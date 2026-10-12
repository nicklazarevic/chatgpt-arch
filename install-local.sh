#!/bin/sh
set -eu

export LC_ALL=C
umask 022

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_base='https://persistent.oaistatic.com/codex-app-prod/linux/deb'
repo_key="${script_dir}/openai-codex-linux-repository.key"
repo_key_sha256='6c8933f828af390b2457f9e2d234082d783d6e4bb1911615b4861c6c61f4ea5a'
package_name='chatgpt'
mode=${1:-install}
updater_data_dir="${CHATGPT_UPDATER_DATA_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/chatgpt-arch-updater}"

case "${mode}" in
  install|--check|--build-only) ;;
  *)
    printf 'Usage: %s [--check|--build-only]\n' "$0" >&2
    exit 2
    ;;
esac

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

phase() {
  printf '%s\n' "$1"
  if [ -n "${CHATGPT_PROGRESS_FILE:-}" ]; then
    printf '%s\n' "$1" > "${CHATGPT_PROGRESS_FILE}"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

cleanup_build_artifacts() {
  find "${build_dir}/dist" -maxdepth 1 -type f \
    -name 'chatgpt-*-x86_64.pkg.tar*' -delete 2>/dev/null || true
  find "${build_dir}/upstream" -maxdepth 1 -type f \
    -name 'chatgpt_*_amd64.deb' -delete 2>/dev/null || true
}

for command_name in awk curl gpg gpgv grep pacman sha256sum uname vercmp; do
  require_command "${command_name}"
done

[ "$(uname -m)" = x86_64 ] || fail 'this installer currently supports x86_64 only'
[ -r "${repo_key}" ] || fail "OpenAI repository key not found: ${repo_key}"

actual_key_sha256=$(sha256sum "${repo_key}" | awk '{ print $1 }')
[ "${actual_key_sha256}" = "${repo_key_sha256}" ] ||
  fail 'the bundled OpenAI repository key failed its integrity check'

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/chatgpt-arch-installer.XXXXXX")
trap 'rm -rf -- "${work_dir}"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
# The desktop launcher supplies a private directory for this one update.
metadata_dir=${CHATGPT_METADATA_DIR:-${work_dir}}

inrelease_file="${metadata_dir}/InRelease"
release_file="${work_dir}/Release"
packages_file="${metadata_dir}/Packages"
candidates_file="${work_dir}/candidates"
keyring_file="${work_dir}/openai-repository.gpg"

gpg --batch --yes --dearmor --output "${keyring_file}" "${repo_key}" ||
  fail 'could not prepare the OpenAI repository key'

phase 'Checking the signed OpenAI repository...'
if [ "${CHATGPT_REUSE_METADATA:-0}" != 1 ]; then
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --retry 1 --retry-max-time 10 \
    --connect-timeout 2 --max-time 8 \
    "${repo_base}/dists/stable/InRelease" -o "${inrelease_file}"
fi
gpgv --keyring "${keyring_file}" --output "${release_file}" \
  "${inrelease_file}" >/dev/null 2>&1 ||
  fail 'OpenAI repository signature verification failed'

packages_sha256=$(awk '
  $1 == "SHA256:" { in_sha256 = 1; next }
  in_sha256 && $3 == "main/binary-amd64/Packages" { print $1; exit }
  in_sha256 && $0 !~ /^[[:space:]]/ { exit }
' "${release_file}")

printf '%s\n' "${packages_sha256}" |
  grep -Eq '^[0-9a-f]{64}$' || fail 'invalid Packages checksum in signed metadata'

if [ "${CHATGPT_REUSE_METADATA:-0}" != 1 ]; then
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --retry 1 --retry-max-time 10 \
    --connect-timeout 2 --max-time 8 \
    "${repo_base}/dists/stable/main/binary-amd64/Packages" \
    -o "${packages_file}"
fi
printf '%s  %s\n' "${packages_sha256}" "${packages_file}" |
  sha256sum -c - >/dev/null || fail 'Packages checksum verification failed'

awk 'BEGIN { RS = ""; FS = "\n" }
  {
    package = version = architecture = filename = checksum = ""
    for (line = 1; line <= NF; line++) {
      if ($line ~ /^Package: /) {
        package = $line; sub(/^Package: /, "", package)
      } else if ($line ~ /^Version: /) {
        version = $line; sub(/^Version: /, "", version)
      } else if ($line ~ /^Architecture: /) {
        architecture = $line; sub(/^Architecture: /, "", architecture)
      } else if ($line ~ /^Filename: /) {
        filename = $line; sub(/^Filename: /, "", filename)
      } else if ($line ~ /^SHA256: /) {
        checksum = $line; sub(/^SHA256: /, "", checksum)
      }
    }
    if (package == "chatgpt" && architecture == "amd64") {
      printf "%s\t%s\t%s\n", version, filename, checksum
    }
  }
' "${packages_file}" > "${candidates_file}"

latest_version=''
latest_filename=''
latest_sha256=''
tab=$(printf '\t')
while IFS="${tab}" read -r candidate_version candidate_filename candidate_sha256; do
  [ -n "${candidate_version}" ] || continue
  if [ -z "${latest_version}" ] ||
    [ "$(vercmp "${candidate_version}" "${latest_version}")" -gt 0 ]; then
    latest_version=${candidate_version}
    latest_filename=${candidate_filename}
    latest_sha256=${candidate_sha256}
  fi
done < "${candidates_file}"

case "${latest_version}" in
  ''|*[!0-9A-Za-z.+_~]*) fail 'invalid version in OpenAI metadata' ;;
esac
case "${latest_filename}" in
  pool/main/c/chatgpt/chatgpt_*_amd64.deb) ;;
  *) fail 'unexpected package path in OpenAI metadata' ;;
