#!/usr/bin/env bash
# RED contract test — eliza vault-01 env-var-endpoints sprint.
#
# Self-contained and offline: PATH-stubbed redis-cli (plus psql/pg_isready/docker/nc
# for completeness — the current pins exercise only redis-cli). Each stub logs its
# argv to a log file and exits 0. No network, no real docker, no redis, no postgres.
#
# Pins (source of truth: di-meta coordination/sprint-eliza-env-var-endpoints-brief.md,
# "RED Contract" section; pin numbering matches the brief):
#   P1  syntax                bash -n update_and_run.sh passes
#   P2  no-unguarded-hardcode (a) no localhost:5432 token outside a ${VAR:-...} default
#                               (b) no bare redis-cli invocation outside the rc() definition line
#   P3  rc() override         the script's rc() honors REDIS_HOST/REDIS_PORT (stub argv check)
#   P4  rc() default          the script's rc() with no env hits localhost:6379 (stub argv check)
#   P5  POSTGRES_URL override the export line evaluates to the PG_DSN value when PG_DSN is set
#   P6  POSTGRES_URL default  the export line uses the ${PG_DSN:-...} form and, with no env,
#                             evaluates to the current hard-coded local DSN
#
# RED at base (pre-sprint file): P1 passes; P2-P6 fail.
# After implementation: all six pins pass.
#
# Run: bash scripts/__tests__/env-var-endpoints.sh
# Exit: 0 only if every pin passes.

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/update_and_run.sh"

EXPECTED_LOCAL_DSN="postgresql://postgres:postgres_dev_pass@localhost:5432/di_memory"
FAKE_DSN="postgres://u:p@FAKEHOST:5433/di_memory"

STUBDIR="$(mktemp -d "${TMPDIR:-/tmp}/envvar-stub.XXXXXX")"
trap 'rm -rf "$STUBDIR"' EXIT
STUB_LOG="$STUBDIR/stub.log"
for tool in redis-cli psql pg_isready docker nc; do
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "echo \"\$0 \$@\" >> \"$STUB_LOG\""
    printf '%s\n' 'exit 0'
  } > "$STUBDIR/$tool"
  chmod +x "$STUBDIR/$tool"
done

PASS_COUNT=0
FAIL_COUNT=0
RESULTS=""

