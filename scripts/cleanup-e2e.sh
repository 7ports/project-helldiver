#!/usr/bin/env bash
# cleanup-e2e.sh — Idempotent cleanup of Helldiver E2E test artifacts.
#
# Usage: cleanup-e2e.sh [CLIENT_LABEL...] [--sauron-repo PATH] [--sauron-url URL]
#
# Removes Pushgateway metrics, Prometheus rules, Grafana dashboards, docs client
# files, and workdir entries for each CLIENT_LABEL. Always cleans up the
# e2e-capability metric. Restores prometheus.yml to git HEAD.
#
# Safe to run multiple times — all steps are idempotent. Cleanup errors are
# non-fatal: the script prints them and continues.

set -uo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_CLIENT_LABELS=("e2e-capability")
CLIENT_LABELS=()
SAURON_REPO="${SAURON_REPO:-}"
SAURON_URL="${SAURON_URL:-https://sauron.7ports.ca}"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sauron-repo)
      SAURON_REPO="$2"
      shift 2
      ;;
    --sauron-url)
      SAURON_URL="$2"
      shift 2
      ;;
    --*)
      echo "ERROR: Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      CLIENT_LABELS+=("$1")
      shift
      ;;
  esac
done

# Use default label if none provided
if [[ ${#CLIENT_LABELS[@]} -eq 0 ]]; then
  CLIENT_LABELS=("${DEFAULT_CLIENT_LABELS[@]}")
fi

# ---------------------------------------------------------------------------
# Auto-detect SAURON_REPO if not set
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$SAURON_REPO" ]]; then
  SAURON_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)/project-sauron"
fi

# ---------------------------------------------------------------------------
# Tracking
# ---------------------------------------------------------------------------
FILES_REMOVED=()
FILES_MISSING=()
ERRORS=()

# ---------------------------------------------------------------------------
# Helper: non-fatal execution — print error but continue
# ---------------------------------------------------------------------------
try() {
  "$@" || {
    local exit_code=$?
    ERRORS+=("Exit $exit_code from: $*")
    echo "  [WARN] Command failed (exit $exit_code): $*" >&2
  }
}

# ---------------------------------------------------------------------------
# Helper: remove a file if it exists, track the result
# ---------------------------------------------------------------------------
remove_if_exists() {
  local path="$1"
  local description="$2"
  if [[ -f "$path" ]]; then
    if rm -f "$path"; then
      FILES_REMOVED+=("$description: $path")
      echo "  [REMOVED] $description"
    else
      ERRORS+=("Failed to remove $path")
      echo "  [ERROR]   Could not remove $description: $path" >&2
    fi
  else
    FILES_MISSING+=("$description: $path")
    echo "  [SKIP]    Not found (already clean): $description"
  fi
}

# ---------------------------------------------------------------------------
# Helper: remove a directory if it exists
# ---------------------------------------------------------------------------
remove_dir_if_exists() {
  local path="$1"
  local description="$2"
  if [[ -d "$path" ]]; then
    if rm -rf "$path"; then
      FILES_REMOVED+=("$description: $path")
      echo "  [REMOVED] $description"
    else
      ERRORS+=("Failed to remove directory $path")
      echo "  [ERROR]   Could not remove $description: $path" >&2
    fi
  else
    FILES_MISSING+=("$description: $path")
    echo "  [SKIP]    Not found (already clean): $description"
  fi
}

# ---------------------------------------------------------------------------
# Main cleanup
# ---------------------------------------------------------------------------
echo "=== Helldiver E2E Cleanup ==="
echo "SAURON_URL:  $SAURON_URL"
echo "SAURON_REPO: $SAURON_REPO"
echo "Labels:      ${CLIENT_LABELS[*]}"
echo ""

# --- Per-label cleanup ---
for CLIENT_LABEL in "${CLIENT_LABELS[@]}"; do
  # Skip the built-in e2e-capability label here — handled separately below
  [[ "$CLIENT_LABEL" == "e2e-capability" ]] && continue

  echo "--- Cleaning label: $CLIENT_LABEL ---"

  # 1. Delete Pushgateway job metrics
  if [[ -n "${PUSH_BEARER_TOKEN:-}" ]]; then
    echo "  Deleting Pushgateway job metrics for $CLIENT_LABEL..."
    try curl -sf -X DELETE \
      -H "Authorization: Bearer $PUSH_BEARER_TOKEN" \
      "$SAURON_URL/metrics/gateway/metrics/job/$CLIENT_LABEL" || true
  else
    echo "  [SKIP] PUSH_BEARER_TOKEN not set — skipping Pushgateway delete for $CLIENT_LABEL"
  fi

  # 2. Remove Prometheus rules file
  remove_if_exists \
    "$SAURON_REPO/monitoring/prometheus/rules/$CLIENT_LABEL.yml" \
    "Prometheus rules ($CLIENT_LABEL)"

  # 3. Remove Grafana dashboard file
  remove_if_exists \
    "$SAURON_REPO/monitoring/grafana/dashboards/$CLIENT_LABEL.json" \
    "Grafana dashboard ($CLIENT_LABEL)"

  # 4. Remove docs client file
  remove_if_exists \
    "$SAURON_REPO/docs/clients/$CLIENT_LABEL.md" \
    "Docs client file ($CLIENT_LABEL)"

  # 5. Remove workdir
  remove_dir_if_exists \
    "/tmp/helldiver-workdir/$CLIENT_LABEL" \
    "Workdir ($CLIENT_LABEL)"

  echo ""
done

# --- Always clean the e2e-capability test metric ---
echo "--- Cleaning built-in label: e2e-capability ---"
if [[ -n "${PUSH_BEARER_TOKEN:-}" ]]; then
  echo "  Deleting Pushgateway job metrics for e2e-capability..."
  try curl -sf -X DELETE \
    -H "Authorization: Bearer $PUSH_BEARER_TOKEN" \
    "$SAURON_URL/metrics/gateway/metrics/job/e2e-capability" || true
else
  echo "  [SKIP] PUSH_BEARER_TOKEN not set — skipping Pushgateway delete for e2e-capability"
fi
echo ""

# --- Restore prometheus.yml to git HEAD ---
echo "--- Restoring prometheus.yml to git HEAD ---"
if [[ -d "$SAURON_REPO/.git" ]]; then
  if git -C "$SAURON_REPO" restore monitoring/prometheus/prometheus.yml 2>/dev/null; then
    echo "  [RESTORED] monitoring/prometheus/prometheus.yml"
    FILES_REMOVED+=("prometheus.yml surgical edits (git restore)")
  else
    # Already clean — not an error
    echo "  [SKIP] prometheus.yml already matches HEAD (or git restore unavailable)"
  fi
else
  echo "  [WARN] $SAURON_REPO is not a git repository — skipping git restore" >&2
  ERRORS+=("SAURON_REPO is not a git repo: $SAURON_REPO")
fi
echo ""

# ---------------------------------------------------------------------------
# Verification: confirm no CLIENT_LABEL files remain in sauron monitoring dirs
# ---------------------------------------------------------------------------
echo "=== Cleanup Verification ==="
VERIFY_PASSED=true
for CLIENT_LABEL in "${CLIENT_LABELS[@]}"; do
  [[ "$CLIENT_LABEL" == "e2e-capability" ]] && continue

  for check_path in \
    "$SAURON_REPO/monitoring/prometheus/rules/$CLIENT_LABEL.yml" \
    "$SAURON_REPO/monitoring/grafana/dashboards/$CLIENT_LABEL.json" \
    "$SAURON_REPO/docs/clients/$CLIENT_LABEL.md"; do
    if [[ -f "$check_path" ]]; then
      echo "  [WARN] File still exists after cleanup: $check_path" >&2
      VERIFY_PASSED=false
    fi
  done
done

if [[ "$VERIFY_PASSED" == "true" ]]; then
  echo "  Verification: all CLIENT_LABEL files removed from sauron monitoring directories."
else
  echo "  Verification: some files could not be removed (see warnings above)."
fi
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== Cleanup Summary ==="
echo "Removed (${#FILES_REMOVED[@]}):"
if [[ ${#FILES_REMOVED[@]} -gt 0 ]]; then
  for item in "${FILES_REMOVED[@]}"; do
    echo "  + $item"
  done
else
  echo "  (nothing — all artifacts were already absent)"
fi

echo ""
echo "Already absent / skipped (${#FILES_MISSING[@]}):"
for item in "${FILES_MISSING[@]}"; do
  echo "  - $item"
done

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Non-fatal errors encountered (${#ERRORS[@]}):"
  for err in "${ERRORS[@]}"; do
    echo "  ! $err"
  done
fi

echo ""
echo "Cleanup complete."

# Exit 0 — cleanup errors are non-fatal by design
exit 0
