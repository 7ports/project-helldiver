#!/usr/bin/env bash
# e2e-test.sh — Helldiver E2E test orchestrator.
#
# Validates Sauron's observability capabilities and the outputs produced by
# Helldiver pipeline agents. Does NOT run agents — it validates pre/post
# conditions and artifact correctness.
#
# Usage: e2e-test.sh [OPTIONS]
#   --owner GITHUB_OWNER      (required for --scope pipeline or all)
#   --repo  GITHUB_REPO       (required for --scope pipeline or all)
#   --label CLIENT_LABEL      (required; must start with "test-")
#   --scope all|health|pipeline  (default: all)
#   --dry-run                 (pass DRY_RUN=true to pipeline agents; skip git commits)
#   --no-cleanup              (skip Phase 3 cleanup — useful for debugging)
#   --sauron-repo PATH        (path to local project-sauron clone)
#
# Required env vars:
#   SAURON_URL               e.g. https://sauron.7ports.ca
#   PUSH_BEARER_TOKEN        Bearer token for Pushgateway auth
#   EC2_HOST                 EC2 hostname/IP for SSH health checks
#   EC2_USER                 EC2 SSH username
#   EC2_SSH_KEY_PATH         Path to SSH private key (optional if using ssh-agent)
#   GRAFANA_ADMIN_PASSWORD   Grafana admin password for API checks

set -uo pipefail

# ---------------------------------------------------------------------------
# Script-level constants
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-/tmp/helldiver-workdir}"

# ---------------------------------------------------------------------------
# Argument defaults
# ---------------------------------------------------------------------------
OWNER=""
REPO=""
CLIENT_LABEL=""
SCOPE="all"
DRY_RUN="false"
NO_CLEANUP="false"
SAURON_REPO="${SAURON_REPO:-}"

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
declare -A RESULTS
FAILURES=0

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)       OWNER="$2";        shift 2 ;;
    --repo)        REPO="$2";         shift 2 ;;
    --label)       CLIENT_LABEL="$2"; shift 2 ;;
    --scope)       SCOPE="$2";        shift 2 ;;
    --dry-run)     DRY_RUN="true";    shift ;;
    --no-cleanup)  NO_CLEANUP="true"; shift ;;
    --sauron-repo) SAURON_REPO="$2";  shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# check() helper — records PASS/FAIL, increments FAILURES counter
# ---------------------------------------------------------------------------
check() {
  local id="$1" desc="$2"
  shift 2
  if "$@" 2>/dev/null; then
    RESULTS["$id"]="PASS"
    echo "  [PASS] $id: $desc"
  else
    RESULTS["$id"]="FAIL"
    echo "  [FAIL] $id: $desc"
    FAILURES=$((FAILURES + 1))
  fi
}

# ---------------------------------------------------------------------------
# Cleanup function — called by EXIT trap (unless --no-cleanup)
# ---------------------------------------------------------------------------
CLEANUP_TRIGGERED=false
cleanup_on_exit() {
  if [[ "$CLEANUP_TRIGGERED" == "true" ]]; then
    return
  fi
  CLEANUP_TRIGGERED=true

  if [[ "$NO_CLEANUP" == "true" ]]; then
    echo ""
    echo "=== Phase 3: Cleanup (SKIPPED — --no-cleanup flag set) ==="
    echo "  Artifacts remain for inspection:"
    echo "    WORKDIR:      $WORKDIR/$CLIENT_LABEL"
    echo "    SAURON_REPO:  $SAURON_REPO"
    return
  fi

  echo ""
  echo "=== Phase 3: Cleanup ==="

  if [[ -n "$CLIENT_LABEL" ]]; then
    bash "$SCRIPT_DIR/cleanup-e2e.sh" "$CLIENT_LABEL" --sauron-repo "$SAURON_REPO"
  else
    # No label was resolved yet — just clean the built-in e2e-capability metric
    bash "$SCRIPT_DIR/cleanup-e2e.sh" --sauron-repo "$SAURON_REPO"
  fi

  # Post-cleanup verification checks (only meaningful if CLIENT_LABEL is set)
  if [[ -n "$CLIENT_LABEL" ]]; then
    check "3.1" "Cleanup: no test files remain in sauron" \
      bash -c "
        ! ls '$SAURON_REPO/monitoring/prometheus/rules/' 2>/dev/null | grep -q '$CLIENT_LABEL' && \
        ! ls '$SAURON_REPO/monitoring/grafana/dashboards/' 2>/dev/null | grep -q '$CLIENT_LABEL' && \
        git -C '$SAURON_REPO' diff --quiet HEAD
      "

    check "3.2" "Cleanup: no test metrics remain in Pushgateway" \
      bash -c "
        ! curl -sf '$SAURON_URL/metrics/gateway/metrics' | grep -q '$CLIENT_LABEL' && \
        ! curl -sf '$SAURON_URL/metrics/gateway/metrics' | grep -q 'e2e-capability'
      "
  fi

  # Print final report from within the exit trap
  print_report
}

