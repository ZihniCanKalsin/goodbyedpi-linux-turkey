#!/usr/bin/env bash
# SuperOnline alternatif 1 — turkey_dnsredir_alternative_superonline.cmd'in karşılığı
#   goodbyedpi.exe --set-ttl 3
# Kullanıcı sistem DNS'ini README'deki gibi manuel ayarlamalıdır (Yandex ya da Cloudflare).
# shellcheck disable=SC2034  # _common.sh tarafından okunuyor
GBD_ARGS="--set-ttl 3"
# shellcheck disable=SC2034
UP_ARGS=""
# shellcheck source=_common.sh
. "$(dirname -- "$(readlink -f -- "$0")")/_common.sh"
