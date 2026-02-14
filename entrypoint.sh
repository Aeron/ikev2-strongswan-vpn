#!/bin/sh

validate_name() {
    if [ -z "$1" ]; then
        return 1
    fi
    # Check for directory traversal attempts
    case "$1" in
        *..* | */* | *.*)
            echo "error: invalid name format: $1" >&2
            return 1
            ;;
    esac
    return 0
}

ensure_uuid_file() {
    local file="$1"
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        gen_uuid > "$file"
        chmod 600 "$file"
    fi
}

compile_profile_psk() {
    if [ -z "$HOST" ]; then
        echo 'error: variable HOST must have a value' >&2
        exit 1
    fi

    ensure_uuid_file /profile.uuid
    ensure_uuid_file /service.uuid

    PROFILE_NAME='IKEv2 VPN'
    PROFILE_ID=$(echo "$HOST" | tr -s '.' '\n' | tac | tr -s '\n' '.' | head -c -1)
    PROFILE_UUID=$(cat /profile.uuid)

    SERVICE_NAME='VPN (IKEv2)'
    SERVICE_NAME_ALT=$HOST
    SERVICE_ID="$PROFILE_ID.shared-configuration"
    SERVICE_UUID=$(cat /service.uuid)

    REMOTE_ADDRESS=$HOST
    REMOTE_ID=$1

    if [ -z "$LOCAL_ID" ];then
        LOCAL_ID=$1
    fi

    SHARED_SECRET=$(get_psk "$1")

    export \
        PROFILE_NAME \
        PROFILE_ID \
        PROFILE_UUID \
        SERVICE_NAME \
        SERVICE_NAME_ALT \
        SERVICE_ID \
        SERVICE_UUID \
        REMOTE_ADDRESS \
        REMOTE_ID \
        LOCAL_ID \
        SHARED_SECRET

    envsubst < /profile-psk.xml
}

add_psk() {
    if ! validate_name "$1"; then
        return 1
    fi

    KEY=$(echo "$2" | xargs)

    if [ -z "$KEY" ]; then
        KEY=$(gen_psk)
    fi

    local psk_file="/etc/swanctl/conf.d/psk-$1.conf"
    printf 'ike-%s {\n    secret = "%s"\n}\n' "$1" "$KEY" > "$psk_file"
    chmod 600 "$psk_file"
}

del_psk() {
    if ! validate_name "$1"; then
        return 1
    fi

    local psk_file="/etc/swanctl/conf.d/psk-$1.conf"
    if [ ! -f "$psk_file" ]; then
        echo "error: PSK credential '$1' does not exist" >&2
        return 1
    fi
    rm "$psk_file"
}

get_psk() {
    if ! validate_name "$1"; then
        return 1
    fi

    local psk_file="/etc/swanctl/conf.d/psk-$1.conf"
    if [ ! -f "$psk_file" ]; then
        echo "error: PSK credential '$1' does not exist" >&2
        return 1
    fi

    grep -oEi 'secret.+' "$psk_file" \
    | grep -oEi '"[a-z0-9=+/]+"' \
    | head -1 \
    | tr -d '"'
}

set_psk_id() {
    if ! validate_name "$1"; then
        return 1
    fi

    KEY=$(get_psk "$1") || return 1

    local psk_file="/etc/swanctl/conf.d/psk-$1.conf"
    printf \
        'ike-%s {\n    id = "%s"\n    secret = "%s"\n}\n' \
        "$1" "$1" "$KEY" \
    > "$psk_file"
    chmod 600 "$psk_file"
}

gen_psk() {
    openssl rand -base64 32
}

gen_uuid() {
    cat /proc/sys/kernel/random/uuid
}

strip_name() {
    echo "$1" | tr '@&+.:' '-' | tr -d '=!%^#$\/()[]{}|;<>, ' | xargs
}

migrate_psk() {
    PAIRS=$(
        grep -oEi '^(.+)?:\sPSK\s.([a-z0-9=+/]+).' /etc/ipsec.secrets \
        | tr -s ' PSK ' '#' \
        | tr -d " #'\""
    )

    echo "$PAIRS" | while IFS= read -r PAIR; do
        [ -z "$PAIR" ] && continue

        ID=$(echo "$PAIR" | cut -d ":" -f1)
        ID=$(strip_name "$ID")
        KEY=$(echo "$PAIR" | cut -d ":" -f2)

        [ -z "$ID" ] && ID=default

        if add_psk "$ID" "$KEY"; then
            echo "migration: PSK secret moved into /etc/swanctl/conf.d/psk-$ID.conf"
        else
            echo "migration: failed to migrate PSK for ID: $ID" >&2
        fi
    done

    echo 'migration: consider to remove /etc/ipsec.secrets'
}

set_logging_mode() {
    if [ ! -w /etc/strongswan.conf ]; then
        echo 'error: /etc/strongswan.conf is not writable' >&2
        exit 1
    fi

    case "$LOGGING_MODE" in
        'zero') LEVEL=-1;;
        'less') LEVEL=0;;
        'some') LEVEL=1;;
        *)
            echo 'error: variable LOGGING_MODE must be "zero", "less", "some", or unset'
            exit 1
        ;;
    esac

    for s in default app asn cfg dmn enc esp ike imc imv job knl lib mgr net pts tls tnc
    do
        sed -i "s/$s = \\S*$/$s = $LEVEL/g" /etc/strongswan.conf
    done

    echo "logging: $LOGGING_MODE mode"
}

wait_for_charon() {
    local timeout=30
    local elapsed=0
    local vici_socket="/var/run/charon.vici"

    echo "charon: waiting for daemon to be ready..."

    # First, wait for the socket to exist
    while [ $elapsed -lt $timeout ]; do
        if [ -S "$vici_socket" ]; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if [ $elapsed -ge $timeout ]; then
        echo "error: charon vici socket not available within ${timeout}s" >&2
        return 1
    fi

    echo "charon: vici socket available, verifying communication..."

    # Now verify we can actually communicate with charon
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if swanctl --stats >/dev/null 2>&1; then
            echo "charon: ready and responding to commands"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "error: charon not responding to commands within ${timeout}s" >&2
    return 1
}

start_strongswan() {
    # NOTE: sysctl requires privileged mode
    # Check current value first to avoid errors in non-privileged mode
    current_ipv4=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    if [ "$current_ipv4" != "1" ]; then
        if ! sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1; then
            echo "warning: failed to enable IPv4 forwarding (current: $current_ipv4)" >&2
            echo "warning: container may need to run in privileged mode or with --sysctl flags" >&2
        fi
    fi

    current_ipv6=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo "0")
    if [ "$current_ipv6" != "1" ]; then
        if ! sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1; then
            echo "warning: failed to enable IPv6 forwarding (current: $current_ipv6)" >&2
            echo "warning: container may need to run in privileged mode or with --sysctl flags" >&2
        fi
    fi

    current_ndp=$(sysctl -n net.ipv6.conf.eth0.proxy_ndp 2>/dev/null || echo "0")
    if [ "$current_ndp" != "1" ]; then
        if ! sysctl -w net.ipv6.conf.eth0.proxy_ndp=1 >/dev/null 2>&1; then
            echo "warning: failed to enable IPv6 proxy NDP (current: $current_ndp)" >&2
            echo "warning: container may need to run in privileged mode or with --sysctl flags" >&2
        fi
    fi

    if ! iptables-legacy-restore < /etc/ipv4.nat.rules; then
        echo "error: failed to restore IPv4 iptables rules" >&2
        exit 1
    fi

    if ! ip6tables-legacy-restore < /etc/ipv6.nat.rules; then
        echo "error: failed to restore IPv6 iptables rules" >&2
        exit 1
    fi

    [ -n "$LOGGING_MODE" ] && set_logging_mode

    # NOTE: a bit ugly but having systemctl is excessive
    charon-systemd &

    if ! wait_for_charon; then
        echo "error: failed to start charon-systemd" >&2
        exit 1
    fi

    if ! swanctl --load-all --noprompt; then
        echo "error: failed to load swanctl configuration" >&2
        exit 1
    fi

    # NOTE: it will try to migrate existing ipsec.secrets automatically
    if [ -n "$IPSEC_AUTO_MIGRATE" ] \
    && [ -f /etc/ipsec.secrets ] \
    && [ -s /etc/ipsec.secrets ]; then
        if migrate_psk; then
            swanctl --load-creds --noprompt
        else
            echo "warning: PSK migration encountered errors" >&2
        fi
    fi

    # shellcheck disable=SC2046
    wait $(jobs -p)
}

set -- "$1" "$(strip_name "$2")"

if [ -z "$2" ]; then
    set -- "$1" default
fi

# shellcheck disable=SC2016
HELP='Usage: /entrypoint.sh [COMMAND [<NAME>]]

Commands:
  add-psk      Add a new PSK credential
  get-psk      Print a secret for a PSK credential
  del-psk      Delete a PSK credential
  set-psk-id   Enforce an ID usage for a PSK credential
  profile-psk  Print a PSK device management profile for macOS/iOS
               [requires: $HOST]
  start        Start the charon-systemd
               [default]

Parameters:
  <NAME>       A desired PSK credential name
               [default: "default"]
'

case "$1" in
    'add-psk')
        add_psk "$2"
        swanctl --load-creds --noprompt
        ;;
    'del-psk')
        del_psk "$2"
        swanctl --load-creds --clear --noprompt
        ;;
    'get-psk')
        get_psk "$2"
        ;;
    'set-psk-id')
        set_psk_id "$2"
        swanctl --load-creds --clear --noprompt
        ;;
    'profile-psk')
        compile_profile_psk "$2"
        ;;
    'start')
        start_strongswan
        ;;
    *)
        echo "$HELP"
        ;;
esac