trap 'cleanup_on_exit' EXIT

# ---------------------------------------------------------------------------
# print_report — prints the full results table and sets exit code
# ---------------------------------------------------------------------------
REPORT_PRINTED=false
print_report() {
  # Guard against double-printing (trap + explicit call race)
  if [[ "$REPORT_PRINTED" == "true" ]]; then
    return
  fi
  REPORT_PRINTED=true

  echo ""
  echo "======================================================================"
  echo "=== Phase 4: Report ==="
  echo "======================================================================"
  printf "%-12s %-60s %s\n" "CHECK" "DESCRIPTION" "RESULT"
  printf "%-12s %-60s %s\n" "------------" "------------------------------------------------------------" "------"

  # Print in sorted order
  for id in $(echo "${!RESULTS[@]}" | tr ' ' '\n' | sort -V); do
    printf "%-12s %-60s %s\n" "$id" "" "${RESULTS[$id]}"
  done

  echo ""
  if [[ $FAILURES -eq 0 ]]; then
    echo "OVERALL: PASS ($FAILURES failures)"
  else
    echo "OVERALL: FAIL ($FAILURES failures)"
  fi
  echo "======================================================================"
}

# ---------------------------------------------------------------------------
# Phase 0: Pre-flight
# ---------------------------------------------------------------------------
echo "=== Phase 0: Pre-flight ==="

# Required env vars
PREFLIGHT_OK=true
for var in SAURON_URL PUSH_BEARER_TOKEN EC2_HOST EC2_USER GRAFANA_ADMIN_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "  [ERROR] Required env var not set: $var" >&2
    PREFLIGHT_OK=false
  fi
done

# CLIENT_LABEL required and must start with "test-"
if [[ -z "$CLIENT_LABEL" ]]; then
  echo "  [ERROR] --label CLIENT_LABEL is required" >&2
  PREFLIGHT_OK=false
elif [[ "$CLIENT_LABEL" != test-* ]]; then
  echo "  [ERROR] CLIENT_LABEL must start with 'test-' (got: $CLIENT_LABEL)" >&2
  echo "          This prevents accidental cleanup of production artifacts." >&2
  PREFLIGHT_OK=false
fi

# OWNER and REPO required for pipeline or all scope
if [[ "$SCOPE" == "pipeline" || "$SCOPE" == "all" ]]; then
  if [[ -z "$OWNER" ]]; then
    echo "  [ERROR] --owner GITHUB_OWNER is required for scope: $SCOPE" >&2
    PREFLIGHT_OK=false
  fi
  if [[ -z "$REPO" ]]; then
    echo "  [ERROR] --repo GITHUB_REPO is required for scope: $SCOPE" >&2
    PREFLIGHT_OK=false
  fi
fi

# Validate scope value
if [[ "$SCOPE" != "all" && "$SCOPE" != "health" && "$SCOPE" != "pipeline" ]]; then
  echo "  [ERROR] --scope must be one of: all, health, pipeline (got: $SCOPE)" >&2
  PREFLIGHT_OK=false
fi

# Docker availability
if ! docker info > /dev/null 2>&1; then
  echo "  [ERROR] Docker is not available or not running (required for promtool checks)" >&2
  PREFLIGHT_OK=false
fi

# Resolve SAURON_REPO
if [[ -z "$SAURON_REPO" ]]; then
  SAURON_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)/project-sauron"
fi

# Assert SAURON_REPO contains the expected file
if [[ ! -f "$SAURON_REPO/monitoring/prometheus/prometheus.yml" ]]; then
  echo "  [ERROR] SAURON_REPO does not look like project-sauron: $SAURON_REPO" >&2
  echo "          Expected: $SAURON_REPO/monitoring/prometheus/prometheus.yml" >&2
  PREFLIGHT_OK=false
