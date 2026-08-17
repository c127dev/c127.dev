+++
# SPDX-License-Identifier: CC-BY-4.0
# Copyright (C) 2026 Johan Alvarado
title = "About me"
template = "prose.html"
+++

I do embedded Linux and networking engineering across the full stack - from
the circuit to the kernel. That means schematic-level analysis, microsoldering
and component-level rework, firmware, kernel drivers, and board integration in
OpenWrt. Most engineers work at one of those layers. I work across all of
them, which matters when a bug refuses to stay on one side of the
hardware/software boundary.

## Upstream Linux kernel work

- [**net: stmmac: dwmac-motorcomm** - fix eFUSE MAC address read
  failure](https://lore.kernel.org/netdev/fc5992a4-9532-49c3-8ec1-c2f8c5b84ca1@smtp-relay.sendinblue.com/)
  - on the YT6801 the eFUSE controller needs a settling window after reset;
  without it the read returns zeros and the driver falls back to a random MAC.
  Found by comparing against a custom U-Boot port where the same read
  succeeded because the driver came up later in boot. Fixes a user-reported
  regression on TUXEDO hardware. Merged.
- [**net: dsa: realtek: rtl8365mb** - SGMII/HSGMII support for the
  RTL8367S](https://lore.kernel.org/netdev/20260711-rtl8367s-sgmii-v6-0-88f7944ddca7@c127.dev/)
  - boards wiring the switch to the CPU over the SerDes had no working CPU
  port. The register sequence was recovered from the vendor GPL drop and
  cross-checked against live hardware by chainloading a custom chained U-Boot ahead of
  the stock firmware and logging the real SerDes accesses.
  Merged.
- [**net: stmmac** - raise the TX completion interrupt at the end of an xmit
  burst](https://lore.kernel.org/netdev/20260731194522.55069-1-contact@c127.dev/)
  - TX skbs are only freed on completion, and completion was gated on 25
  frames or a 5 ms timer. Paced flows never queue 25 frames, so every burst
  waited out the timer: BBR over a 23 ms path was pinned at 5.24 Mbit/s where
  CUBIC reached 207. Setting the interrupt bit on the last descriptor of each
  burst takes it to 447 Mbit/s with interrupt load unchanged. A 2016 report of
  the same starvation was closed asking for a real fix; this is it. In review.

## Other work

- [**Armbian**](https://github.com/armbian/build/pull/8348) - board support
  for the Orange Pi 5 Pro, and a
  [follow-up rework](https://github.com/armbian/build/pull/9600) extending it.
- [**games-on-whales/inputtino**](https://github.com/games-on-whales/inputtino/pull/47)
  - fixed multi-touch slot allocation in the evdev backend. Contacts released
  out of order collided on the same MT slot, making fingers teleport between
  positions over Sunshine/Moonlight touch passthrough. Now allocates the
  lowest free slot with monotonic tracking IDs.
- **OpenWrt** - board support for a Mercusys MR80X v2.20 router. Still in process to publish the testing image.

## Current focus

Networking: MACs, PHYs, Ethernet switches - the data path between the silicon
and the Linux network stack, with most of my recent kernel work in and around
stmmac. I got here through electronics and circuit design, and that hardware
background is what lets me debug the problems that cross the boundary: a
driver that misbehaves because of a strapping pin, a link that flaps because
of a clocking issue the datasheet buries in a footnote, an interrupt that
never fires because the errata says it won't.

I work upstream because that's where the code outlives the project. A driver
merged into mainline keeps running on devices for decades, maintained by the
community, long after any single vendor has moved on.

