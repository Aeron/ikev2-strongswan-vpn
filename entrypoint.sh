#!/bin/sh

compile_profile() {
    [ -z $HOST ] && \
        echo "\033[0;31mEnvironment variable HOST is required\033[0m" && \
        exit 1

    [ -z $1 ] && PROFILE="default" || PROFILE=$1

    if [ ! -f /profiles/$PROFILE.xml ]; then
        echo "\033[0;31mInvalid profile $PROFILE\033[0m"
        exit 2
    fi

    PROFILE_NAME='IKEv2 VPN'
    PROFILE_ID=$(echo "$HOST" | tr -s '.' '\n' | tac | tr -s '\n' '.' | head -c -1)
    PROFILE_UUID=$(cat /proc/sys/kernel/random/uuid)

    SERVICE_NAME='VPN (IKEv2)'
    SERVICE_ID="$PROFILE_ID.shared-configuration"
    SERVICE_UUID=$(cat /proc/sys/kernel/random/uuid)

    REMOTE_ADDRESS=$HOST
    REMOTE_ID=$HOST

    get_secret

    eval "echo \"$(cat /profiles/$PROFILE.xml)\""
}

get_secret() {
    if [ ! -f /etc/ipsec.secrets ]; then
        echo ": PSK '$(openssl rand -base64 32)'" > /etc/ipsec.secrets
    fi

    SHARED_SECRET=$(cat /etc/ipsec.secrets | grep -oEi "[a-z0-9=+/]+" | tail -1)
    export SHARED_SECRET
}

show_secret() {
    get_secret

    echo "\033[0;36mSecret: $SHARED_SECRET\033[0m"
}

start_ipsec() {
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv6.conf.all.forwarding=1
    sysctl -w net.ipv6.conf.eth0.proxy_ndp=1

    iptables-restore < /etc/ipv4.nat.rules
    ip6tables-restore < /etc/ipv6.nat.rules

    ndppd -c /etc/ndppd.conf -d

    rm -f /var/run/starter.charon.pid

    ipsec start --nofork
}

case "$1" in
    "profile")
        compile_profile $2
        ;;
    "secret")
        show_secret
        ;;
    *)
        start_ipsec
        ;;
esac
