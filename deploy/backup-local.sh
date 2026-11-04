#!/usr/bin/env bash
set -Eeuo pipefail

umask 077
SNAPSHOT=/srv/canary/elixir.micutu.com/evolving_minds/data/world.snapshot
BACKUP=/srv/backups/evolving-minds
stamp="$(date -u +'%Y-%m-%dT%H%M%SZ')"
raw_tmp="${BACKUP}/.world-${stamp}.snapshot.tmp"
gz_tmp="${BACKUP}/.world-${stamp}.snapshot.gz.tmp"
final="${BACKUP}/world-${stamp}.snapshot.gz"
verify="${BACKUP}/.world-${stamp}.verify.snapshot"
cleanup() { rm -f "${raw_tmp}" "${gz_tmp}" "${verify}"; }
trap cleanup EXIT
test -s "${SNAPSHOT}"
cp --reflink=auto --preserve=mode,timestamps "${SNAPSHOT}" "${raw_tmp}"
gzip -n -9 -c "${raw_tmp}" > "${gz_tmp}"
gzip -t "${gz_tmp}"
gzip -cd "${gz_tmp}" > "${verify}"
cmp -s "${raw_tmp}" "${verify}"
mv "${gz_tmp}" "${final}"
sha256sum "${final}" > "${final}.sha256"
find "${BACKUP}" -xdev -type f \
  \( -name 'world-*.snapshot.gz' -o -name 'world-*.snapshot.gz.sha256' \) \
  -mtime +14 -delete
cleanup
trap - EXIT
printf '%s backed up Evolving Minds world snapshot\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
