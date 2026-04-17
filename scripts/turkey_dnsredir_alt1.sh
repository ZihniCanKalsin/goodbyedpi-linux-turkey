#!/usr/bin/env bash
# SuperOnline alternatif 1 — turkey_dnsredir_alternative_superonline.cmd'in karşılığı
#   goodbyedpi.exe --set-ttl 3
# Kullanıcı sistem DNS'ini README'deki gibi manuel ayarlamalıdır (Yandex ya da Cloudflare).
GBD_ARGS="--set-ttl 3"
UP_ARGS=""
. "$(dirname -- "$(readlink -f -- "$0")")/_common.sh"