record() {
  # record <id> <name> <ok:0|1> [detail]
  local id="$1" name="$2" ok="$3" detail="${4-}"
  if [ "$ok" = "1" ]; then
    RESULTS="${RESULTS}PASS  ${id}  ${name}"$'\n'
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    RESULTS="${RESULTS}FAIL  ${id}  ${name}${detail:+ — ${detail}}"$'\n'
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: $SCRIPT not found (repo root: $ROOT)"
  echo "The sprint in-scope file must exist at the worktree root (see red-report.md)."
  exit 1
fi

# --- P1: syntax ---
P1_ERR="$STUBDIR/p1.err"
if bash -n "$SCRIPT" 2>"$P1_ERR"; then
  record "P1" "syntax: bash -n update_and_run.sh" 1
else
  record "P1" "syntax: bash -n update_and_run.sh" 0 "$(head -n 1 "$P1_ERR" 2>/dev/null || true)"
fi

# --- P2: no unguarded hardcode (1 pin, 2 sub-checks) ---
# sub a: every line containing localhost:5432 must also carry a ${VAR:-...} default
# sub b: every line containing redis-cli must be the rc() definition line
P2A_BAD="$(grep -n 'localhost:5432' "$SCRIPT" | grep -Ev '\$\{[A-Za-z_][A-Za-z_0-9]*:-' || true)"
P2B_BAD="$(grep -n 'redis-cli' "$SCRIPT" | grep -Ev '^[0-9]+:[[:space:]]*rc[[:space:]]*\(\)' || true)"
P2_OK=1
P2_DETAIL=""
if [ -n "$P2A_BAD" ]; then
  P2_OK=0
  P2_DETAIL="sub a: unguarded localhost:5432 line(s): $(printf '%s' "$P2A_BAD" | head -n 3 | cut -d: -f1 | tr '\n' ' ')"
fi
if [ -n "$P2B_BAD" ]; then
  P2_OK=0
  P2_DETAIL="${P2_DETAIL}${P2_DETAIL:+; }sub b: bare redis-cli line(s): $(printf '%s' "$P2B_BAD" | head -n 3 | cut -d: -f1 | tr '\n' ' ')"
fi
record "P2" "no-unguarded-hardcode (localhost:5432 guarded; no bare redis-cli)" "$P2_OK" "$P2_DETAIL"

# --- Extract the script's rc() definition (empty at base; pins P3/P4 run it) ---
extract_rc() {
  awk '
    !started && /^[[:space:]]*rc[[:space:]]*\(\)[[:space:]]*\{/ { started = 1 }
    started {
      depth += gsub(/\{/, "{")
      depth -= gsub(/\}/, "}")
      print
      if (depth <= 0) exit
    }
  ' "$SCRIPT"
}
RC_DEF="$(extract_rc)"

invoke_rc() {
  # invoke_rc <logfile> <default|override>
  # Eval the script's rc() in a subshell with the stubbed PATH, then call: rc PING.
  # The stub appends its argv to <logfile>.
  local log="$1" mode="$2"
  : > "$log"
  (
    export PATH="$STUBDIR:$PATH"
    unset REDIS_HOST REDIS_PORT
    if [ "$mode" = "override" ]; then
      export REDIS_HOST=FAKEHOST REDIS_PORT=7000
    fi
    if [ -n "$RC_DEF" ]; then
      eval "$RC_DEF"
    fi
    rc PING >/dev/null 2>&1 || true
  )
  return 0
}

# --- P3: rc() override (stub-based) ---
invoke_rc "$STUB_LOG" "override"
if grep -q -- '-h FAKEHOST -p 7000' "$STUB_LOG" 2>/dev/null; then
  record "P3" "rc() override: stub log contains -h FAKEHOST -p 7000" 1
elif [ -z "$RC_DEF" ]; then
  record "P3" "rc() override: stub log contains -h FAKEHOST -p 7000" 0 "rc() definition not found in update_and_run.sh"
else
  record "P3" "rc() override: stub log contains -h FAKEHOST -p 7000" 0 "rc ran but stub log lacks -h FAKEHOST -p 7000 (got: $(head -n 1 "$STUB_LOG" 2>/dev/null || true))"
fi

# --- P4: rc() default (stub-based) ---
invoke_rc "$STUB_LOG" "default"
if grep -q -- '-h localhost -p 6379' "$STUB_LOG" 2>/dev/null; then
  record "P4" "rc() default: stub log contains -h localhost -p 6379" 1
elif [ -z "$RC_DEF" ]; then
  record "P4" "rc() default: stub log contains -h localhost -p 6379" 0 "rc() definition not found in update_and_run.sh"
else
  record "P4" "rc() default: stub log contains -h localhost -p 6379" 0 "rc ran but stub log lacks -h localhost -p 6379 (got: $(head -n 1 "$STUB_LOG" 2>/dev/null || true))"
fi

# --- P5/P6: POSTGRES_URL export line ---
PG_LINE="$(grep -E '^[[:space:]]*export[[:space:]]+POSTGRES_URL=' "$SCRIPT" | head -n 1 || true)"

P5_GOT=""
if [ -n "$PG_LINE" ]; then
  P5_GOT="$(PG_DSN="$FAKE_DSN" bash -c 'eval "$1"; printf "%s" "$POSTGRES_URL"' _ "$PG_LINE" 2>/dev/null || true)"
fi
if [ "$P5_GOT" = "$FAKE_DSN" ]; then
  record "P5" "POSTGRES_URL: PG_DSN wins when set" 1
elif [ -z "$PG_LINE" ]; then
  record "P5" "POSTGRES_URL: PG_DSN wins when set" 0 "no export POSTGRES_URL line found"
else
  record "P5" "POSTGRES_URL: PG_DSN wins when set" 0 "evaluated to: ${P5_GOT:-<empty>}"
fi

P6_OK=1
P6_DETAIL=""
if [ -z "$PG_LINE" ] || ! printf '%s\n' "$PG_LINE" | grep -qF -- '${PG_DSN:-'; then
  P6_OK=0
  P6_DETAIL="export line missing or does not use the \${PG_DSN:-...} default form"
fi
P6_GOT=""
if [ -n "$PG_LINE" ]; then
  P6_GOT="$(bash -c 'unset PG_DSN; eval "$1"; printf "%s" "$POSTGRES_URL"' _ "$PG_LINE" 2>/dev/null || true)"
fi
if [ "$P6_GOT" != "$EXPECTED_LOCAL_DSN" ]; then
  P6_OK=0
  P6_DETAIL="${P6_DETAIL}${P6_DETAIL:+; }no-env eval gave: ${P6_GOT:-<empty>} (want: $EXPECTED_LOCAL_DSN)"
fi
record "P6" "POSTGRES_URL default: no env = current hard-coded local DSN" "$P6_OK" "$P6_DETAIL"

# --- Summary ---
echo "=== env-var-endpoints pins (eliza update_and_run.sh) ==="
printf '%s' "$RESULTS"
echo "-------------------------------------------------------"
echo "pins: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "RESULT: GREEN"
  exit 0
else
  echo "RESULT: RED (${FAIL_COUNT} pin(s) failing)"
  exit 1
fi
