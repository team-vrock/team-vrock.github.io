---
layout: post
title: "Tuning a Windows 11 KVM Guest for Pro Audio, Part 2: Pinning, Passthrough, and RDP"
date: 2026-05-03 10:00:00 +0000
categories: post
tags: [kvm, libvirt, windows, opensuse, virtualization, qemu, audio]
author: Tobias Geiser
image: "/assets/posts/2026-05-03/kvm-rdp-proaudio.png"
header: "/assets/posts/2026-05-03/kvm-proaudio-header.png"
excerpt_separator: <!--more-->
---

In [Part 1]({% post_url 2026-03-29-tuning-a-windows-11-kvm-guest-part-1 %}) I tuned the boring parts of a Windows 11 VM: storage, drivers, CPU model. This part has a stricter goal: a USB audio interface living inside the VM, controlled over RDP, without crackling. That means CPU pinning, whole-controller PCI passthrough, removing every piece of emulated audio, and finding the one xfreerdp flag that decides where sound actually plays.
<!--more-->

**TL;DR:** Pass through the whole USB controller instead of individual devices, pin vCPUs to dedicated cores, delete the emulated sound card and SPICE USB redirection, and use `/audio-mode:1` so Windows plays audio through the passed-through interface instead of the RDP audio channel. The final baseline is listed at the end.

This is Part 2 of a two-part series.

## Overview

The workload: music production inside the guest — a DAW talking to an external USB audio interface — while I sit on the Linux host and connect with `xfreerdp`. Any scheduling jitter or audio redirection through RDP shows up as crackling, so the bar is higher than "the VM is responsive".

The host for this round: an Intel Core Ultra 9 285K with 24 physical cores and no SMT, single NUMA node. That is a good base for deterministic pinning — no sibling threads to share, no cross-node accidents.

## Architecture

Three decisions shape everything else:

1. **The audio interface is attached to a dedicated USB controller** (an ASMedia ASM2142/ASM3142 PCIe card), and that *whole controller* is passed through to the VM by PCI address. Per-device `usb-host` passthrough works, but a dedicated controller avoids reconnect races and hotplug surprises.
2. **RDP carries video and input only.** Audio stays local to the VM: it plays out of the passed-through interface, not through the RDP audio channel.
3. **The host stays the display machine.** SPICE remains as an emergency console; nothing audio-critical depends on it.

![Pro audio KVM virtualization architecture: Linux host kernel isolation, dedicated CPU pinning, VFIO USB controller passthrough, Windows guest DAW, and low-latency RDP display.](/assets/posts/2026-05-03/kvm-audio-architecture.png){: style="max-width: 100%; min-width: 100%; height: auto"}

## Prerequisites

- A host CPU you can dedicate cores to (I kept cores 0–1 for the host/emulator).
- An IOMMU group containing your USB controller (or a device you can pass through).
- The guest booted with `host-passthrough` and virtio disk/net (see Part 1).
- `xfreerdp` on the host (not the deprecated `wlfreerdp`).

## Walkthrough

### Confirm the passthrough candidate

Check the controller's PCI address and its IOMMU group:

```bash
lspci -nnk | grep -i usb
for d in /sys/kernel/iommu_groups/*/devices/*; do
  echo "${d}" | grep -q '<pci-address>' && dirname "$(dirname "$d")"
done
```

Everything in the same IOMMU group gets passed through together — make sure nothing you need on the host shares the group.

### Pin vCPUs and emulator threads

With 6 vCPUs for the guest and 24 cores on the host:

```xml
<cputune>
  <vcpupin vcpu='0' cpuset='2'/>
  <vcpupin vcpu='1' cpuset='3'/>
  <vcpupin vcpu='2' cpuset='4'/>
  <vcpupin vcpu='3' cpuset='5'/>
  <vcpupin vcpu='4' cpuset='6'/>
  <vcpupin vcpu='5' cpuset='7'/>
  <emulatorpin cpuset='0-1'/>
</cputune>
```

vCPUs get cores 2–7; the emulator threads (timers, IO, anything QEMU does that is not a vCPU) are confined to cores 0–1 so they cannot steal time from the audio path. Verify after boot:

```bash
virsh -c qemu:///system vcpupin <vm-name>
```

### Remove emulated audio and SPICE redirection

The guest XML had an emulated ICH9 sound card and SPICE USB redirection devices. Both are useless with a passed-through interface and only add latency paths, so they went away:

- Delete the `<sound model='ich9'>` device.
- Delete the `<redirdev bus='usb' type='spicevmc'>` entries.
- Keep the `<hostdev>` for the USB controller.