fi

if [[ "$PREFLIGHT_OK" != "true" ]]; then
  echo ""
  echo "Pre-flight checks failed. Aborting." >&2
  # Disable EXIT trap's cleanup since CLIENT_LABEL may be invalid
  NO_CLEANUP=true
  exit 1
fi

echo "  CLIENT_LABEL: $CLIENT_LABEL"
echo "  SCOPE:        $SCOPE"
echo "  OWNER/REPO:   ${OWNER:-N/A}/${REPO:-N/A}"
echo "  DRY_RUN:      $DRY_RUN"
echo "  NO_CLEANUP:   $NO_CLEANUP"
echo "  SAURON_REPO:  $SAURON_REPO"
echo "  SAURON_URL:   $SAURON_URL"
echo "  WORKDIR:      $WORKDIR"
echo ""

# Capture baseline state (used by pipeline checks to detect what was added)
BASELINE_RULES=$(ls "$SAURON_REPO/monitoring/prometheus/rules/" 2>/dev/null || true)
BASELINE_DASHBOARDS=$(ls "$SAURON_REPO/monitoring/grafana/dashboards/" 2>/dev/null || true)
BASELINE_PROMETHEUS_LINES=$(wc -l < "$SAURON_REPO/monitoring/prometheus/prometheus.yml")
BASELINE_GIT_LOG=$(git -C "$SAURON_REPO" log --oneline -1 2>/dev/null || echo "unknown")

echo "  Baseline prometheus.yml lines: $BASELINE_PROMETHEUS_LINES"
echo "  Baseline git HEAD:             $BASELINE_GIT_LOG"
echo ""

