FROM bitnami/minideb:bullseye

LABEL org.opencontainers.image.source https://github.com/Aeron/ikev2-strongswan-vpn
LABEL org.opencontainers.image.licenses MIT

RUN install_packages \
    libstrongswan-standard-plugins \
    strongswan \
    iptables \
    procps \
    ndppd \
    ca-certificates \
    openssl

COPY etc/* /etc/
COPY profile.xml /
COPY entrypoint.sh .

RUN rm /etc/ipsec.secrets

VOLUME /etc
EXPOSE 500/udp 4500/udp

ENTRYPOINT [ "/entrypoint.sh" ]
