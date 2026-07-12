#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${LIFLY_POWERSYNC_CONFIG:-$ROOT_DIR/infra/powersync/powersync.yaml}"
REQUIRED_TABLES_PATH="$ROOT_DIR/infra/powersync-required-tables.txt"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[FAIL] PowerSync config not found: $CONFIG_PATH" >&2
  echo "Set LIFLY_POWERSYNC_CONFIG to the deployment config path." >&2
  exit 1
fi

if [[ ! -f "$REQUIRED_TABLES_PATH" ]]; then
  echo "[FAIL] Required table list not found: $REQUIRED_TABLES_PATH" >&2
  exit 1
fi

missing=0
while IFS= read -r table; do
  [[ -z "$table" || "$table" == \#* ]] && continue
  if grep -Eq "^[[:space:]]*-[[:space:]]+table:[[:space:]]+(public\\.)?${table}[[:space:]]*$" "$CONFIG_PATH"; then
    echo "[PASS] $table"
  else
    echo "[FAIL] missing sync rule: $table" >&2
    missing=1
  fi
done < "$REQUIRED_TABLES_PATH"

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "PowerSync sync scope is complete."