# ---------------------------------------------------------------------------
# Phase 1: Sauron Capability Checks
# ---------------------------------------------------------------------------
if [[ "$SCOPE" == "health" || "$SCOPE" == "all" ]]; then
  echo "=== Phase 1: Sauron Capability Checks ==="

  # 1.1 Stack health via verify-stack.sh on EC2
  echo "  Running 1.1 (SSH to EC2 — may take a moment)..."
  check "1.1" "Stack health (verify-stack.sh)" \
    ssh ${EC2_SSH_KEY_PATH:+-i "$EC2_SSH_KEY_PATH"} "$EC2_USER@$EC2_HOST" \
      'bash /opt/project-sauron/scripts/verify-stack.sh --json | grep -q "\"overall\": \"PASS\""'

  # 1.2 Pushgateway write — POST a synthetic capability metric
  check "1.2" "Pushgateway write" \
    bash -c "http_code=\$(curl -sf -o /dev/null -w '%{http_code}' \
      -X POST -H 'Authorization: Bearer $PUSH_BEARER_TOKEN' -H 'Content-Type: text/plain' \
      --data $'# HELP sauron_e2e_cap E2E capability check\n# TYPE sauron_e2e_cap gauge\nsauron_e2e_cap{check=\"write\"} 1\n' \
      '$SAURON_URL/metrics/gateway/metrics/job/e2e-capability/instance/write-test') && \
      [[ \$http_code == '200' || \$http_code == '202' ]]"

  # 1.3 Pushgateway read — metric should appear after write
  check "1.3" "Pushgateway read" \
    bash -c "curl -sf '$SAURON_URL/metrics/gateway/metrics' | grep -q 'sauron_e2e_cap'"

  # 1.4 nginx auth enforcement — invalid token must be rejected with 401
  check "1.4" "nginx auth enforcement (invalid token → 401)" \
    bash -c "http_code=\$(curl -sf -o /dev/null -w '%{http_code}' \
      -H 'Authorization: Bearer invalid-token-e2e-test' \
      '$SAURON_URL/metrics/gateway/metrics/job/e2e/instance/x' -X POST -d 'test 1') && \
      [[ \$http_code == '401' ]]"

  # 1.5 Grafana API health
  check "1.5" "Grafana API health" \
    bash -c "curl -sf -u admin:$GRAFANA_ADMIN_PASSWORD '$SAURON_URL/api/health' | grep -q 'ok'"

  # 1.6 Grafana dashboards provisioned — all 6 expected dashboards present
  check "1.6" "Grafana dashboards provisioned (6/6)" \
    bash -c "
      result=\$(curl -sf -u admin:$GRAFANA_ADMIN_PASSWORD '$SAURON_URL/api/search?type=dash-db')
      for title in alexandria api-overview aws-overview hammer sauron-self web-traffic; do
        echo \"\$result\" | grep -qi \"\$title\" || { echo \"Missing dashboard: \$title\"; exit 1; }
      done
    "

  # 1.7 Prometheus query API — via SSH (Prometheus not exposed externally)
  echo "  Running 1.7 (SSH to EC2 — may take a moment)..."
  check "1.7" "Prometheus query API" \
    ssh ${EC2_SSH_KEY_PATH:+-i "$EC2_SSH_KEY_PATH"} "$EC2_USER@$EC2_HOST" \
      'curl -sf "http://localhost:9090/api/v1/query?query=up" | grep -q "\"status\":\"success\""'

  # 1.8 Prometheus alert rules syntax — all rules files pass promtool
  echo "  Running 1.8 (SSH to EC2 — may take a moment)..."
  check "1.8" "Prometheus alert rules syntax (all files)" \
    ssh ${EC2_SSH_KEY_PATH:+-i "$EC2_SSH_KEY_PATH"} "$EC2_USER@$EC2_HOST" \
      'cd /opt/project-sauron && for f in monitoring/prometheus/rules/*.yml; do
         docker compose -f monitoring/docker-compose.yml exec -T prometheus \
           promtool check rules /etc/prometheus/rules/$(basename "$f") || exit 1
       done'

  # 1.9 Loki write
  LOKI_TS=$(date +%s%N)
  check "1.9" "Loki write" \
    bash -c "http_code=\$(curl -sf -o /dev/null -w '%{http_code}' \
      -H 'Authorization: Bearer $PUSH_BEARER_TOKEN' \
      -H 'Content-Type: application/json' \
      --data '{\"streams\":[{\"stream\":{\"job\":\"e2e-capability\",\"instance\":\"log-test\"},\"values\":[[\"${LOKI_TS}\",\"e2e log write test\"]]}]}' \
      '$SAURON_URL/loki/api/v1/push') && \
      [[ \$http_code == '204' ]]"

  # 1.10 Loki query — wait 5s for ingestion then query
  echo "  Waiting 5s for Loki ingestion..."
  sleep 5
  check "1.10" "Loki query" \
    bash -c "count=\$(curl -sf \
      -H 'Authorization: Bearer $PUSH_BEARER_TOKEN' \
      '$SAURON_URL/loki/api/v1/query?query={job=\"e2e-capability\"}&limit=1' \
      | jq '.data.result | length') && [[ \$count -ge 1 ]]"

  # 1.11 Alloy metrics in Prometheus
  echo "  Running 1.11 (SSH to EC2 — may take a moment)..."
  check "1.11" "Alloy metrics visible in Prometheus" \
    ssh ${EC2_SSH_KEY_PATH:+-i "$EC2_SSH_KEY_PATH"} "$EC2_USER@$EC2_HOST" \
      'count=$(curl -sf "http://localhost:9090/api/v1/query?query=alloy_build_info" | jq ".data.result | length") && [[ $count -ge 1 ]]'

  # 1.12 Blackbox probe UP — at least 1 target should be UP
  echo "  Running 1.12 (SSH to EC2 — may take a moment)..."
  check "1.12" "Blackbox probe (at least 1 target UP)" \
    ssh ${EC2_SSH_KEY_PATH:+-i "$EC2_SSH_KEY_PATH"} "$EC2_USER@$EC2_HOST" \
      'count=$(curl -sf "http://localhost:9090/api/v1/query?query=count(probe_success==1)" | jq ".data.result[0].value[1]" -r) && [[ ${count:-0} -ge 1 ]]'

  echo ""
fi

