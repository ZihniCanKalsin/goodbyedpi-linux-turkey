#!/usr/bin/env bash
# SuperOnline alternatif 6 — turkey_dnsredir_alternative6_superonline.cmd'in karşılığı
#   goodbyedpi.exe -9
# shellcheck disable=SC2034  # _common.sh tarafından okunuyor
GBD_ARGS="-9"
# shellcheck disable=SC2034
UP_ARGS="--quic"
# shellcheck source=_common.sh
. "$(dirname -- "$(readlink -f -- "$0")")/_common.sh"