Also keep the disk and network tuning from Part 1 — raw/NOCOW backing with `cache='none' io='native'`, and a virtio NIC with vhost and multiple queues:

```xml
<interface type='network'>
  ...
  <driver name='vhost' queues='6'/>
</interface>
```

### Verify the interface inside Windows

After starting the VM, the audio interface should show up as a normal Windows device. In my case the DAW and the Windows sound settings both saw the interface inputs and outputs correctly, which is the point of the whole exercise: audio never touches the RDP session.

### Tune the guest for audio

Inside Windows:

- High Performance power plan.
- Disable USB selective suspend (it can starve a USB audio interface).
- Add Defender exclusions for your DAW's folders and processes. On my guest, `MsMpEng.exe` (Defender) was the top CPU consumer and caused usage spikes; exclusions for the DAW's program-data and project folders dropped CPU samples from spiking to a steady 30–55%.
- Disable Windows Search indexing for the same reason.

**Pro tip:** check the guest's CPU queue length before adding more vCPUs. Mine was 0 after tuning — the spikes were Defender, not core starvation.

### Configure xfreerdp for audio

The flag that decides where sound plays is `/audio-mode`:

```text
/audio-mode:0  play audio on the client (the Linux host)
/audio-mode:1  play audio on the remote machine (the VM)
/audio-mode:2  disable audio output
```

For this setup the correct value is `1`: Windows plays through the passed-through interface, and RDP does not try to stream audio to the host. My stable launcher:

```bash
xfreerdp /v:<vm-ip> /u:.\ <vm-user> /cert:ignore \
  /audio-mode:1 /dynamic-resolution +clipboard /network:lan
```

A second profile exists for video playback testing with modern codecs:

```bash
xfreerdp ... /gfx:AVC420:on,AVC444:off +video /audio-mode:1
```

### Final baseline

What ended up running stably:

- 6 pinned vCPUs (host cores 2–7), emulator on 0–1
- Raw NOCOW disk, `cache=none`, `io=native`
- VirtIO network with `vhost` and `queues=6`
- Whole USB controller passed through; audio interface verified in Windows
- High Performance plan, USB selective suspend off, Defender exclusions, Search off
- RDP with `/audio-mode:1`; video testing with AVC420

## Troubleshooting

### `/microphone:sys:none` kills FreeRDP

I tried disabling microphone redirection with `/microphone:sys:none`. FreeRDP attempted to load a microphone backend literally named "none", failed, and aborted right after graphics initialized. Drop the flag entirely instead; audio output is controlled by `/audio-mode` alone.

### Connection reaches the host but logon fails at NLA

Symptom: `ERRCONNECT_LOGON_FAILURE [0x00020014]` with Kerberos "no default realm" noise in the log. The Kerberos lines are usually harmless — FreeRDP tried Kerberos first and your host has no realm configured. Typical causes, in order:

- Username format: for a local account use `.\ <vm-user>` or `<vm-hostname>\<vm-user>`, not `./<vm-user>`.
- Force NTLM to skip the Kerberos path: `/auth-pkg-list:!kerberos`.
- If the guest has NLA disabled, try `/sec:rdp`.
- And the mundane ones: account unlocked, in Remote Desktop Users, RDP enabled.

### AVC444 glitches during UAC prompts

With `/gfx:avc444`, the session could glitch exactly when Windows switches to the UAC secure desktop. The AVC420-only video profile above avoids it. Also note: a frozen RDP screen during UAC is not necessarily a VM crash — check from the host first:

```bash
virsh -c qemu:///system domstate <vm-name>
```

### Audio crackling under load

If crackling returns after all of the above, look at the network path before blaming the VM: libvirt's default NAT plus a Wi-Fi upstream adds latency and jitter. Prefer wired Ethernet on the host, or bridge/macvtap if the guest needs predictable latency.

## Summary

- Pass through the entire USB controller, not individual audio devices.
- Pin vCPUs *and* emulator threads; verify with `vcpupin`.
- Delete emulated sound and SPICE USB redirection when a real interface is passed through.
- `/audio-mode:1` keeps audio in the VM; never use `/microphone:sys:none`.
- Fix Defender and Search before adding vCPUs — check the guest CPU queue length.

## References

- [Part 1: Performance Baseline and Modular QEMU]({% post_url 2026-03-29-tuning-a-windows-11-kvm-guest-part-1 %})
- [FreeRDP documentation](https://github.com/FreeRDP/FreeRDP)
- [libvirt: CPU tuning](https://libvirt.org/formatdomain.html#cpu-tuning)