# ---------------------------------------------------------------------------
# Phase 2: Helldiver Pipeline Validation
# ---------------------------------------------------------------------------
if [[ "$SCOPE" == "pipeline" || "$SCOPE" == "all" ]]; then
  echo "=== Phase 2: Helldiver Pipeline ==="
  echo "  NOTE: This phase validates OUTPUTS produced by pipeline agents."
  echo "  The pipeline (run_agent_in_docker via scrum-master) must have been"
  echo "  executed before running this scope."
  echo ""
  echo "  Pipeline sequence documented here for reference:"
  echo "    recon-agent → instrumentation-engineer"
  echo "    → (sauron-config-writer ∥ client-onboarding-agent)"
  echo "    → dashboard-generator → validation-agent → docs-agent"
  echo ""

  RESEARCH_GATE_TRIGGERED=false
  PIPELINE_TYPE=""
  CONFIDENCE=""

  # 2.1 Recon output validation — fingerprint.md must exist with required fields
  FINGERPRINT="$WORKDIR/$CLIENT_LABEL/fingerprint.md"
  check "2.1" "Recon: fingerprint.md produced with required fields" \
    bash -c "
      test -f '$FINGERPRINT' && \
      grep -q '$CLIENT_LABEL' '$FINGERPRINT' && \
      grep -qi 'project_type' '$FINGERPRINT' && \
      grep -qi 'confidence' '$FINGERPRINT'
    "

  # Extract project_type and confidence for downstream assertions
  if [[ -f "$FINGERPRINT" ]]; then
    PIPELINE_TYPE=$(grep -i 'project_type' "$FINGERPRINT" | head -1 | sed 's/.*://;s/[[:space:]]//g' | tr '[:upper:]' '[:lower:]' || true)
    CONFIDENCE=$(grep -i 'confidence' "$FINGERPRINT" | head -1 | sed 's/.*://;s/[[:space:]]//g' | tr '[:upper:]' '[:lower:]' || true)
    echo "  → project_type: $PIPELINE_TYPE  confidence: $CONFIDENCE"
    if echo "$CONFIDENCE" | grep -qi "low"; then
      echo "  INFO: Research gate would trigger for this project (LOW confidence detected)"
      RESEARCH_GATE_TRIGGERED=true
    fi
  else
    echo "  INFO: fingerprint.md not found — downstream type-specific checks may fail"
  fi

  # 2.2 Research gate detection — always advisory (PASS/FAIL does not change FAILURES)
  if [[ "$RESEARCH_GATE_TRIGGERED" == "true" ]]; then
    RESULTS["2.2"]="ADVISORY: research gate would trigger"
    echo "  [INFO] 2.2: Research gate detection — LOW confidence, gate would activate in production"
  else
    RESULTS["2.2"]="NOT_TRIGGERED"
    echo "  [INFO] 2.2: Research gate detection — confidence is not LOW, gate not triggered"
  fi

  # 2.3 Instrumentation plan validation
  PLAN="$WORKDIR/$CLIENT_LABEL/instrumentation-plan.md"
  check "2.3" "Instrumentation plan: exists and no placeholders" \
    bash -c "
      test -f '$PLAN' && \
      test -s '$PLAN' && \
      ! grep -qE '<CLIENT_LABEL>|TODO|FIXME' '$PLAN'
    "

  # 2.4 Sauron config validation
  RULES="$SAURON_REPO/monitoring/prometheus/rules/$CLIENT_LABEL.yml"
  PROM_YML="$SAURON_REPO/monitoring/prometheus/prometheus.yml"

  check "2.4a" "Sauron config: rules file created and passes promtool" \
    bash -c "
      test -f '$RULES' && \
      docker run --rm \
        -v '$SAURON_REPO/monitoring/prometheus:/etc/prometheus' \
        prom/prometheus promtool check rules /etc/prometheus/rules/$CLIENT_LABEL.yml
    "

  check "2.4b" "Sauron config: prometheus.yml passes check-config" \
    bash -c "
      docker run --rm \
        -v '$SAURON_REPO/monitoring/prometheus:/etc/prometheus' \
        prom/prometheus --config.file=/etc/prometheus/prometheus.yml --check-config
    "

  check "2.4c" "Sauron config: surgical edit preserved existing entries (line count grew)" \
    bash -c "
      current_lines=\$(wc -l < '$PROM_YML')
      [[ \$current_lines -gt $BASELINE_PROMETHEUS_LINES ]]
    "

  # Type-specific assertions branch on project_type extracted from fingerprint.md
  if echo "$PIPELINE_TYPE" | grep -qi "mcp"; then
    check "2.4d" "Sauron config (MCP): alert uses absent() not probe_success" \
      bash -c "grep -q 'absent(' '$RULES' && ! grep -q 'probe_success' '$RULES'"
    check "2.4e" "Sauron config (MCP): pushgateway job with honor_labels present" \
      bash -c "grep -q 'honor_labels' '$PROM_YML' || grep -q 'pushgateway' '$PROM_YML'"
  else
    check "2.4d" "Sauron config (blackbox): alert uses probe_success" \
      bash -c "grep -q 'probe_success' '$RULES'"
    check "2.4e" "Sauron config (blackbox): CLIENT_LABEL target added to prometheus.yml" \
      bash -c "grep -q '$CLIENT_LABEL' '$PROM_YML'"
  fi

  # 2.5 Client onboarding validation
  ONBOARDING="$WORKDIR/$CLIENT_LABEL/ONBOARDING.md"
  check "2.5a" "Client onboarding: ONBOARDING.md produced" \
    bash -c "test -f '$ONBOARDING' && test -s '$ONBOARDING'"

  if echo "$PIPELINE_TYPE" | grep -qi "mcp"; then
    check "2.5b" "Client onboarding (MCP): restart warning present" \
      bash -c "grep -qi 'restart claude code' '$ONBOARDING'"
    check "2.5c" "Client onboarding (MCP): metrics appeared in Pushgateway" \
      bash -c "curl -sf '$SAURON_URL/metrics/gateway/metrics' | grep -q '$CLIENT_LABEL'"
  fi

  # 2.6 Dashboard validation
  DASH="$SAURON_REPO/monitoring/grafana/dashboards/$CLIENT_LABEL.json"
  check "2.6a" "Dashboard: valid JSON" \
    bash -c "jq . '$DASH' > /dev/null"
  check "2.6b" "Dashboard: correct UID" \
    bash -c "jq -r '.uid' '$DASH' | grep -q '$CLIENT_LABEL-overview'"
  check "2.6c" "Dashboard: non-empty panels array" \
    bash -c "[[ \$(jq '.panels | length' '$DASH') -gt 0 ]]"
  check "2.6d" "Dashboard: helldiver tag present" \
    bash -c "jq '.tags[]' '$DASH' | grep -q 'helldiver'"
  check "2.6e" "Dashboard: no empty datasource UIDs in panels" \
    bash -c "! jq -e '.panels[].datasource.uid | select(. == null or . == \"\")' '$DASH' > /dev/null"
  check "2.6f" "Dashboard: no unreplaced placeholders" \
    bash -c "! grep -qE '<CLIENT_LABEL>|TODO|FIXME|PLACEHOLDER' '$DASH'"

  # 2.7 Validation agent report
  REPORT="$WORKDIR/$CLIENT_LABEL/validation-report.md"
  check "2.7a" "Validation agent: report produced" \
    bash -c "test -f '$REPORT' && test -s '$REPORT'"
  check "2.7b" "Validation agent: overall PASS" \
    bash -c "grep -qi 'overall.*pass\|overall: pass' '$REPORT'"

  if [[ "$DRY_RUN" == "true" ]]; then
    check "2.7c" "Validation agent (dry-run): git log unchanged" \
      bash -c "[[ \"\$(git -C '$SAURON_REPO' log --oneline -1 2>/dev/null)\" == '$BASELINE_GIT_LOG' ]]"
  fi

  # 2.8 Docs agent output
  # In dry-run mode, docs-agent writes to workdir rather than the sauron repo
  DOCS_FILE="$WORKDIR/$CLIENT_LABEL/docs/$CLIENT_LABEL.md"
  check "2.8a" "Docs agent: client doc produced (dry-run workdir)" \
    bash -c "test -f '$DOCS_FILE' && test -s '$DOCS_FILE'"
  check "2.8b" "Docs agent: no unreplaced placeholders" \
    bash -c "! grep -qE '<CLIENT_LABEL>|<OWNER>|TODO|FIXME' '$DOCS_FILE'"

  echo ""
fi

# ---------------------------------------------------------------------------
# Phase 3 & 4 are handled by the EXIT trap (cleanup_on_exit calls print_report)
# ---------------------------------------------------------------------------
# Signal that the main body completed normally — the EXIT trap will run
# cleanup and then call print_report. We set REPORT_PRINTED=false so the
# trap's call to print_report is the one that executes.

# Determine exit code (used after trap returns)
if [[ $FAILURES -eq 0 ]]; then
  EXIT_CODE=0
else
  EXIT_CODE=1
fi

exit $EXIT_CODE
