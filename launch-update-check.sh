#!/bin/sh
set -eu

export LC_ALL=C

official_launcher=${CHATGPT_OFFICIAL_LAUNCHER:-'/usr/lib/chatgpt/codex-launcher'}
installer=${CHATGPT_UPDATE_INSTALLER:-'/usr/lib/chatgpt-arch-updater/install-local.sh'}
package_name='chatgpt'
data_dir=${CHATGPT_UPDATER_DATA_DIR:-"${XDG_DATA_HOME:-${HOME}/.local/share}/chatgpt-arch-updater"}
state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/chatgpt-arch-updater"
runtime_dir=${XDG_RUNTIME_DIR:-"/tmp"}
lock_file="${runtime_dir}/chatgpt-arch-update-check-$(id -u).lock"
lock_held=no
progress_kind=''
progress_service=''
progress_path=''
progress_pid=''
build_log=''
operation_dir=''
phase_pid=''

stop_progress() {
  if [ -n "${phase_pid}" ]; then
    kill "${phase_pid}" >/dev/null 2>&1 || true
    wait "${phase_pid}" 2>/dev/null || true
    phase_pid=''
  fi
  case "${progress_kind}" in
    kdialog)
      timeout 2s qdbus6 "${progress_service}" "${progress_path}" close \
        >/dev/null 2>&1 || true
      kill "${progress_pid}" >/dev/null 2>&1 || true
      wait "${progress_pid}" 2>/dev/null || true
      ;;
    zenity)
      kill "${progress_pid}" >/dev/null 2>&1 || true
      wait "${progress_pid}" 2>/dev/null || true
      ;;
  esac
  progress_kind=''
  progress_service=''
  progress_path=''
  progress_pid=''
}

cleanup() {
  stop_progress
  if [ -n "${build_log}" ]; then
    rm -f -- "${build_log}"
    build_log=''
  fi
  if [ -n "${operation_dir}" ]; then
    rm -rf -- "${operation_dir}"
    operation_dir=''
  fi
  if [ "${lock_held}" = yes ]; then
    flock -u 9 >/dev/null 2>&1 || true
    exec 9>&-
    lock_held=no
  fi
}

start_progress() {
  progress_message='Preparing the ChatGPT update...'

  if command -v kdialog >/dev/null 2>&1 &&
    command -v qdbus6 >/dev/null 2>&1; then
    # kdialog may keep stdout open for the lifetime of its window.
    # Read its D-Bus reference from a file so starting progress cannot block.
    kdialog --title 'ChatGPT Update' --icon chatgpt \
      --progressbar "${progress_message}" 0 >"${operation_dir}/progress-ref" 2>/dev/null &
    progress_pid=$!
    attempts=0
    while [ "${attempts}" -lt 20 ]; do
      progress_ref=$(cat "${operation_dir}/progress-ref" 2>/dev/null || true)
      case "${progress_ref}" in *' '*) break ;; esac
      sleep 0.1
      attempts=$((attempts + 1))
    done
    case "${progress_ref}" in
      *' '*)
        progress_service=${progress_ref%% *}
        progress_path=${progress_ref#* }
        progress_kind=kdialog
        (
          previous=''
          while :; do
            current=$(cat "${operation_dir}/phase" 2>/dev/null || true)
            if [ -n "${current}" ] && [ "${current}" != "${previous}" ]; then
              timeout 2s qdbus6 "${progress_service}" "${progress_path}" \
                setLabelText "${current}" >/dev/null 2>&1 || true
              previous=${current}
            fi
            sleep 0.5
          done
        ) &
        phase_pid=$!
        return
        ;;
    esac
    kill "${progress_pid}" >/dev/null 2>&1 || true
    wait "${progress_pid}" 2>/dev/null || true
    progress_pid=''
  fi

  if command -v zenity >/dev/null 2>&1; then
    (
      while :; do
        current=$(cat "${operation_dir}/phase" 2>/dev/null || true)
        printf '# %s\n' "${current:-${progress_message}}"
        sleep 0.5
      done
    ) | zenity --progress --title='ChatGPT Update' --icon-name=chatgpt \
      --pulsate --no-cancel --auto-close --no-markup \
      --text="${progress_message}" >/dev/null 2>&1 &
    progress_pid=$!
    progress_kind=zenity
  fi
}

launch_chatgpt() {
  cleanup
  trap - EXIT HUP INT TERM
  exec "${official_launcher}" "$@"
}

