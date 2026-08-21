#!/bin/sh
set -eu

export LC_ALL=C
umask 022

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_base='https://persistent.oaistatic.com/codex-app-prod/linux/deb'
repo_key="${script_dir}/openai-codex-linux-repository.asc"
repo_key_sha256='6c8933f828af390b2457f9e2d234082d783d6e4bb1911615b4861c6c61f4ea5a'
package_name='chatgpt'
mode=${1:-install}
updater_data_dir="${CHATGPT_UPDATER_DATA_DIR:-${HOME}/.local/share/chatgpt-arch-updater}"

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

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

cleanup_build_artifacts() {
  find "${build_dir}/dist" -maxdepth 1 -type f \
    -name 'chatgpt-*-x86_64.pkg.tar.zst' -delete 2>/dev/null || true
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
trap 'rm -rf -- "${work_dir}"' EXIT HUP INT TERM

inrelease_file="${work_dir}/InRelease"
release_file="${work_dir}/Release"
packages_file="${work_dir}/Packages"
candidates_file="${work_dir}/candidates"
keyring_file="${work_dir}/openai-repository.gpg"

gpg --batch --yes --dearmor --output "${keyring_file}" "${repo_key}" ||
  fail 'could not prepare the OpenAI repository key'

printf 'Checking the signed OpenAI repository...\n'
curl --proto '=https' --tlsv1.2 -fsSL --retry 1 --retry-max-time 10 \
  --connect-timeout 2 --max-time 8 \
  "${repo_base}/dists/stable/InRelease" -o "${inrelease_file}"
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

curl --proto '=https' --tlsv1.2 -fsSL --retry 1 --retry-max-time 10 \
  --connect-timeout 2 --max-time 8 \
  "${repo_base}/dists/stable/main/binary-amd64/Packages" \
  -o "${packages_file}"
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

latest_package_version="${latest_version}-1"
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

if [ "${installed_version}" != 'not installed' ] &&
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
  install -m644 "${script_dir}/openai-codex-linux-repository.asc" \
    "${build_dir}/openai-codex-linux-repository.asc"
fi

mkdir -p "${build_dir}/dist" "${build_dir}/upstream"
package="${build_dir}/dist/${package_name}-${latest_package_version}-x86_64.pkg.tar.zst"

for command_name in bsdtar fakeroot makepkg; do
  require_command "${command_name}"
done

# Never authorize installation of a previously cached Arch package. Rebuild it
# from the DEB whose checksum was obtained from OpenAI's signed metadata.
rm -f "${package}"
printf 'Building Arch package for ChatGPT %s...\n' "${latest_version}"
(
  cd "${build_dir}"
  CHATGPT_UPSTREAM_VERSION="${latest_version}" \
  CHATGPT_UPSTREAM_URL="${repo_base}/${latest_filename}" \
  CHATGPT_UPSTREAM_SHA256="${latest_sha256}" \
  SRCDEST="${build_dir}/upstream" \
  BUILDDIR="${work_dir}/build" \
  PKGDEST="${build_dir}/dist" \
    makepkg --cleanbuild --noconfirm
)
[ -f "${package}" ] || fail 'makepkg completed without producing the expected package'

sha256sum "${package}"

if [ "${mode}" = '--build-only' ]; then
  printf 'Package ready; installation was skipped.\n'
  exit 0
fi

printf 'Installing with pacman...\n'
if [ "$(id -u)" -eq 0 ]; then
  pacman -U --needed "${package}"
else
  require_command sudo
  sudo pacman -U --needed "${package}"
fi

cleanup_build_artifacts
printf 'ChatGPT %s is installed.\n' "${latest_package_version}"
