FROM debian:stretch-slim

ENV LANG C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    strongswan \
    iptables \
    procps \
    ndppd \
    ca-certificates \
    openssl

RUN rm -rf /var/lib/apt/lists/*

COPY etc/* /etc/
COPY profiles/* /profiles/
COPY entrypoint.sh .

RUN rm /etc/ipsec.secrets

VOLUME /etc
EXPOSE 500/udp 4500/udp

ENTRYPOINT [ "/entrypoint.sh" ]
