# IKEv2 VPN (Strongswan) Server @ Docker

A Docker image to help deploy [Strongswan](https://strongswan.org)-based IKEv2 VPN on an own server.

By default, the minimum configuration is [CNSA Suite](https://apps.nsa.gov/iaarchive/programs/iad-initiatives/cnsa-suite.cfm) compliant.

## Usage

Run a container with the `--privileged` flag:

```sh
docker run -d --privileged --name ikev2-vpn --restart=always -p 500:500/udp -p 4500:4500/udp aeron/ikev2-strongswan-vpn:latest
```

Or, it’s always possible to run it only with the `NET_ADMIN` capability:

```sh
docker run -d --name ikev2-vpn --restart=always --cap-add net_admin -p 500:500/udp -p 4500:4500/udp aeron/ikev2-strongswan-vpn:latest
```

**Note**: In this case, related [kernel parameters setup](#kernel-parameters) required before.

### Shared secret

To get a shared secret only, use the following:

```sh
docker run -it --rm --volumes-from ikev2-vpn aeron/ikev2-strongswan-vpn:latest secret
```

Optionally, it’s possible to save/restore a shared secret by mounting the `/etc/ipsec.secrets` file.

### Device Management Profile

To generate a `.mobileconfig` file for macOS/iOS, run the following:

```sh
docker run -it --rm --volumes-from ikev2-vpn -e HOST=example.com aeron/ikev2-strongswan-vpn:latest profile > ikev2-vpn.mobileconfig
```

Replace the `example.com` with the desired domain name; an IP address may be used instead as well.

Then copy this `ikev2-vpn.mobileconfig` file on a machine and install it by double-click, or transfer it on an iOS device via AirDrop.

If there’s a need to identify different clients, then `LOCAL_ID` value could be supplied:

```sh
docker run -it --rm --volumes-from ikev2-vpn -e HOST=example.com -e LOCAL_ID=john.example.com aeron/ikev2-strongswan-vpn:latest profile > ikev2-vpn.mobileconfig
```

Usually, the `LOCAL_ID` should be an IP address, FQDN, UserFQDN, or ASN1DN, but a simple name suits as well.

## Caveats

### Kernel Parameters

If a container was never run in privileged mode and such an approach is undesirable, then run the following first:

```sh
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv6.conf.eth0.proxy_ndp=1
```

### Kernel Modules

Running container logs may contain something similar to this:

```text
ip6tables-restore: unable to initialize table 'nat'
```

Probably, Docker doesn’t load a proper kernel module for IPv6 NAT, so it’ll be necessary to run `modprobe` first:

```sh
sudo modprobe ip6table_nat
```

Or simply put a config in `/lib/modules-load.d/` permanently.

## IPv6 Support

Docker has IPv6 support out-of-the-box, but it needs to be enabled manually in daemon configuration and a network created afterward. More on this in the official [Docker documentation](https://docs.docker.com/config/daemon/ipv6/).
