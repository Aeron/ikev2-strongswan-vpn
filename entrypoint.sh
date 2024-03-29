#!/bin/sh

compile_profile_psk() {
    [ -z "$HOST" ] \
    && echo 'error: variable HOST must have a value' \
    && exit 1

    if [ ! -f /profile.uuid ] || [ ! -s /profile.uuid ]; then
        gen_uuid > /profile.uuid
    fi

    if [ ! -f /service.uuid ] || [ ! -s /service.uuid ]; then
        gen_uuid > /service.uuid
    fi

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
    KEY=$(echo "$2" | xargs)

    if [ -z "$KEY" ]; then
        KEY=$(gen_psk)
    fi

    printf 'ike-%s {\n    secret = "%s"\n}\n' "$1" "$KEY" \
    > /etc/swanctl/conf.d/psk-"$1".conf
}

del_psk() {
    rm /etc/swanctl/conf.d/psk-"$1".conf
}

get_psk() {
    grep -oEi 'secret.+' /etc/swanctl/conf.d/psk-"$1".conf \
    | grep -oEi '"[a-z0-9=+/]+"' \
    | head -1 \
    | tr -d '"'
}

set_psk_id() {
    KEY=$(get_psk "$1")

    printf \
        'ike-%s {\n    id = "%s"\n    secret = "%s"\n}\n' \
        "$1" "$1" "$KEY" \
    > /etc/swanctl/conf.d/psk-"$1".conf
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

    for PAIR in $PAIRS; do
        ID=$(echo "$PAIR" | cut -d ":" -f1)
        ID=$(strip_name "$ID")
        KEY=$(echo "$PAIR" | cut -d ":" -f2)

        [ -z "$ID" ] && ID=default

        add_psk "$ID" "$KEY"

        echo "migration: PSK secret moved into /etc/swanctl/conf.d/psk-$ID.conf"
        echo 'migration: consider to remove /etc/ipsec.secrets'
    done

    # echo "" > /etc/ipsec.secrets
}

set_logging_mode() {
    [ ! -w /etc/strongswan.conf ] \
    && echo 'error: /etc/strongswan.conf is not writable' \
    && exit 1

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
        sed -ie "s/$s = \S*$/$s = $LEVEL/g" /etc/strongswan.conf
    done

    echo "logging: $LOGGING_MODE mode"
}

start_strongswan() {
    # NOTE: sysctl requires privileged mode
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv6.conf.all.forwarding=1
    sysctl -w net.ipv6.conf.eth0.proxy_ndp=1

    iptables-legacy-restore < /etc/ipv4.nat.rules
    ip6tables-legacy-restore < /etc/ipv6.nat.rules

    [ -n "$LOGGING_MODE" ] && set_logging_mode

    # NOTE: a bit ugly but having systemctl is excessive
    charon-systemd &
    sleep 5
    swanctl --load-all --noprompt

    # NOTE: it will try to migrate existing ipsec.secrets automatically
    [ -n "$IPSEC_AUTO_MIGRATE" ] \
    && [ -f /etc/ipsec.secrets ] \
    && [ -s /etc/ipsec.secrets ] \
    && migrate_psk \
    && swanctl --load-creds --noprompt

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
