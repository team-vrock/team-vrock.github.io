---
layout: post
title: "Tuning a Windows 11 KVM Guest, Part 1: Performance Baseline and Modular QEMU"
date: 2026-03-29 10:00:00 +0000
categories: post
tags: [kvm, libvirt, windows, opensuse, virtualization, qemu, audio]
author: Tobias Geiser
image: "/assets/posts/2026-03-29/kvm-win.png"
header: "/assets/posts/2026-03-29/kvm-win-header.png"
excerpt_separator: <!--more-->
---

My Windows 11 VM felt sluggish everywhere — window dragging, app launches, even cursor movement. Instead of randomly flipping settings, I audited the libvirt XML first. The config was better than I expected, and the real problems were elsewhere: a btrfs-backed qcow2 with no tuning, and two failures that only make sense if you know that openSUSE ships QEMU as a pile of small modules.
<!--more-->

**TL;DR:** Audit with `virsh dumpxml` before tuning. The wins were storage (`NOCOW`/raw, `cache=none`, `io=native`), CPU pinning, and guest-side drivers — not the CPU model, which was already `host-passthrough`. Along the way, USB passthrough broke because the `usb-host` QEMU module was not installed, and `virtio-vga-gl` failed because the display backend had no OpenGL. Both are openSUSE packaging details worth knowing.

This is Part 1 of a two-part series. [Part 2]({% post_url 2026-05-03-tuning-a-windows-11-kvm-guest-for-pro-audio-part-2 %}) covers pinning for audio work, USB controller passthrough, and xfreerdp tuning.

## Overview

This post is a performance audit and repair walkthrough for a Windows 11 guest under KVM/libvirt on openSUSE Tumbleweed. It is for you if:

- You run Windows VMs with libvirt and they feel slower than they should.
- You want a systematic audit order instead of folklore.
- You hit weird QEMU device errors on a distribution that modularizes QEMU.

The guest started life with 12 vCPUs, 16 GB RAM, and a qcow2 image on btrfs.

## Prerequisites

- A Linux host with libvirt/QEMU (`virsh` working) and a Windows 11 guest.
- The `virtio-win` driver ISO for guest-side driver updates.
- Root or sufficient permissions to edit domain XML and inspect storage.
- Willingness to shut the VM down for the XML changes (live tuning covers only part of this).

## Walkthrough

### Audit the current configuration

Read what the hypervisor actually runs, not what you think it runs:

```bash
virsh -c qemu:///system dumpxml <vm-name>
virsh -c qemu:///system domblklist <vm-name> --details
virsh -c qemu:///system vcpupin <vm-name>
lscpu
```

My audit scorecard:

| Item | State | Verdict |
|---|---|---|
| CPU model | `host-passthrough` | good, keep |
| Hyper-V enlightenments (`hv_*`) | enabled | good, keep |
| Disk | virtio (`vda`) | good, keep |
| NIC | virtio | good, keep |
| vCPU pinning | none | fix |
| Disk backing | qcow2 on btrfs, no NOCOW | fix |
| Disk cache/io tuning | defaults | fix |
| Ballooning | enabled | disable for fixed-size guests |
| Install ISOs | still attached | remove |
| Display | SPICE + virtio video, no GL | keep for console, RDP for daily use |

**Pro tip:** `host-passthrough` plus Hyper-V enlightenments is the part everyone recommends, and it was already fine. The measurable wins were in storage and scheduling — the boring places.

### Fix the storage path

The guest disk was a qcow2 file on btrfs. Two problems stack here: qcow2 metadata overhead, and btrfs copy-on-write on a file that is rewritten constantly. Options, best first:

1. Raw image on ext4/xfs.
2. Keep btrfs but set the NOCOW attribute on the image file (`chattr +C`) before heavy use.
3. At minimum, preallocate.

In the domain XML, tune the disk itself:

```xml
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' cache='none' io='native'/>
  <source file='/var/lib/libvirt/images/<vm-name>.qcow2'/>
  <target dev='vda' bus='virtio'/>
</disk>
```

`cache='none'` skips the host page cache double-buffering; `io='native'` uses Linux AIO. Add an iothread if you run several disks, and silence ballooning for a fixed-size guest:

```xml
<memballoon model='none'/>
```

Also detach leftover install ISOs — a Windows install ISO and a `virtio-win` ISO sitting on the virtual SATA bus are just dead weight after setup.

### Plan CPU pinning

With no pinning, vCPUs migrate across all host cores, and the emulator threads fight with everything else. The fix is a `<cputune>` block mapping each vCPU to a fixed host CPU and giving the emulator its own cores. I did this in Part 2 together with the audio work — the XML looks like:

```xml
<cputune>
  <vcpupin vcpu='0' cpuset='2'/>
  <vcpupin vcpu='1' cpuset='3'/>
  <emulatorpin cpuset='0-1'/>
</cputune>
```

Leave core 0–1 (and whatever your host needs) for the emulator and the host; pin vCPUs to the rest.

### Tune the guest side

On the Windows side:

- Install or update the `virtio-win` drivers — especially display and network.
- Set the High Performance power plan.
- Consider disabling VBS/Memory Integrity if you do not need them; they tax a virtualized CPU.
- Use RDP for daily interaction; keep the SPICE/virtio console for emergency access only.

### Pick the right RDP client

This host has both `xfreerdp` and `wlfreerdp`. The Wayland client (`wlfreerdp`) is deprecated and crashed with a client-side assert right after connecting:

```text
freerdp_client_warn_deprecated: wlfreerdp client has been deprecated
```

The Kerberos warnings in the log were noise — authentication had already succeeded when it died. Use `xfreerdp`:

```bash
xfreerdp /v:<vm-ip> /u:.\ <vm-user> /cert:ignore /dynamic-resolution +clipboard /network:lan
```

## Troubleshooting

### 'usb-host' is not a valid device model name

After adding the USB audio interface as a passthrough device in virt-manager, the VM refused to start:

```text
qemu-system-x86_64: -device {"driver":"usb-host",...}:
'usb-host' is not a valid device model name
```

The XML was fine — `<hostdev type='usb'>` with the device's vendor/product IDs. The problem is that openSUSE splits QEMU into many small packages, and the module providing `usb-host` was simply not installed. Verify what your QEMU actually knows:

```bash
qemu-system-x86_64 -device help | grep usb-host
```

Empty output means the module is missing. Check the installed pieces:

```bash
rpm -qa 'qemu*'
```

On my host I had `qemu-hw-usb-redirect` but not the package providing `usb-host`. Install the missing module package, restart libvirt, and verify again with `-device help`.

**Gotcha:** to boot immediately while debugging, remove the USB host device from the domain and start the VM; re-add it once the module is present.

### OpenGL display backend not available

Trying to speed up the console, I switched the video model to the 3D variant (`virtio-vga-gl`). The VM failed to start:

```text
-device {"driver":"virtio-vga-gl",...}: The display backend does not have
OpenGL support enabled
```

The GL variant needs a display backend with OpenGL (SPICE with `gl` enabled or egl-headless). The plain fix: use `virtio-vga` without GL:

```xml
<video>
  <model type='virtio-vga' heads='1' primary='yes'/>
</video>
```

Since daily use runs over RDP anyway, a fast SPICE console is a nice-to-have, not a requirement.

## Summary

- Audit with `dumpxml` before changing anything; `host-passthrough` + Hyper-V flags were already correct.
- Storage wins: NOCOW or raw, `cache=none`, `io=native`, drop ballooning and stale ISOs.
- Pin vCPUs and emulator threads; leave cores for the host.
- On openSUSE, "device model not found" usually means a missing `qemu-hw-*` module package.
- Prefer `virtio-vga` over `virtio-vga-gl` unless your display backend supports OpenGL; prefer RDP over the console for daily use.

## References

- [Part 2: Pro Audio Over RDP]({% post_url 2026-05-03-tuning-a-windows-11-kvm-guest-for-pro-audio-part-2 %})
- [libvirt: CPU tuning](https://libvirt.org/formatdomain.html#cpu-tuning)
- [virtio-win drivers](https://github.com/virtio-win/virtio-win-pkg-scripts)
