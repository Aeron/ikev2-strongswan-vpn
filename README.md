# IKEv2 Strongswan VPN Docker Image

A compact [Strongswan][strongswan] IKEv2 VPN Docker image based on
[`bitnami/minideb`][minideb] base image.

By default, the minimum configuration is [CNSA Suite][cnsa] compliant.

[strongswan]: https://strongswan.org
[minideb]: https://hub.docker.com/r/bitnami/minideb
[cnsa]: https://apps.nsa.gov/iaarchive/programs/iad-initiatives/cnsa-suite.cfm

## Usage

This image is available as [`docker.io/aeron/ikev2-strongswan-vpn`][docker]
and [`ghcr.io/Aeron/ikev2-strongswan-vpn`][github]. You can use them both
interchangeably.

[docker]: https://hub.docker.com/r/aeron/ikev2-strongswan-vpn
[github]: https://github.com/Aeron/ikev2-strongswan-vpn/pkgs/container/ikev2-strongswan-vpn

```sh
docker pull docker.io/aeron/ikev2-strongswan-vpn
# …or…
docker pull ghcr.io/aeron/ikev2-strongswan-vpn
```

### Container Running

Run a container with the `--privileged` flag:

```sh
docker run -d --privileged --name ikev2-vpn --restart=unless-stopped \
    -p 500:500/udp \
    -p 4500:4500/udp \
    aeron/ikev2-strongswan-vpn:latest
```

Or, it is always possible to run it only with the `NET_ADMIN` capability:

```sh
docker run -d --name ikev2-vpn --restart=unless-stopped \
    --cap-add net_admin \
    -p 500:500/udp \
    -p 4500:4500/udp \
    aeron/ikev2-strongswan-vpn:latest
```

