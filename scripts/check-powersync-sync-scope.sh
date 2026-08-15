#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_CONFIG="${LIFLY_POWERSYNC_CONFIG:-$ROOT_DIR/infra/powersync/powersync.yaml}"
SYNC_CONFIG="${LIFLY_POWERSYNC_SYNC_CONFIG:-$ROOT_DIR/infra/powersync/sync-config.yaml}"
REQUIRED_TABLES_PATH="$ROOT_DIR/infra/powersync-required-tables.txt"

for path in "$SERVICE_CONFIG" "$SYNC_CONFIG" "$REQUIRED_TABLES_PATH"; do
  if [[ ! -f "$path" ]]; then
    echo "[FAIL] required PowerSync file not found: $path" >&2
    exit 1
  fi
done

if ! grep -Eq '^[[:space:]]*edition:[[:space:]]*3[[:space:]]*$' "$SYNC_CONFIG"; then
  echo "[FAIL] Sync Streams edition 3 is required" >&2
  exit 1
fi

missing=0
while IFS= read -r table; do
  [[ -z "$table" || "$table" == \#* ]] && continue
  if grep -Eq "FROM[[:space:]]+(public\\.)?${table}([[:space:]]|$)" "$SYNC_CONFIG"; then
    echo "[PASS] encrypted sync stream: $table"
  else
    echo "[FAIL] missing Sync Stream query for: $table" >&2
    missing=1
  fi
done < "$REQUIRED_TABLES_PATH"

for plaintext_table in \
  memos tag_metadata memo_classifications tasks task_reminder_strategies \
  reminders ledger_transactions ledger_accounts ledger_categories ledger_budgets \
  import_batches assets memo_asset_refs audit_logs mcp_undo_actions \
  mcp_capture_sessions mcp_capture_turns tombstones; do
  if grep -Eq "FROM[[:space:]]+(public\\.)?${plaintext_table}([[:space:]]|$)" "$SYNC_CONFIG"; then
    echo "[FAIL] plaintext table leaked into remote Sync Streams: $plaintext_table" >&2
    missing=1
  fi
done

if ! grep -Fq 'WHERE user_id = auth.user_id()' "$SYNC_CONFIG"; then
  echo "[FAIL] encrypted_entities stream is not scoped by authenticated Account" >&2
  missing=1
fi

if ! grep -Fq 'kid: lifly-dev-hs256' "$SERVICE_CONFIG"; then
  echo "[FAIL] PowerSync client auth key id does not match API token issuer" >&2
  missing=1
fi

if ! grep -Fq 'http://localhost:8204' "$SERVICE_CONFIG"; then
  echo "[FAIL] PowerSync client auth audience does not match API default endpoint" >&2
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "PowerSync encrypted sync scope is complete and cloud-blind."
