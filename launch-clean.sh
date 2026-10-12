#!/bin/sh
# Start the installed application outside an inherited Voice overlay namespace.
set -eu

script_path=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/launch-clean.sh

if [ "${1:-}" = '--verify-host' ]; then
  if awk '$5 == "/usr/lib/chatgpt/resources/app.asar" { found = 1 }
          END { exit !found }' /proc/self/mountinfo; then
    printf 'The application archive is covered by a mount; clean launch refused.\n' >&2
    exit 1
  fi
  [ -x /usr/bin/chatgpt ] || exit 127
  sha256sum /usr/lib/chatgpt/resources/app.asar
  exit 0
fi

command -v systemd-run >/dev/null 2>&1 || {
  printf 'Clean launch requires the systemd user service manager.\n' >&2
  exit 1
}

# The user service manager starts commands in the host mount namespace.
systemd-run --user --quiet --wait --pipe --collect \
  /bin/sh "$script_path" --verify-host

if [ "${1:-}" = '--check' ]; then
  exit 0
fi

command -v pgrep >/dev/null 2>&1 || exit 127
if pgrep -u "$(id -u)" -x ChatGPT >/dev/null 2>&1; then
  printf 'Quit all ChatGPT windows first, then run this command again.\n' >&2
  printf 'An existing process would reuse its Voice overlay session.\n' >&2
  exit 1
fi

exec systemd-run --user --quiet --collect \
  /usr/bin/env CHATGPT_SKIP_UPDATE_CHECK=1 /usr/bin/chatgpt "$@"