**Note**: In this case, related [kernel parameters setup](#kernel-parameters) must be
set before.

#### Logging Mode

The `LOGGING_MODE` environment variable could be convenient for setting a different
logging level. It accepts the following values:

- `zero` for almost silent logging;
- `less` for only necessary info;
- `some` for standard logging and errors.

Unset value behaves as `some`, yet adds debugging for `cfg`, `ike`, and `net`
subsystems.

For finer tuning better to mount a custom `/etc/strongswan.conf`.

### Entrypoint Options

The entrypoint script supports the following commands and parameters:

```text
Usage: /entrypoint.sh [COMMAND [<NAME>]]

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
```

### PSK Credentials

#### Management

To add, get, or delete a pre-shared key, use the following command pattern:

```sh
docker run -it --rm --volumes-from ikev2-vpn \
    aeron/ikev2-strongswan-vpn:latest \
    COMMAND [<NAME>]
```

Supported commands and parameters are described [above](#entrypoint-options).

If you are running the image for the first time and only need a single default
credential, then do this:

```sh
docker run -it --rm --volumes-from ikev2-vpn \
    aeron/ikev2-strongswan-vpn:latest \
    add-psk
docker run -it --rm --volumes-from ikev2-vpn \
    aeron/ikev2-strongswan-vpn:latest \
    get-psk
```

It will create a new PSK credetial and display it. If you want a one-click solution
instead, then check out [the profile section](#device-management-profile).

#### Persistency

It is possible to save/restore pre-shared keys by mounting the `/etc/swanctl/conf.d`
directory. For example:

```sh
docker run -d --name ikev2-vpn --restart=unless-stopped \
    --cap-add net_admin \
    -p 500:500/udp \
    -p 4500:4500/udp \
    -v /your/local/path:/etc/swanctl/conf.d:rw \
    aeron/ikev2-strongswan-vpn:latest
```

Simply replace the `/your/local/path` with a desired directory path.

#### Migration

There is a auto-migration support for prior-`swanctl` deployments.

If PSK credentials are still stored in `/etc/ipsec.secrets`, entrypoint script will
try to migrate them to separate `/etc/swanctl/conf.d/psk-*.conf` files.

While existing `/etc/ipsec.secrets` will not be touched, it is better to manually
remove it at some point. Before you decide to do so, ensure that both credential
volumes are mounted at the same time. It might look like so:

```sh
docker run -d --name ikev2-vpn --restart=unless-stopped \
    --cap-add net_admin \
    -p 500:500/udp \
    -p 4500:4500/udp \
    -v /path/to/old/ipsec.secrets:/etc/ipsec.secrets:ro \
    -v /path/to/new/config:/etc/swanctl/conf.d:rw \
    aeron/ikev2-strongswan-vpn:latest
```

It will guarantee you have a migrated configuration safely stored.

**Important**: Before removing an older configuration, verify that secrets in both
configurations are the same.

If you already migrated a configuration but do not want to remove or unmount
`/etc/ipsec.secrets` yet, it is possible to disable auto-migration, by unsetting the
`IPSEC_AUTO_MIGRATE` environment variable.

**Important**: The resulting `/etc/swanctl/conf.d/psk-*.conf` files will not include
IKE-PSK ID fields because—before [version 23.0][release-23]—compiled profiles never
strictly addressed the remote ID field. So a client’s remote ID will be treated
as `%any`.

[release-23]: https://github.com/Aeron/ikev2-strongswan-vpn/releases/tag/23.0

### Device Management Profile

To generate a `.mobileconfig` file for macOS/iOS, run the following:

```sh
docker run -it --rm --volumes-from ikev2-vpn \
    -e HOST=example.com \
    aeron/ikev2-strongswan-vpn:latest \
    profile-psk > ikev2-vpn.mobileconfig
```

Replace the `example.com` with the desired domain name; an IP address may be used
instead as well. The `HOST` environment variable is required.

If there is a need to identify different clients, then `LOCAL_ID` value could be
supplied:

```sh
docker run -it --rm --volumes-from ikev2-vpn \
    -e HOST=example.com \
    -e LOCAL_ID=john.example.com \
    aeron/ikev2-strongswan-vpn:latest \
    profile-psk > ikev2-vpn.mobileconfig
```

Usually, the `LOCAL_ID` should be an IP address, FQDN, UserFQDN, or ASN1DN, but a
simple name suits as well.

**Important**: The `LOCAL_ID` must be unique for each simultaneous connection.

#### (Un)Installation

Copy the resulting `ikev2-vpn.mobileconfig` file on a macOS machine, then add it by
double-clicking. Or transfer it on an iOS device via AirDrop. Also, it can be stored
in iCloud Files and added from there.

To install it, search “Profile” in the device settings. It will display all profiles
waiting for installation. Proceed from there: click on a profile, then click an
“install” button, and authorize it. As a result, there must be a new VPN added with a
familiar name.

To remove a VPN service, search “Profile” in a device settings, then delete a
previously installed profile.

#### UUIDs Persistency

To avoid reproducing excessive profiles and VPN services on a device, profile/service
UUIDs can be saved/restored by mounting volumes `/profile.uuid` and `/service.uuid`,
like so:

```sh
docker run -it --rm --volumes-from ikev2-vpn \
    -e HOST=example.com \
    -v /path/to/profile.uuid:/profile.uuid \
    -v /path/to/service.uuid:/service.uuid \
    aeron/ikev2-strongswan-vpn:latest \
    profile-psk > ikev2-vpn.mobileconfig
```

It will generate new UUIDs once and re-use them next time.

**Note**: Such volumes also can be mounted for a main container somewhat permanently.
Then there will be no need to specify it for the profile compilation.

## Caveats

### Kernel Parameters

If a container was never run in privileged mode and such an approach is undesirable,
then run the following first:

```sh
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv6.conf.eth0.proxy_ndp=1
```

Or put a config in `/etc/sysctl.d/` permanently, like so:

```sh
echo net.ipv4.ip_forward=1 | sudo tee /etc/sysctl.d/network-tune.conf
echo net.ipv6.conf.all.forwarding=1 | sudo tee /etc/sysctl.d/network-tune.conf
echo net.ipv6.conf.eth0.proxy_ndp=1 | sudo tee /etc/sysctl.d/network-tune.conf
```

### Kernel Modules

Running container logs may contain something similar to this:

```text
ip6tables-restore: unable to initialize table 'nat'
```

Probably, Docker does not load a proper kernel module for IPv6 NAT, so it will be
necessary to run `modprobe` first:

```sh
sudo modprobe ip6table_nat
```

Or simply put a config in `/lib/modules-load.d/` permanently, like so:

```sh
echo ip6table_nat | sudo tee /lib/modules-load.d/ip6table-nat.conf
```

## IPv6 Support

Docker has IPv6 support out-of-the-box, but it needs to be enabled manually in daemon
configuration and a network created afterward. More on this in the official
[Docker documentation][docs].

[docs]: https://docs.docker.com/config/daemon/ipv6/
