#!/usr/bin/env bash
# SuperOnline alternatif 2 — turkey_dnsredir_alternative2_superonline.cmd'in karşılığı
#   goodbyedpi.exe -5
# shellcheck disable=SC2034  # _common.sh tarafından okunuyor
GBD_ARGS="-5"
# shellcheck disable=SC2034
UP_ARGS=""
# shellcheck source=_common.sh
. "$(dirname -- "$(readlink -f -- "$0")")/_common.sh"
