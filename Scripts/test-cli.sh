#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
cd "${PROJECT_DIR}"
swift build --build-system native --product mactape
CLI="$(swift build --build-system native --show-bin-path)/mactape"
STAGING_DIR="$(mktemp -d -t mactape-cli-test)"
trap '/bin/rm -rf "${STAGING_DIR}"' EXIT

expect_status() {
  local expected="$1"
  shift
  local actual=0
  "$@" > "${STAGING_DIR}/stdout" 2> "${STAGING_DIR}/stderr" || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    print -u2 "Expected exit ${expected}, got ${actual}: $*"
    /bin/cat "${STAGING_DIR}/stdout" "${STAGING_DIR}/stderr"
    exit 1
  fi
}

expect_status 0 "$CLI" version
expect_status 0 "$CLI" help
expect_status 0 "$CLI" validate Examples/01-safe-wait.mactape --json
/usr/bin/plutil -extract valid raw "${STAGING_DIR}/stdout" | /usr/bin/grep -q true
expect_status 0 "$CLI" inspect Examples/02-textedit-draft.mactape
/usr/bin/grep -q '4 enabled / 4 total' "${STAGING_DIR}/stdout"
expect_status 1 "$CLI" validate
expect_status 1 "$CLI" validate Examples/01-safe-wait.mactape --typo
expect_status 1 "$CLI" format Examples/01-safe-wait.mactape --chek
expect_status 1 "$CLI" list --directory
expect_status 1 "$CLI" nonexistent
expect_status 1 "$CLI" validate "${STAGING_DIR}/missing.mactape"
/bin/cp Examples/01-safe-wait.mactape "${STAGING_DIR}/format.mactape"
expect_status 0 "$CLI" format "${STAGING_DIR}/format.mactape"
expect_status 0 "$CLI" format "${STAGING_DIR}/format.mactape" --check
expect_status 0 "$CLI" list --directory "${STAGING_DIR}/library"
print 'CLI smoke tests passed (13 command checks).'
