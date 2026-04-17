# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-04-17

### Added
- First release. From-scratch C reimplementation of the
  [GoodbyeDPI Turkey fork](https://github.com/ValdikSS/GoodbyeDPI)
  feature surface on Linux, using NFQUEUE + raw sockets instead of WinDivert.
- `-5` and `-9` presets, matching the upstream flag expansions.
- Per-flag support for `-f`, `-e`, `--auto-ttl`, `--reverse-frag`,
  `--wrong-seq`, `--wrong-chksum`, `--max-payload`, `--set-ttl`, `-q`.
- Outbound TLS ClientHello and HTTP-request splitting at a configurable
  byte offset, optionally in reverse order.
- Fake-decoy TCP segment injection with wrong TCP sequence and/or wrong
  checksum, at a caller-chosen low TTL / hop limit.
- Transparent DNS redirection over IPv4 (`--dns-addr`/`--dns-port`) and
  IPv6 (`--dnsv6-addr`/`--dnsv6-port`), including reverse rewrite on the
  response path via a fixed-size per-`(src, txid)` hashmap.
- QUIC / UDP-443 blocking under `-q` and `-9`.
- Seven launcher scripts (`scripts/turkey_dnsredir*.sh`) in 1:1
  correspondence with the Windows Turkey fork's `.cmd` files.
- Distro-agnostic background install / uninstall helpers that daemonize
  via `setsid` and a PID file (no systemd dependency).
- Idempotent `scripts/iptables-up.sh` / `iptables-down.sh` to manage the
  NFQUEUE rules, with `--queue-bypass` so a crash fails open.
- `scripts/deps-install.sh` detecting `apt-get`, `dnf`, `yum`, `pacman`,
  `zypper`, and `apk`.

### Known limitations
- `--auto-ttl` is a heuristic (fixed hop limit 4 if `--set-ttl` is not
  given); upstream does active network probing to measure distance to
  the DPI middlebox.
- `--max-payload` is a no-op knob. Our NFQUEUE path already gates on
  ClientHello / HTTP-verb detection, so there is nothing to skip.
- Not yet verified end-to-end against a real Turkish ISP DPI middlebox.
  The packet-level behavior has been confirmed on a local smoke test
  (NFQ bind, preset expansion, clean rule teardown); real-world
  effectiveness still needs to be validated on-network.
