#!/usr/bin/env bash
# SuperOnline alternatif 5 — turkey_dnsredir_alternative5_superonline.cmd'in karşılığı
#   goodbyedpi.exe -9 --dns-addr 77.88.8.8 --dns-port 1253 \
#                  --dnsv6-addr 2a02:6b8::feed:0ff --dnsv6-port 1253
GBD_ARGS="-9 --dns-addr 77.88.8.8 --dns-port 1253 --dnsv6-addr 2a02:6b8::feed:0ff --dnsv6-port 1253"
UP_ARGS="--dns4 --dns4-addr 77.88.8.8 --dns4-port 1253 --dns6 --dns6-addr 2a02:6b8::feed:0ff --dns6-port 1253 --quic"
. "$(dirname -- "$(readlink -f -- "$0")")/_common.sh"
