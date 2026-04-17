#!/usr/bin/env bash
# SuperOnline alternative 1 — mirrors turkey_dnsredir_alternative_superonline.cmd
#   goodbyedpi.exe --set-ttl 3
# User must set system DNS manually (Yandex or Cloudflare) per the README.
GBD_ARGS="--set-ttl 3"
UP_ARGS=""
. "$(dirname -- "$(readlink -f -- "$0")")/_common.sh"