esac
case "${latest_filename}" in
  *..*) fail 'unsafe package path in OpenAI metadata' ;;
esac
printf '%s\n' "${latest_sha256}" |
  grep -Eq '^[0-9a-f]{64}$' || fail 'invalid package checksum in OpenAI metadata'

package_revision=$(awk '/^pkgrel=[1-9][0-9]*$/ { sub(/^pkgrel=/, ""); print; exit }' "${script_dir}/PKGBUILD")
[ -n "${package_revision}" ] || fail 'invalid packaging revision in PKGBUILD'
latest_package_version="${latest_version}-${package_revision}"
if pacman -Q "${package_name}" >/dev/null 2>&1; then
  installed_version=$(pacman -Q "${package_name}" | awk '{ print $2 }')
else
  installed_version='not installed'
fi

printf 'Installed: %s\nLatest OpenAI version: %s\n' \
  "${installed_version}" "${latest_package_version}"

if [ "${mode}" = '--check' ]; then
  exit 0
fi

if [ "${mode}" = install ] && [ "${installed_version}" != 'not installed' ] &&
  [ "$(vercmp "${installed_version}" "${latest_package_version}")" -ge 0 ]; then
  printf 'ChatGPT is already up to date.\n'
  exit 0
fi

build_dir=${script_dir}
if [ "${script_dir}" = '/usr/lib/chatgpt-arch-updater' ]; then
  build_dir=${updater_data_dir}
  mkdir -p "${build_dir}"
  install -m755 "${script_dir}/install-local.sh" "${build_dir}/install-local.sh"
  install -m755 "${script_dir}/launch-update-check.sh" "${build_dir}/launch-update-check.sh"
  install -m755 "${script_dir}/chatgpt-launcher.sh" "${build_dir}/chatgpt-launcher.sh"
  install -m644 "${script_dir}/PKGBUILD" "${build_dir}/PKGBUILD"
  install -m644 "${script_dir}/chatgpt.install" "${build_dir}/chatgpt.install"
  install -m644 "${script_dir}/openai-codex-linux-repository.key" \
    "${build_dir}/openai-codex-linux-repository.key"
fi

mkdir -p "${build_dir}/dist" "${build_dir}/upstream"

for command_name in bsdtar fakeroot makepkg; do
  require_command "${command_name}"
done

export CHATGPT_UPSTREAM_VERSION="${latest_version}"
export CHATGPT_UPSTREAM_URL="${repo_base}/${latest_filename}"
export CHATGPT_UPSTREAM_SHA256="${latest_sha256}"
export SRCDEST="${build_dir}/upstream"
export BUILDDIR="${work_dir}/build"
export PKGDEST="${build_dir}/dist"
package=$(cd "${build_dir}" && makepkg --packagelist)
[ "$(printf '%s\n' "${package}" | wc -l)" -eq 1 ] || fail 'expected one Arch package'
case "${package}" in
  "${PKGDEST}/${package_name}-${latest_package_version}-x86_64.pkg.tar"*) ;;
  *) fail 'makepkg returned an unexpected package path' ;;
esac

# Always rebuild the Arch package from the verified upstream download.
rm -f -- "${package}" "${package}.sig"
deb_file="${SRCDEST}/chatgpt_${latest_version}_amd64.deb"
if [ ! -f "${deb_file}" ]; then
  phase 'Downloading ChatGPT...'
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fL --retry 2 \
    --connect-timeout 10 --speed-limit 1024 --speed-time 30 \
    "${CHATGPT_UPSTREAM_URL}" -o "${work_dir}/chatgpt.deb"
  deb_file="${work_dir}/chatgpt.deb"
fi
phase 'Verifying the ChatGPT download...'
if ! printf '%s  %s\n' "${latest_sha256}" "${deb_file}" | sha256sum -c -; then
  rm -f -- "${deb_file}"
  fail 'ChatGPT download checksum verification failed; retry to download it again'
fi
if [ "${deb_file}" = "${work_dir}/chatgpt.deb" ]; then
  mv "${deb_file}" "${SRCDEST}/chatgpt_${latest_version}_amd64.deb"
fi
phase 'Preparing the Arch package...'
(cd "${build_dir}" && makepkg --cleanbuild --noconfirm --nocolor)
[ -f "${package}" ] || fail 'makepkg completed without producing the expected package'

[ "$(pacman -Qp "${package}")" = "${package_name} ${latest_package_version}" ] ||
  fail 'the built package has unexpected metadata'
sha256sum "${package}"
printf 'Package: %s\n' "${package}"

if [ "${mode}" = '--build-only' ]; then
  printf 'Package ready; installation was skipped.\n'
  exit 0
fi

voice_dry_run="${HOME}/.local/share/chatgpt-voice-overlay/dry-run-candidate.sh"
phase 'Checking the voice overlay against this update...'
if [ ! -x "${voice_dry_run}" ] || ! CHATGPT_UPDATE_NOTIFY=1 "${voice_dry_run}" "${package}"; then
  fail 'ChatGPT was not updated. The current version was left in place so its settings stay'
fi

phase 'Installing the ChatGPT update...'
if [ "$(id -u)" -eq 0 ]; then
  pacman -U --needed "${package}"
else
  require_command sudo
  sudo pacman -U --needed "${package}"
fi

cleanup_build_artifacts
printf 'ChatGPT %s is installed.\n' "${latest_package_version}"
