#!/bin/sh
set -eu

export LC_ALL=C

official_launcher=${CHATGPT_OFFICIAL_LAUNCHER:-'/usr/lib/chatgpt/codex-launcher'}
installer=${CHATGPT_UPDATE_INSTALLER:-'/usr/lib/chatgpt-arch-updater/install-local.sh'}
package_name='chatgpt'
data_dir=${CHATGPT_UPDATER_DATA_DIR:-"${HOME}/.local/share/chatgpt-arch-updater"}
runtime_dir=${XDG_RUNTIME_DIR:-"/tmp"}
lock_file="${runtime_dir}/chatgpt-arch-update-check-$(id -u).lock"
lock_held=no

cleanup() {
  if [ "${lock_held}" = yes ]; then
    flock -u 9 >/dev/null 2>&1 || true
    exec 9>&-
    lock_held=no
  fi
}

launch_chatgpt() {
  cleanup
  trap - EXIT HUP INT TERM
  exec "${official_launcher}" "$@"
}

show_error() {
  message=$1
  details=${2:-}
  if command -v kdialog >/dev/null 2>&1; then
    if [ -n "${details}" ]; then
      kdialog --title 'ChatGPT Update Error' --detailederror "${message}" "${details}" || true
    else
      kdialog --title 'ChatGPT Update Error' --error "${message}" || true
    fi
  elif command -v zenity >/dev/null 2>&1; then
    if [ -n "${details}" ]; then
      dialog_text=$(printf '%s\n\n%s' "${message}" "${details}")
    else
      dialog_text=${message}
    fi
    zenity --error --title='ChatGPT Update Error' --no-markup \
      --text="${dialog_text}" || true
  fi
}

show_success() {
  message=$1
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --title 'ChatGPT Update Complete' --msgbox "${message}" || true
  elif command -v zenity >/dev/null 2>&1; then
    zenity --info --title='ChatGPT Update Complete' --no-markup \
      --text="${message}" || true
  fi
}

ask_to_update() {
  message=$1
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --title 'ChatGPT Update Available' --icon chatgpt \
      --yes-label 'Update' --no-label 'Later' --yesno "${message}"
  elif command -v zenity >/dev/null 2>&1; then
    zenity --question --title='ChatGPT Update Available' --icon=chatgpt \
      --no-markup --ok-label='Update' --cancel-label='Later' \
      --text="${message}"
  else
    return 1
  fi
}

[ -x "${official_launcher}" ] || exit 127
[ -x "${installer}" ] || exec "${official_launcher}" "$@"
command -v flock >/dev/null 2>&1 || exec "${official_launcher}" "$@"

# A second launch must never wait behind an update dialog or build. It opens
# the currently installed application immediately.
exec 9>"${lock_file}"
if ! flock -n 9; then
  exec "${official_launcher}" "$@"
fi
lock_held=yes
trap cleanup EXIT HUP INT TERM

# Network, signature, or metadata errors must not prevent ChatGPT from opening.
if ! status_output=$("${installer}" --check 2>&1); then
  launch_chatgpt "$@"
fi

installed_version=$(printf '%s\n' "${status_output}" |
  awk -F': ' '$1 == "Installed" { print $2; exit }')
available_version=$(printf '%s\n' "${status_output}" |
  awk -F': ' '$1 == "Latest OpenAI version" { print $2; exit }')

case "${installed_version}" in
  ''|'not installed') launch_chatgpt "$@" ;;
esac
case "${available_version}" in
  ''|*[!0-9A-Za-z.+_~-]*) launch_chatgpt "$@" ;;
esac

if [ "$(vercmp "${available_version}" "${installed_version}")" -le 0 ]; then
  launch_chatgpt "$@"
fi

dialog_message=$(printf '%s\n\n%s\n%s\n\n%s' \
  'A new ChatGPT desktop update is available.' \
  "Installed version: ${installed_version}" \
  "Available version: ${available_version}" \
  'Install the update before opening ChatGPT?')

if ! ask_to_update "${dialog_message}"; then
  launch_chatgpt "$@"
fi

if command -v kdialog >/dev/null 2>&1; then
  kdialog --title 'ChatGPT Update' --icon chatgpt \
    --passivepopup 'Downloading and preparing the update…' 5 || true
fi

if ! build_output=$("${installer}" --build-only 2>&1); then
  show_error 'The ChatGPT update package could not be prepared.' "${build_output}"
  launch_chatgpt "$@"
fi

built_version=$(printf '%s\n' "${build_output}" |
  awk -F': ' '$1 == "Latest OpenAI version" { print $2; exit }')
case "${built_version}" in
  ''|*[!0-9A-Za-z.+_~-]*)
    show_error 'The updater returned an invalid package version.' "${build_output}"
    launch_chatgpt "$@"
    ;;
esac

package="${data_dir}/dist/${package_name}-${built_version}-x86_64.pkg.tar.zst"
if [ ! -f "${package}" ]; then
  show_error 'The updater did not produce the expected Arch package.' "${build_output}"
  launch_chatgpt "$@"
fi

if ! command -v pkexec >/dev/null 2>&1 ||
  ! pkexec /usr/bin/pacman -U --needed "${package}"; then
  show_error 'The ChatGPT update was not installed.' \
    'Authentication may have been cancelled, or pacman reported an error.'
  launch_chatgpt "$@"
fi

find "${data_dir}/dist" -maxdepth 1 -type f \
  -name 'chatgpt-*-x86_64.pkg.tar.zst' -delete 2>/dev/null || true
find "${data_dir}/upstream" -maxdepth 1 -type f \
  -name 'chatgpt_*_amd64.deb' -delete 2>/dev/null || true

show_success "ChatGPT was updated successfully to version ${built_version}."
launch_chatgpt "$@"
