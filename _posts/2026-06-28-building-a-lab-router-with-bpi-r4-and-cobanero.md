---
layout: post
title: "Building a Lab Router with Banana Pi BPI-R4 and Cobanero"
date: 2026-06-28 10:00:00 +0000
categories: post
image: "/assets/posts/2026-06-28/cobanero.png"
header: "/assets/posts/2026-06-28/cobanero-header.png"
tags: [linux, opensuse, networking, router, bpi-r4, cobanero, ovs, docker]
author: Tobias Geiser
excerpt_separator: <!--more-->
---

The Banana Pi BPI-R4 is a useful ARM64 board for building a compact lab router. It has enough CPU, memory, and network capability to run routing, firewalling, VLANs, and a small set of infrastructure services.
<!--more-->

This article describes a lab setup using fictional addresses and hostnames. It is intended as a safe reference design for building a router with Open vSwitch, Docker, systemd, and Cobanero — an in-house, container-based router project (firewall, DHCP, DNS, NTP, syslog, and Grafana monitoring, each as its own container) that this build wires together.

### Lab goals

The goal is to build a small router that can provide the core services usually needed in a segmented lab network.

The router should provide:

- VLAN routing
- firewall policy
- DNS
- DHCP
- NTP
- syslog
- SNMP monitoring
- Prometheus
- Grafana

The design keeps the router host responsible for bootstrapping, physical networking, and performance tuning. Application services run as containers and are managed by systemd.

![Cobanero lab router architecture: 10G SFP+ WAN, Open vSwitch VLAN matrix, firewall and DHCP services, and high-speed LAN routing.](/assets/posts/2026-06-28/cobanero-network-layout.png){: style="max-width: 100%; min-width: 100%; height: auto"}

### Example hardware

The lab router uses the following example hardware profile.

```text
Board:        Banana Pi BPI-R4
Architecture: ARM64
Networking:   Ethernet ports with VLAN trunking
Storage:      eMMC, SD card, or NVMe depending on the build
Switching:    Open vSwitch
Services:     Docker containers
Persistence:  systemd units
```

The exact storage and interface naming depends on the image and kernel used. Treat the names in this article as examples and adapt them to your board.

### Example lab network

Use documentation and private ranges when writing examples. The following layout uses `192.0.2.0/24`, which is reserved for documentation, and RFC1918 private networks.

```text
Lab domain:           lab.example.internal
Router management IP: 192.0.2.10/24
Management gateway:   192.0.2.1
```

Example VLAN layout:

```text
VLAN 100  Management      192.0.2.0/24
VLAN 200  Transit/WAN     DHCP or lab upstream
VLAN 300  Users           10.10.30.0/24
VLAN 400  Services        10.10.40.0/24
VLAN 500  IoT             10.10.50.0/24
VLAN 600  Monitoring      10.10.60.0/24
```

Example service addresses:

```text
Firewall internal:    10.10.40.1
DNS authoritative:    10.10.40.10
DNS cache:            10.10.40.11
DHCP:                 10.10.40.12
Syslog:               10.10.40.13
NTP:                  10.10.40.14
Prometheus exporter:  10.10.60.10
Prometheus:           10.10.60.11
Grafana:              10.10.60.12
```

In this example, Grafana is reachable at:

```text
http://10.10.60.12:3000
```

### Boot image

For this lab, the BPI-R4 boots from a FIT image.

```text
/boot/bpi-r4.itb
```

The FIT image bundles the kernel, initrd, and device tree. That makes it the single boot artifact the board needs.

After the board boots successfully, check `/boot` and remove stale standalone boot files only if you are sure they are not used by your bootloader.

Common examples of files that may be unused in a FIT-based boot are:

```text
/boot/Image
/boot/uInitrd
/boot/dtb/
/boot/extlinux/
```

Do not remove boot files blindly. First confirm which image your board actually boots.

### Image creation process

The image creation process has two separate concerns: the Linux userspace and the BPI-R4 boot layout.

The userspace image contains the operating system, packages, kernel modules, and the files that will become the root filesystem. The BPI-R4 base image provides the board-specific bootloader and partition layout. Keeping those concerns separate makes the build process easier to reason about.

The high-level process looks like this:

```text
Build or obtain an ARM64 Linux rootfs image
Start from a known-good BPI-R4 base image
Copy the Linux root filesystem into the BPI-R4 root partition
Copy the boot payload into the BPI-R4 boot partition
Generate the FIT image as /boot/bpi-r4.itb
Write the resulting image to the target storage
```

For a lab build, I use a repacking step rather than manually recreating the BPI-R4 partition layout from scratch. The repack step preserves the board-specific bootloader area and replaces the boot and root filesystem payloads with the lab operating system.

Example command shape:

```bash
sudo ./scripts/repack-bpi-r4-image.sh \
  output/images/lab-linux-arm64.img.xz \
  external/cache/images/bpi-r4-base.img.gz \
  output/images/bpi-r4-lab-router.img.gz
```

The source image is the generic ARM64 Linux build. The base image is a known-good BPI-R4 image with the expected bootloader and partition structure. The output image is the final lab router image.

The repack process should do the following:

```text
decompress both images into temporary raw images
attach them as loop devices
locate the source root filesystem
locate the BPI-BOOT and BPI-ROOT partitions
resize BPI-BOOT if needed
format the destination boot and root partitions
copy the source root filesystem into BPI-ROOT
copy the source boot payload into BPI-BOOT
create or normalize boot variables for FIT boot
compress the final image
```

FIT generation requires `mkimage` and `dtc`.

```bash
sudo zypper install u-boot-tools dtc
```

