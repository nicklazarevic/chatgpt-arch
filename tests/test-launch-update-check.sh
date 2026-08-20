#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/chatgpt-launch-test.XXXXXX")
trap 'rm -rf -- "${test_dir}"' EXIT HUP INT TERM

bin_dir="${test_dir}/bin"
runtime_dir="${test_dir}/runtime"
data_dir="${test_dir}/data"
log_file="${test_dir}/events.log"
mkdir -p "${bin_dir}" "${runtime_dir}" "${data_dir}"

cat > "${bin_dir}/official-launcher" <<'EOF'
#!/bin/sh
printf 'app' >> "${TEST_LOG}"
for argument in "$@"; do
  printf '|%s' "${argument}" >> "${TEST_LOG}"
done
printf '\n' >> "${TEST_LOG}"
EOF

cat > "${bin_dir}/installer" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --check)
    [ "${TEST_CHECK_FAIL:-no}" = no ] || exit 1
    printf 'Installed: %s\nLatest OpenAI version: %s\n' \
      "${TEST_INSTALLED}" "${TEST_AVAILABLE}"
    ;;
  --build-only)
    mkdir -p "${CHATGPT_UPDATER_DATA_DIR}/dist"
    : > "${CHATGPT_UPDATER_DATA_DIR}/dist/chatgpt-${TEST_AVAILABLE}-x86_64.pkg.tar.zst"
    printf 'Installed: %s\nLatest OpenAI version: %s\n' \
      "${TEST_INSTALLED}" "${TEST_AVAILABLE}"
    ;;
  *) exit 2 ;;
esac
EOF

cat > "${bin_dir}/kdialog" <<'EOF'
#!/bin/sh
printf 'dialog:%s\n' "$*" >> "${TEST_LOG}"
case " $* " in
  *' --yesno '*) [ "${TEST_DIALOG:-later}" = update ] ;;
  *) exit 0 ;;
esac
EOF

cat > "${bin_dir}/pkexec" <<'EOF'
#!/bin/sh
printf 'pkexec:%s\n' "$*" >> "${TEST_LOG}"
exit 0
EOF

chmod +x "${bin_dir}/official-launcher" "${bin_dir}/installer" \
  "${bin_dir}/kdialog" "${bin_dir}/pkexec"

run_launcher() {
  TEST_LOG="${log_file}" \
  TEST_INSTALLED=${TEST_INSTALLED} \
  TEST_AVAILABLE=${TEST_AVAILABLE} \
  TEST_DIALOG=${TEST_DIALOG:-later} \
  TEST_CHECK_FAIL=${TEST_CHECK_FAIL:-no} \
  CHATGPT_OFFICIAL_LAUNCHER="${bin_dir}/official-launcher" \
  CHATGPT_UPDATE_INSTALLER="${bin_dir}/installer" \
  CHATGPT_UPDATER_DATA_DIR="${data_dir}" \
  XDG_RUNTIME_DIR="${runtime_dir}" \
  PATH="${bin_dir}:${PATH}" \
    "${repo_dir}/launch-update-check.sh" --test 'two words'
}

assert_contains() {
  grep -Fq "$1" "${log_file}" || {
    printf 'missing expected event: %s\n' "$1" >&2
    cat "${log_file}" >&2
    exit 1
  }
}

assert_not_contains() {
  if grep -Fq "$1" "${log_file}"; then
    printf 'unexpected event: %s\n' "$1" >&2
    cat "${log_file}" >&2
    exit 1
  fi
}

: > "${log_file}"
TEST_INSTALLED=1.0-1 TEST_AVAILABLE=1.0-1 TEST_DIALOG=later run_launcher
assert_contains 'app|--test|two words'
assert_not_contains 'dialog:'

: > "${log_file}"
TEST_INSTALLED=1.0-1 TEST_AVAILABLE=1.1-1 TEST_DIALOG=later run_launcher
assert_contains 'dialog:'
assert_contains 'app|--test|two words'
assert_not_contains 'pkexec:'

: > "${log_file}"
TEST_INSTALLED=1.0-1 TEST_AVAILABLE=1.1-1 TEST_DIALOG=update run_launcher
assert_contains 'pkexec:/usr/bin/pacman -U --needed'
assert_contains 'app|--test|two words'

: > "${log_file}"
TEST_INSTALLED=1.0-1 TEST_AVAILABLE=1.1-1 TEST_CHECK_FAIL=yes \
  TEST_DIALOG=update run_launcher
assert_contains 'app|--test|two words'
assert_not_contains 'dialog:'

printf 'launch update checks: OK\n'