show_error() {
  stop_progress
  message=$1
  details=${2:-}
  if [ -n "${build_log}" ] && [ -f "${build_log}" ]; then
    printf '\n%s\n' "${message}" >> "${build_log}"
    if (umask 077; mkdir -p "${state_dir}" &&
        cp "${build_log}" "${state_dir}/last-error.log" &&
        chmod 600 "${state_dir}/last-error.log"); then
      details=$(printf '%s\n\nFull log: %s\n\n%s' "${details}" \
        "${state_dir}/last-error.log" "$(tail -n 60 "${build_log}")")
    else
      details=$(printf '%s\n\n%s' "${details}" "$(tail -n 60 "${build_log}")")
    fi
  fi
  if command -v kdialog >/dev/null 2>&1; then
    if [ -n "${details}" ]; then
      kdialog --title 'ChatGPT Update Error' --detailederror "${message}" "${details}" || true
    else
      kdialog --title 'ChatGPT Update Error' --error "${message}" || true
    fi
  elif command -v zenity >/dev/null 2>&1; then
    if [ -n "${build_log}" ] && [ -f "${build_log}" ]; then
      if zenity --question --title='ChatGPT Update Error' --no-markup \
        --text="${message}" --ok-label='Show details' --cancel-label='Close'; then
        zenity --text-info --title='ChatGPT Update Details' \
          --filename="${build_log}" --width=800 --height=500 || true
      fi
    else
      zenity --error --title='ChatGPT Update Error' --no-markup \
        --text="${message}" || true
    fi
  fi
}

show_success() {
  message=$1
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --title 'ChatGPT Update Complete' --icon chatgpt \
      --passivepopup "${message}" 8 || true
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
command -v timeout >/dev/null 2>&1 || exec "${official_launcher}" "$@"

# A second launch must never wait behind an update dialog or build. It opens
# the currently installed application immediately.
exec 9>"${lock_file}"
if ! flock -n 9; then
  exec "${official_launcher}" "$@"
fi
lock_held=yes
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

# Network, signature, or metadata errors must not prevent ChatGPT from opening.
operation_dir=$(mktemp -d "${runtime_dir}/chatgpt-arch-update.XXXXXX") || launch_chatgpt "$@"
if ! status_output=$(CHATGPT_METADATA_DIR="${operation_dir}" \
  timeout --kill-after=1s 5s "${installer}" --check 2>&1); then
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

build_log="${operation_dir}/update.log"
start_progress
if CHATGPT_METADATA_DIR="${operation_dir}" CHATGPT_REUSE_METADATA=1 \
  CHATGPT_PROGRESS_FILE="${operation_dir}/phase" \
  "${installer}" --build-only >"${build_log}" 2>&1; then
  build_succeeded=yes
else
  build_succeeded=no
fi
build_output=$(cat "${build_log}")

if [ "${build_succeeded}" != yes ]; then
  show_error 'The ChatGPT update package could not be prepared.'
  launch_chatgpt "$@"
fi

built_version=$(printf '%s\n' "${build_output}" |
  awk -F': ' '$1 == "Latest OpenAI version" { print $2; exit }')
case "${built_version}" in
  ''|*[!0-9A-Za-z.+_~-]*)
    show_error 'The updater returned an invalid package version.'
    launch_chatgpt "$@"
    ;;
esac

package=$(printf '%s\n' "${build_output}" | sed -n 's/^Package: //p' | tail -n 1)
if [ ! -f "${package}" ] ||
  [ "${built_version}" != "${available_version}" ] ||
  [ "$(pacman -Qp "${package}" 2>/dev/null)" != "${package_name} ${built_version}" ]; then
  show_error 'The updater did not produce the expected Arch package.'
  launch_chatgpt "$@"
fi

if ! command -v pkexec >/dev/null 2>&1; then
  show_error 'The update requires pkexec. Install the polkit package and try again.'
  launch_chatgpt "$@"
fi
printf '%s\n' 'Installing the ChatGPT update...' > "${operation_dir}/phase"
install_status=0
pkexec /usr/bin/pacman -U --needed --noconfirm "${package}" >>"${build_log}" 2>&1 || install_status=$?
case "${install_status}" in
  0) ;;
  126)
    show_error 'Authorization was cancelled. ChatGPT was not updated.'
    launch_chatgpt "$@" ;;
  127)
    show_error 'Authorization failed or the installation command could not start.'
    launch_chatgpt "$@" ;;
  *)
    show_error 'Pacman could not install the ChatGPT update.'
    launch_chatgpt "$@" ;;
esac
stop_progress
if [ "$(pacman -Q "${package_name}" 2>/dev/null)" != "${package_name} ${built_version}" ]; then
  show_error 'The expected ChatGPT version is not installed after running pacman.'
  launch_chatgpt "$@"
fi

find "${data_dir}/dist" -maxdepth 1 -type f \
  -name 'chatgpt-*-x86_64.pkg.tar*' -delete 2>/dev/null || true
find "${data_dir}/upstream" -maxdepth 1 -type f \
  -name 'chatgpt_*_amd64.deb' -delete 2>/dev/null || true

show_success "ChatGPT was updated successfully to version ${built_version}."
launch_chatgpt "$@"