The FIT image is generated from the kernel image, the BPI-R4 device tree, and optional overlays. Conceptually, the generated image is built with `mkimage` from an ITS description.

```text
kernel image      -> Image or Image.gz
base device tree  -> mt7988a-bananapi-bpi-r4.dtb
optional overlays -> SD, eMMC, Wi-Fi, or board-specific overlays
output            -> bpi-r4.itb
```

If the boot partition is small, increase it during repacking. A 512 MiB boot partition leaves enough space for a FIT image, device trees, and future kernel updates.

```bash
sudo BPI_R4_BOOT_SIZE_MIB=512 ./scripts/repack-bpi-r4-image.sh \
  output/images/lab-linux-arm64.img.xz \
  external/cache/images/bpi-r4-base.img.gz \
  output/images/bpi-r4-lab-router.img.gz
```

After the image is created, write it to the target storage. Replace `/dev/sdX` with the correct device for your lab system.

```bash
gzip -dc output/images/bpi-r4-lab-router.img.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Before booting the board, verify that the storage device contains the expected partitions and that the boot partition contains `bpi-r4.itb`.

### Open vSwitch layout

Open vSwitch provides the internal switching fabric for the lab router.

Example bridge layout:

```text
br-mgmt       VLAN 100
br-transit    VLAN 200
br-users      VLAN 300
br-services   VLAN 400
br-iot        VLAN 500
br-monitor    VLAN 600
```

The physical uplink can be configured as a VLAN trunk carrying the lab VLANs.

```text
100,200,300,400,500,600
```

Patch ports can connect internal bridges where needed. Be careful with patch ports and physical switch ports: if both connect the same Layer 2 domain, you can create a loop. Document every patch port and keep unused physical ports disconnected until the topology is clear.

### Cobanero service model

Cobanero describes each service with a container configuration file. A lab profile can define site-specific values such as the domain, VLANs, container addresses, and bridges.

Example profile name:

```text
site_config_lab
```

Example container configuration files:

```text
container/firewall-internal/config.json
container/firewall-external/config.json
container/dns/config.json
container/dns-cache/config.json
container/dhcp/config.json
container/ntp/config.json
container/syslog/config.json
container/prometheus-exporter/config.json
container/prometheus/config.json
container/grafana/config.json
```

Containers are launched through the Cobanero runner.

```bash
/opt/cobanero/app/run.sh -c /opt/cobanero/app/container/<service>/config.json
```

The runner creates the container, attaches its interfaces to Open vSwitch, assigns addresses, and applies VLAN configuration according to the JSON file.

### Systemd persistence

Each production container should have a systemd unit. This keeps startup behavior explicit and makes service status easy to inspect.

Example units:

```text
cobanero-firewall-internal.service
cobanero-firewall-external.service
cobanero-dns.service
cobanero-dns-cache.service
cobanero-dhcp.service
cobanero-ntp.service
cobanero-syslog.service
cobanero-prometheus-exporter.service
cobanero-prometheus.service
cobanero-grafana.service
```

Useful commands:

```bash
systemctl enable cobanero-dns.service
systemctl start cobanero-dns.service
systemctl status cobanero-grafana.service
systemctl restart cobanero-dhcp.service
```

Use systemd for container persistence rather than hiding container startup in ad-hoc boot scripts. Host-level network preparation and tuning can still be handled separately.

### DNS and DHCP

The lab has separate authoritative and caching DNS services.

```text
Authoritative DNS: 10.10.40.10
Caching resolver:  10.10.40.11
```

DHCP runs on the services VLAN.

```text
DHCP server: 10.10.40.12
```

Example DHCP settings for the user VLAN:

```text
Subnet:      10.10.30.0/24
Gateway:     10.10.30.1
DNS:         10.10.40.11
Domain:      lab.example.internal
```

If DHCP clients live on multiple VLANs, place the DHCP server on a service network and use DHCP relay from the firewall or router interfaces.

### Monitoring

Prometheus scrapes the lab router and service exporters.

Example targets:

```text
Node exporter:      10.10.60.10:9100
Prometheus:         10.10.60.11:9090
SNMP target:        192.0.2.10
Blackbox exporter:  10.10.60.10:9115
```

Grafana uses Prometheus as the default datasource. A basic router dashboard should show:

```text
CPU
memory
disk usage
interface traffic
uptime
service health
firewall or log events
```

If node exporter runs in a container, be aware of namespace visibility. CPU and memory may be sufficient for a lab dashboard, but host interfaces and host filesystems may require additional mounts or host namespace access.

### Performance tuning

Start with no artificial bandwidth caps unless you are explicitly testing traffic shaping. Add QoS only when there is a real requirement.

Useful tuning areas include:

```text
BBR congestion control
fq_codel or fq qdisc
larger TCP receive and send buffers
RPS/XPS on busy interfaces
no unnecessary shaping on fast paths
```

The goal is to keep the baseline router fast and predictable. Shaping, rate limits, and queue policies can be layered on later for specific experiments.

### Validation checklist

After the setup is complete, validate each layer independently.

```text
Boot image loads correctly
Management IP responds
Open vSwitch bridges exist
VLAN trunk passes expected VLANs
Firewall containers are running
DNS resolves lab records
DHCP leases are issued
NTP responds
Syslog receives messages
Prometheus targets are up
Grafana dashboards show data
```

Keep this checklist small and repeatable. It is much easier to debug a router when each layer can be verified separately.

### Result

The result is a compact ARM64 lab router that runs VLAN routing, firewall services, DNS, DHCP, logging, and monitoring in containers.

This setup is useful for testing Cobanero, experimenting with routing policy, building dashboards, and validating network designs without publishing private infrastructure details.
