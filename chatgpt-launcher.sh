#!/bin/sh
set -eu

official_launcher=${CHATGPT_OFFICIAL_LAUNCHER:-'/usr/lib/chatgpt/codex-launcher'}
update_launcher=${CHATGPT_UPDATE_LAUNCHER:-'/usr/lib/chatgpt-arch-updater/launch-update-check.sh'}

if [ "${CHATGPT_SKIP_UPDATE_CHECK:-0}" != '1' ] &&
  [ -x "${update_launcher}" ]; then
  exec "${update_launcher}" "$@"
fi

exec "${official_launcher}" "$@"
