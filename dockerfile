FROM bitnami/minideb:bullseye

LABEL org.opencontainers.image.source https://github.com/Aeron/ikev2-strongswan-vpn
LABEL org.opencontainers.image.licenses MIT

RUN install_packages \
    libstrongswan-standard-plugins \
    strongswan \
    strongswan-swanctl \
    charon-systemd \
    iptables \
    procps \
    ca-certificates \
    openssl \
    gettext-base

COPY etc/swanctl.conf /etc/swanctl/swanctl.conf
COPY etc/strongswan.conf /etc/strongswan.conf
COPY *.rules /etc/

COPY profile.xml .
COPY entrypoint.sh .

RUN echo "" > /etc/ipsec.secrets

VOLUME /etc
VOLUME /var/run

EXPOSE 500/udp 4500/udp

ENV IPSEC_AUTO_MIGRATE 1

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "start" ]
