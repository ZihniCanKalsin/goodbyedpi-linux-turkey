# goodbyedpi-0.1-linux-turkey

[![build](https://img.shields.io/github/actions/workflow/status/OWNER/goodbyedpi-0.1-linux-turkey/build.yml?branch=main)](./.github/workflows/build.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue)](./LICENSE)
[![version](https://img.shields.io/badge/version-0.1.0-informational)](./CHANGELOG.md)

A from-scratch Linux reimplementation of
[GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) — the Windows DPI
(Deep Packet Inspection) circumvention tool — targeting the feature surface
of the Turkey-ISP fork. Uses **NFQUEUE + raw sockets** on Linux in place of
the Windows **WinDivert** kernel driver, with matching command-line
semantics for the `-5` / `-9` presets, TTL tricks, and transparent DNS
redirection.

It is not a line-for-line port. It is a clean-room reimplementation that
targets the exact command-line surface used by the Turkey fork's `.cmd`
launchers, so existing users can move 1:1 from Windows to Linux without
changing their mental model.

---

## Table of contents

- [Why this exists](#why-this-exists)
- [Features](#features)
- [Quickstart](#quickstart)
- [Install](#install)
- [Usage — variant table](#usage--variant-table)
- [Running persistently](#running-persistently)
- [How it works](#how-it-works)
- [Flag reference](#flag-reference)
- [Troubleshooting](#troubleshooting)
- [Limitations and differences from upstream](#limitations-and-differences-from-upstream)
- [Development](#development)
- [Contributing](#contributing)
- [License and credits](#license-and-credits)
- [Legal](#legal)

---

## Why this exists

The upstream GoodbyeDPI and its Turkey fork are Windows-only — they rely on
the WinDivert kernel driver and target the Windows network stack. For users
on Linux (desktop, WSL hosts, home-router VMs, travel laptops) there has
been no equivalent tool that mirrors the Turkey fork's ready-made variant
presets. `goodbyedpi-0.1-linux-turkey` fills that gap: same argv, same
behavior, same variant names — packaged for 1:1 migration from the
Windows Turkey fork.

## Features

- **NFQUEUE-based packet interception.** Kernel hands matching packets to
  userspace; the daemon inspects, rewrites, or replaces them.
- **TLS ClientHello splitting** at a configurable byte offset, optionally in
  reverse order (second fragment sent before the first).
- **HTTP request splitting** at a configurable byte offset for outbound
  TCP/80 traffic.
- **Fake decoy packet injection** with deliberately wrong TCP sequence
  and/or wrong TCP checksum, at a low TTL / hop limit so the decoy dies
  in-path before reaching the real server.
- **Transparent DNS redirect** over IPv4 and IPv6 — outbound UDP/53 queries
  are NAT-rewritten to a custom resolver (e.g. Yandex DNSCrypt on port
  1253); reply-path rewrites are reversed via a short-lived per-query
  hashmap so the client stack sees a normal reply.
- **QUIC / UDP-443 blocking** under `-q` and `-9`, forcing browsers to fall
  back to TCP where fragmentation tricks work.
- **Seven launcher scripts** in 1:1 correspondence with the Turkey fork's
  `.cmd` files — migration from Windows is picking the matching `.sh`.
- **Fails open on crash.** iptables rules are installed with
  `--queue-bypass`; if the daemon dies the kernel just forwards traffic
  normally (DPI bypass turns off, but the internet still works).
- **No systemd dependency.** Distro-agnostic `setsid` + PID-file background
  model. Autostart is left to the user's preferred init.

## Quickstart

On a Debian / Ubuntu host, as an admin:

```sh
git clone https://github.com/OWNER/goodbyedpi-0.1-linux-turkey.git
cd goodbyedpi-0.1-linux-turkey
sudo scripts/deps-install.sh         # installs libnetfilter-queue-dev, libmnl-dev, iptables
make
sudo scripts/turkey_dnsredir.sh      # primary variant — Ctrl-C to stop
```

That's it. On Ctrl-C the iptables rules are removed and your networking
returns to default.

## Install

### Dependencies

**Build-time:** `libnetfilter_queue` headers, `libmnl` headers, a C
compiler, `make`, `pkg-config`.

**Run-time:** `iptables` (and `ip6tables` if you want IPv6), kernel module
`nfnetlink_queue` (present in any mainline kernel; the helper `modprobe`s
it on startup), and **root** (or `CAP_NET_ADMIN` + `CAP_NET_RAW`).

The `scripts/deps-install.sh` helper auto-detects the local package manager
(`apt-get`, `dnf`, `yum`, `pacman`, `zypper`, `apk`) and installs the right
packages. If your distro isn't on that list, install the equivalents of:

| Package (Debian/Ubuntu) | Equivalent on other distros                          |
|---|---|
| `libnetfilter-queue-dev` | `libnetfilter_queue-devel` (Fedora/RHEL/SUSE), `libnetfilter_queue` + `-dev` (Arch/Alpine) |
| `libmnl-dev`             | `libmnl-devel` (Fedora/RHEL/SUSE), `libmnl`          |
| `gcc`, `make`, `pkg-config`, `iptables` | same name everywhere |

### Build

```sh
make                # produces ./goodbyedpi-linux (~35 KB)
make clean          # wipe build artifacts
```

## Usage — variant table

Each script installs exactly the iptables rules its variant needs, runs
the daemon in the foreground, and tears the rules down on Ctrl-C / exit.

| Windows `.cmd` (Turkey fork) | Linux equivalent here | What it does |
|---|---|---|
| `turkey_dnsredir.cmd` | `sudo scripts/turkey_dnsredir.sh` | Primary variant. `-5` + TTL 5 + DNS redirect to Yandex (1253) for IPv4 and IPv6. |
| `turkey_dnsredir_alternative_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt1.sh` | `--set-ttl 3` only. You configure DNS manually. |
| `turkey_dnsredir_alternative2_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt2.sh` | `-5` only. You configure DNS manually. |
| `turkey_dnsredir_alternative3_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt3.sh` | `--set-ttl 3` + Yandex DNS redirect (v4 + v6). |
| `turkey_dnsredir_alternative4_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt4.sh` | `-5` + Yandex DNS redirect (v4 + v6). |
| `turkey_dnsredir_alternative5_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt5.sh` | `-9` + Yandex DNS redirect (v4 + v6). |
| `turkey_dnsredir_alternative6_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt6.sh` | `-9` only. You configure DNS manually. |

Variants whose name doesn't include "DNS redirect" do **not** rewrite
UDP/53 — you must set your system resolver yourself (Yandex `77.88.8.8` or
Cloudflare `1.1.1.1` are the usual choices), same caveat as the Windows
README.

To use a custom DNS server instead of Yandex, edit the top of the variant
script or run the daemon directly:

```sh
sudo scripts/iptables-up.sh --dns4 --dns4-addr 1.1.1.1 --dns4-port 53 &&
sudo ./goodbyedpi-linux -5 --dns-addr 1.1.1.1 --dns-port 53
```

## Running persistently

There is no systemd unit on purpose — the project stays distro-agnostic.
Two helpers manage a long-running background daemon:

```sh
sudo scripts/goodbyedpi-linux-install.sh turkey_dnsredir   # or any variant name
sudo scripts/goodbyedpi-linux-uninstall.sh
```

The installer:

- backgrounds the chosen variant with `setsid`,
- writes the PID to `/var/run/goodbyedpi-linux.pid`,
- appends logs to `/var/log/goodbyedpi-linux.log`.

The daemon **survives** logout but does **not auto-start** at boot. To
autostart, wire it into your distro's native mechanism — common options:

```sh
# /etc/rc.local (classic sysvinit / rc.local-enabled systems)
/path/to/goodbyedpi-0.1-linux-turkey/scripts/goodbyedpi-linux-install.sh turkey_dnsredir

# crontab (any distro that ships cron)
@reboot root /path/to/goodbyedpi-0.1-linux-turkey/scripts/goodbyedpi-linux-install.sh turkey_dnsredir

# or write your own systemd unit if you prefer
```

## How it works

```
                   ┌──────────────────────────────────────────┐
   outbound pkts   │  iptables OUTPUT / INPUT                 │
  ─────────────▶  │  -m multiport --dports 80,443 -j NFQUEUE │
                   │  -p udp --dport 53      -j NFQUEUE       │
                   │  -p udp --dport 443     -j NFQUEUE  (-q) │
                   └───────────────┬──────────────────────────┘
                                   │ libnetfilter_queue
                                   ▼
                   ┌──────────────────────────────────────────┐
                   │  goodbyedpi-linux                        │
                   │  ┌────────────────────────────────────┐  │
                   │  │ dispatcher (nfq_loop.c)            │  │
                   │  └───┬──────────┬─────────┬───────────┘  │
                   │      │          │         │              │
                   │      ▼          ▼         ▼              │
                   │  tcp_mangle  dns_redir   QUIC drop       │
                   │  (ClientHello  (UDP 53    (UDP 443       │
                   │   + HTTP split, DNAT +    NF_DROP)       │
                   │   fake decoys,  reverse                  │
                   │   reverse frag) rewrite)                 │
                   └──────────────────────────────────────────┘
                                   │ raw socket (IP_HDRINCL)
                                   ▼
                    crafted fragments / decoys back to the wire
```

### Per-packet verdicts

| Direction | Protocol / port | Condition                               | Action |
|---|---|---|---|
| Outbound  | TCP dport 443   | First data segment is a TLS ClientHello (`0x16 0x03 … 0x01`) | `NF_DROP` original, raw-inject decoy (optional) + two fragments of the original payload, optionally in reverse order. |
| Outbound  | TCP dport 80    | First data segment is an HTTP verb (`GET `, `POST `, `HEAD `, …) | same as above. |
| Outbound  | UDP dport 53    | `--dns-addr` / `--dnsv6-addr` set | Rewrite dst IP+port to the configured resolver, recompute IP/UDP checksums, record `(src, txid)` for reverse rewrite, `NF_ACCEPT`. |
| Inbound   | UDP from configured DNS server | `--dns-addr` / `--dnsv6-addr` set | Rewrite src IP+port back to the original destination the client queried, recompute checksums, `NF_ACCEPT`. |
| Outbound  | UDP dport 443   | `-q` / `-9` active                      | `NF_DROP` (forces TCP fallback). |
| Anything else in-queue | — | —                                | `NF_ACCEPT` untouched. |

### Why `NF_DROP` + raw-socket re-injection

`NFQUEUE` lets us modify a packet in-place and re-verdict it, but that
can't produce *multiple* packets from one input. Fragmented ClientHello
splitting inherently emits ≥ 2 packets, so the original is dropped and
the replacements go out via an `AF_INET`/`AF_INET6 SOCK_RAW` socket with
`IP_HDRINCL`, preserving source IP/port/seq and letting us freely control
TTL and checksums.

## Flag reference

| Flag                      | Effect                                                              |
|---|---|
| `-5`                      | `-f 2 -e 2 --auto-ttl --reverse-frag --max-payload`                 |
| `-9`                      | `-5` + `--wrong-seq --wrong-chksum -q`                              |
| `-f N`                    | HTTP request split offset (bytes; Turkey fork uses 2)               |
| `-e N`                    | TLS ClientHello split offset (bytes; Turkey fork uses 2)            |
| `--auto-ttl`              | Enable low TTL heuristic for decoy packets                          |
| `--reverse-frag`          | Send the second fragment before the first                           |
| `--wrong-seq`             | Inject decoy with bogus TCP sequence number                         |
| `--wrong-chksum`          | Inject decoy with deliberately invalid TCP checksum                 |
| `--max-payload`           | Accepted for compatibility; no-op (NFQUEUE path already gates work) |
| `--set-ttl N`             | TTL / hop limit applied to decoy packets (1–255)                    |
| `-q`                      | Drop QUIC / UDP-443 (forces browsers to TCP)                        |
| `--dns-addr IP`           | Target IP for UDP/53 rewrite                                        |
| `--dns-port N`            | Target port for UDP/53 rewrite (default 53)                         |
| `--dnsv6-addr IP6`        | Target address for IPv6 UDP/53 rewrite                              |
| `--dnsv6-port N`          | Target port for IPv6 UDP/53 rewrite (default 53)                    |
| `--queue-num N`           | NFQUEUE number (default 200)                                        |
| `-v`                      | Verbose debug logging                                               |
| `-h`                      | Help                                                                |

## Troubleshooting

- **`iptables: No chain/target/match by that name`** — kernel is missing
  `xt_NFQUEUE`. Run `sudo modprobe xt_NFQUEUE nfnetlink_queue`, or build /
  install a kernel that includes them (every mainline distro kernel does
  by default).
- **`firewalld` / `ufw` wipes my rules** — those daemons manage iptables
  exclusively. Either register the NFQUEUE rules through their own
  interfaces, or stop that firewall service while using goodbyedpi-linux.
- **Nothing changes on the wire** — verify the rules are installed
  (`sudo iptables -S OUTPUT | grep NFQUEUE`) and the daemon is running
  (`ps -ef | grep goodbyedpi-linux`, or tail
  `/var/log/goodbyedpi-linux.log` in persistent mode).
- **IPv6 DNS redirect never fires** — many systems issue DNS only over
  IPv4. Test with `dig -6 @<your-local-resolver> example.com` or force
  IPv6 at your stub resolver.
- **`socket(SOCK_RAW, IPPROTO_RAW): Operation not permitted`** — the
  daemon was started without `CAP_NET_RAW`. Run with `sudo`, or give the
  binary the capabilities once with
  `sudo setcap cap_net_admin,cap_net_raw=ep goodbyedpi-linux`.
- **Two instances on the same queue #** — only one NFQUEUE reader can bind
  each queue number. Override with `QUEUE_NUM=201 scripts/turkey_dnsredir.sh`.
- **WSL2** — note that iptables applied inside WSL only affects WSL's
  network namespace, not the Windows host. DPI bypass for Windows apps
  still needs `goodbyedpi.exe`. For a real Linux deployment, use native
  Linux (desktop, VM, or router).

## Limitations and differences from upstream

- **`--auto-ttl` is a simplification.** Upstream actively probes to measure
  the distance to the DPI middlebox. This port uses `--set-ttl` if given,
  otherwise defaults the decoy hop limit to 4. If your middlebox is
  unusually far, pass `--set-ttl N` explicitly.
- **`--max-payload` is accepted but has no effect.** The NFQUEUE path
  already only acts on packets carrying a TLS ClientHello or an HTTP
  verb, so there's nothing for it to skip.
- **Turkey fork feature subset only.** Upstream has dozens of extra flags
  (`-1`/`-2`/`-3`/`-4`, `-a`, `-r`, `-s`, `-m`, blacklist file support,
  fake-gen modes, hop-limit probing, …) that are not reimplemented.
  Those are out of scope for this project; open an issue if you need one
  of them.
- **No WinDivert-style single-binary bundle.** Linux needs iptables wired
  up out-of-band. The variant scripts do this for you; if you call the
  binary directly, run `scripts/iptables-up.sh` first and
  `scripts/iptables-down.sh` when done.
- **Fails open, not closed.** If the daemon dies with iptables rules still
  installed, the `--queue-bypass` flag makes the kernel forward traffic
  normally (DPI bypass just turns off). This matches the Windows behavior
  of closing the `.cmd` window: you lose the workaround, not your
  connection.

## Development

Source layout:

```
goodbyedpi-0.1-linux-turkey/
├── Makefile                    # cc + pkg-config libnetfilter_queue libmnl
├── LICENSE                     # Apache-2.0
├── NOTICE                      # attribution to upstream GoodbyeDPI
├── README.md                   # this file
├── CHANGELOG.md
├── .gitignore
├── .github/workflows/build.yml # CI: build + CLI smoke test + shellcheck
├── src/
│   ├── main.c                  # arg parse, preset expansion, signal handling
│   ├── nfq_loop.c/.h           # NFQUEUE consumer + dispatcher
│   ├── tcp_mangle.c/.h         # ClientHello / HTTP detection + 2-byte split
│   ├── raw_inject.c/.h         # AF_INET{,6} SOCK_RAW with IP_HDRINCL
│   ├── dns_redir.c/.h          # DNS rewrite + response un-rewrite hashmap
│   ├── checksum.c/.h           # IPv4 / IPv6 / TCP / UDP checksums
│   └── util.c/.h               # global config + logging macros
└── scripts/
    ├── deps-install.sh
    ├── iptables-up.sh / iptables-down.sh
    ├── goodbyedpi-linux-install.sh / -uninstall.sh
    ├── _common.sh              # shared boilerplate for variant scripts
    └── turkey_dnsredir{,_alt1..6}.sh
```

To hack on it, `make` and run the daemon with `-v` for extra log lines.
A small local reproducer is the pair of commands in `.github/workflows/build.yml`
under `Smoke-test CLI parse path`. For on-the-wire inspection:

```sh
sudo tcpdump -i any -n 'tcp port 443 or tcp port 80 or udp port 53'
```

## Contributing

Issues and pull requests welcome. Before opening a large PR, please open an
issue first to discuss scope — the project intentionally stays narrow
(the Turkey fork flag surface), and features from the broader upstream
GoodbyeDPI may be out of scope on purpose.

A few guidelines:

- Keep the code pure C11, no external dependencies beyond
  `libnetfilter_queue` and `libmnl`.
- Match the existing style (4-space indent, `snake_case`, `static` where
  possible, header guards `GBD_*_H`).
- Shell scripts should pass `shellcheck` cleanly (CI enforces this).
- Don't introduce a systemd dependency; the project is deliberately
  distro-agnostic.

## License and credits

Licensed under **Apache-2.0** — see [`LICENSE`](./LICENSE) and
[`NOTICE`](./NOTICE).

This is an independent reimplementation, but credit for the technique and
the command-line design goes to:

- **[GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI)** (ValdikSS) —
  upstream Windows project, Apache-2.0.
- **GoodbyeDPI Turkey fork** — whose `.cmd` variant set defines the
  flag combinations this project targets.

Linux kernel subsystems used: `nfnetlink_queue` / `xt_NFQUEUE`, raw
sockets. Library: `libnetfilter_queue` (GPL-2.0) and `libmnl` (LGPL-2.1)
— this project links against them at the library boundary; see each
library's license for the terms that apply to redistribution.

## Legal

This tool changes the way your packets hit the wire. That may interact
with laws, ISP terms of service, or workplace network policy in your
jurisdiction. You are solely responsible for how and where you run it.
Use only on networks you own or are authorized to operate on. The authors
accept no liability for misuse. For educational and research purposes.
