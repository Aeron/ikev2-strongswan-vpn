# IKEv2 VPN (Strongswan) Server @ Docker

A Docker image to help deploy Strongswan-based IKEv2 VPN on an own server.

## Usage

Run a container with the `NET_ADMIN` capability added:

```sh
docker run -d --name ikev2-vpn --restart=always --cap-add net_admin -p 500:500/udp -p 4500:4500/udp aeron/ikev2-strongswan-vpn:latest
```

Optionally, it’s possible to save/restore a shared secret by mounting the `/etc/ipsec.secrets` file.

To generate a `.mobileconfig` file for macOS/iOS, run the following:

```sh
docker run -it --rm --volumes-from ikev2-vpn -e HOST=example.com aeron/ikev2-strongswan-vpn:latest profile > ikev2-vpn.mobileconfig
```

Replace the `example.com` with the desired domain name; an IP address may be used instead as well.

Then copy this `ikev2-vpn.mobileconfig` file on a machine and install it by double-click, or transfer it on an iOS device via AirDrop.

Also, it’s possible to get a shared secret only:

```sh
docker run -it --rm --volumes-from ikev2-vpn -e HOST=example.com aeron/ikev2-strongswan-vpn:latest secret
```

## IPv6 Support

Docker has IPv6 support out-of-the-box, but it needs to be enabled manually in daemon configuration and a network created afterward. More on this in the official [Docker documentation](https://docs.docker.com/config/daemon/ipv6/).
