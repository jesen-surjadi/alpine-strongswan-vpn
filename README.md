# StrongSwan VPN + Alpine Linux

This repository contains a Dockerfile for generating
an image with [StrongSwan](https://www.strongswan.org/) and
[Alpine Linux](https://alpinelinux.org/).

This image can be used on the server or client in a variety
of configurations.

The reference configuration in this repository and following
guidelines are intended to provide an attempt at a
best-practice example for setting up a universal VPN server
that can handle modern IKEv2 roadwarrior clients (with IPv6
support in mind).

## Server Setup
## Quick Start

* Pick a name for the `$STRONGSWAN_DATA` data volume container. It's recommended to
  use the `strongswan_data` prefix to operate seamlessly with the reference systemd
  service.  Users are encourage to replace `example` with a descriptive name of
  their choosing.

        STRONGSWAN_DATA="strongswan_data"

* Initialize the `$STRONGSWAN_DATA` container that will hold the configuration files
  and certificates.  The container will prompt for a passphrase to protect the
  private key used by the newly generated certificate authority.

        docker volume create --name $STRONGSWAN_DATA
		
* Update ipsec.conf with your VPN hostname or ip address
        docker run -v $STRONGSWAN_DATA:/config --rm alpine-strongswan-vpn strongswan_genconfig -u VPN.SERVERNAME.COM
		
* Generate VPN root CA key, CA Certificate, server private key and self-signed server certificate
        docker run -v $STRONGSWAN_DATA:/config --rm alpine-strongswan-vpn strongswan_initpki

* Generate and retrieve client certificate 
        docker run -v $STRONGSWAN_DATA:/config --rm alpine-strongswan-vpn strongswan_genclientcert CLIENTNAME > $CLIENTNAME.p12
		
* Start Strongswan server process
        docker run -v $STRONGSWAN_DATA:/config -d -p 500:500/udp -p 4500:4500/udp --cap-add=NET_ADMIN alpine-strongswan-vpn


## Next Steps


### Edit configuration, setup certificates

review the rules in `ipsec.d/firewall.updown`. 


If running behind a router, you'll need to forward
ports 500/udp and 4500udp. If you have a local firewall,
you'll need to accept packets from ports 500/udp, 4500/udp,
and possibly rotocol 50 (ESP), and protocol 51 (AH).

Also a caveat for docker hosts receiving their IP and
gateway from router advertisements. With IPv6 packet
forwarding enabled, advertisements are disabled unless
you set `accept_ra=2` for your interface with sysctl or
in `/etc/network/interfaces`.

### Start Docker container

Running this particular Docker container typically requires
running with elevated privileges including `--cap-add=NET_ADMIN`
and `--net=host` or `-p 500:500/udp -p 4500:4500/udp`. It will have permission to modify your Docker
host's networking and iptables configuration.

You may need to enable packet forwarding and ndp proxying on your
docker host via sysctl or /etc/sysctl.conf:

```
sudo sysctl net.ipv4.ip_forward=1
sudo sysctl net.ipv6.conf.all.forwarding=1
sudo sysctl net.ipv6.conf.all.proxy_ndp=1
sudo iptables -A FORWARD -j ACCEPT
```

### Check status

There are various ways to check on StrongSwan, including tailing
the Docker logging output (stdout/stderr), the `ipsec` command,
and the `swanctl` command:

    docker logs -f --tail 100 strongswan
    docker exec -it strongswan ipsec statusall
    docker exec -it strongswan swanctl --list-sas

## Client Setup

### OSX 10.12 Sierra

Crypto: IKEv2 AES256-SHA256-MODP2048

On OSX, you'll need to import and trust the client certificate
and the CA certificate from `config/ipsec.d/cacerts/caCert.pem`
and possibly the exported .p12 file if you are using
certificate-based authentication. For iOS, you can email yourself
the pem and .p12 and import them as a new profile onto the device.

* For eap password, select Username for the authentication type
* For eap cert, select Certificate for the authentication type
* For pubkey cert, select None for the authentication type and select cert

### Windows 10

Crypto: IKEv2 AES256-SHA256-MODP1024

For Windows, you'll need to import the certificates into your
trusted root CA store (Machine) from the exported .p12 file.

After creating the VPN connection, go to the properties for the
network connection, click on the Networking tab, and go to the
IPv4 connection properties. Click Advanced and check the box,
"Use default gateway on remote network" to allow tunneling.

To enable IPv6 gateway you'll need aministrator access. Run
the first command to find your interface number (`Idx`) which
should be named the same as the name of your VPN connection.

    netsh int ipv6 show interfaces
    netsh interface ipv6 add route ::/0 interface=INTERFACE_NUMBER

In Windows, modp2048 Diffie Hellman is disabled by default, you
can change this behavior by creating or setting the following
registry REG_DWORD to a (Hex) value of 0, 1 or 2. No reboot should
be required.

    HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Rasman\Parameters\NegotiateDH2048_AES256

* 0 = disable (default)
* 1 = enable modp2048
* 2 = enforce modp2048 and aes-256-cbc

### iOS 10.x

Crypto: IKEv2 AES256-SHA256-MODP2048

To setup, go to Settings -> General -> VPN. Add a new VPN configuration
with type "IKEv2". Enter a description, server, remote ID, and local
ID. Local ID should typically be your username. For authentication,
you can select "Username" for EAP+mschapv2, "Certificate" for EAP+tls, or
"None" for pubkey or PSK-based authentication.

### Android

Crypto: IKEv2 CHACHA20POLY1305-PRFSHA256-ECP256 (via strongSwan VPN Client)

Native Android VPN on Android 5 Lollipop and Andorid 6 Marshmallow is
limited to IKEv1 which is not supported in this configuration.

Most users should consider using the excellent [strongSwan VPN Client](https://play.google.com/store/apps/details?id=org.strongswan.android&hl=en).

### Linux

Crypto: IKEv2 CHACHA20POLY1305-PRFSHA256-NEWHOPE128

In addition to serving VPN connections, StrongSwan will act as a client.
You can use this Docker image on Linux to act as a client (and it can act
as a client and server simultaneously). (Note: You should only run one
instance of the strongswan Docker container per host.)

To configure a StrongSwant client to be used with this Docker image,
you can use same configuration for the server (above), namely:
`ipsec.conf`, `ipsec.secrets`, `strongswan.conf`, and any generated
cacerts and client certificates in `ipsec.d/cacerts` and `ipsec.d/certs`.

The `ipsec.conf` file has rules for a client connection called
"home". If you haven't already, start up the Docker container the same
way you would when starting it for the server (above) and issue
commands such as the ones below to connect, check status, and
disconnect:

    docker exec -it strongswan ipsec up home
    docker exec -it strongswan ipsec status
    docker exec -it strongswan ipsec down home

You can also choose to install the StrongSwan package from your
Linux distribution and use the files in `config/` as a reference
for setting it up. If you're looking for a GUI, there's a
NetworkManager plugin (in Ubuntu, the package is called
`network-manager-strongswan`).

## Other Info

### Cipher Suites

This configuration attemps to balance higher grade ciphers with
performance and compatibility with the lastest versions of OSX,
Windows, Linux, and mobile devices. The list of ciphers is intentionally
kept short, users can always modify the list if higher grade
encryption is desired.

This build uses OpenSSL rather than LibreSSL in order to support
the NIST Elliptic Curves (ecp256, etc). In addition, OpenSSL provides
the same functionality provided by gmp.

I would love hearing any feedback regarding the ciphers or overall
ways we can improve the current settings.

### References

Useful resources:

* [Conn Reference](https://wiki.strongswan.org/projects/strongswan/wiki/ConnSection)
* [FARP for IPv6](https://wiki.strongswan.org/issues/1008)
* [IKEv2 Cipher Suites](https://wiki.strongswan.org/projects/strongswan/wiki/IKEv2CipherSuites)
* [StrongSwan Autoconf](https://wiki.strongswan.org/projects/strongswan/wiki/Autoconf)
* [StrongSwan ikev2 Tests](https://www.strongswan.org/testresults.html)
* [StrongSwan on Windows 7](https://wiki.strongswan.org/projects/strongswan/wiki/Windows7)

