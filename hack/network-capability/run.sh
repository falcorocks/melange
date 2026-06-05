#!/usr/bin/env bash
# Network capability matrix test.
#
# For a given runner, builds two probe packages whose pipelines self-assert the
# sandbox network state:
#
#   net-blocked.yaml (capabilities.networking: false) -> curl MUST fail
#   net-open.yaml    (capabilities.networking: true)  -> curl MUST succeed
#
# The assertions live inside the pipelines, so a build that exits 0 means the
# runner enforced the flag correctly. A non-zero exit means the runner ignored
# (or over-applied) capabilities.networking and the test fails.
#
# Usage: run.sh <bubblewrap|docker|qemu>
set -euo pipefail

RUNNER="${1:?usage: run.sh <bubblewrap|docker|qemu>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"

case "$(uname -m)" in
  x86_64|amd64)  ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac
# Allow overriding the target arch. Building for a non-host arch makes the qemu
# runner fall back to TCG software emulation, which lets the qemu matrix run on
# CI hosts that lack /dev/kvm.
ARCH="${MELANGE_ARCH:-${ARCH}}"

# Build the melange binary under test unless one was provided.
MELANGE="${MELANGE_BIN:-}"
if [[ -z "${MELANGE}" ]]; then
  MELANGE="$(mktemp -d)/melange"
  echo "==> building melange from ${REPO_ROOT}"
  ( cd "${REPO_ROOT}" && go build -o "${MELANGE}" . )
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
"${MELANGE}" keygen "${WORK}/melange.rsa" >/dev/null 2>&1

run_case() {
  local name="$1" file="$2"
  echo "==> [${RUNNER}] ${name}"
  if "${MELANGE}" build "${HERE}/${file}" \
      --arch "${ARCH}" \
      --runner "${RUNNER}" \
      --signing-key "${WORK}/melange.rsa" \
      --out-dir "${WORK}/packages-${name}"; then
    echo "PASS: ${name} on ${RUNNER}"
  else
    echo "FAIL: ${name} on ${RUNNER} (capabilities.networking not enforced correctly)" >&2
    exit 1
  fi
}

run_case "blocked" "net-blocked.yaml"
run_case "open" "net-open.yaml"

echo "ALL PASS: capabilities.networking enforced correctly on ${RUNNER}"
