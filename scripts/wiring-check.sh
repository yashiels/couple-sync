#!/usr/bin/env bash
# wiring-check.sh — Validates that all items in wiring-checklist.json pass.
# Each item specifies a file, a grep pattern, and a human-readable description.
# Exits 0 if all items pass, 1 if any item fails.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKLIST="${REPO_ROOT}/wiring-checklist.json"

if [[ ! -f "${CHECKLIST}" ]]; then
  echo "ERROR: wiring-checklist.json not found at ${CHECKLIST}" >&2
  exit 1
fi

pass=0
fail=0

# Read each checklist item with jq
item_count=$(jq 'length' "${CHECKLIST}")

for i in $(seq 0 $((item_count - 1))); do
  file=$(jq -r ".[$i].file" "${CHECKLIST}")
  pattern=$(jq -r ".[$i].pattern" "${CHECKLIST}")
  description=$(jq -r ".[$i].description" "${CHECKLIST}")

  target="${REPO_ROOT}/${file}"

  if [[ ! -f "${target}" ]]; then
    echo "FAIL [missing file] ${file}: ${description}"
    ((fail++)) || true
    continue
  fi

  if grep -qE "${pattern}" "${target}"; then
    echo "PASS ${file}: ${description}"
    ((pass++)) || true
  else
    echo "FAIL [pattern '${pattern}' not found] ${file}: ${description}"
    ((fail++)) || true
  fi
done

echo ""
echo "Results: ${pass} passed, ${fail} failed"

if [[ ${fail} -gt 0 ]]; then
  exit 1
fi
exit 0
