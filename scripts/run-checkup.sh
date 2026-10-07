#!/usr/bin/env bash
# DSH Harness Checkup - composite action runner
# Route: npm @deepseek-ai/dsh, version supplied by the `dsh-version` input (env DSH_VERSION) -
# the default pin lives in action.yml, so this script carries no version literal.
# Verified on ubuntu-latest by the T5.0 probe (run 36880871917); @deepseek-ai/dsh-headless
# 0.0.1-rc.1 is NOT installable (unpublished dep dsh-code-runtime-worker, npm 404).
set -euo pipefail

DSH_VERSION="${DSH_VERSION:-}"
if [ -z "$DSH_VERSION" ]; then
  echo "::error::DSH_VERSION is empty. It comes from the action input dsh-version (see action.yml)."
  exit 1
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "::error::DEEPSEEK_API_KEY is not set. Add it as a secret in the caller repo and pass it via job-level env."
  exit 1
fi

DIFF_BYTES="${DIFF_BYTES:-50000}"
RUN_DIR="${RUNNER_TEMP:?RUNNER_TEMP is not set}/dsh-action-run"
mkdir -p "$RUN_DIR"
OUT="${GITHUB_OUTPUT:-/dev/null}"

# --- outputs (see action.yml `outputs:`; composite requires steps.<id>.outputs -> outputs.value) ---
write_output() { printf '%s=%s\n' "$1" "$2" >> "$OUT"; }
write_output_multiline() {
  local name="$1" file="$2"
  if [ -s "$file" ]; then
    { printf '%s<<%s\n' "$name" 'DSH_REPORT_EOF'; cat "$file"; printf '\n%s\n' 'DSH_REPORT_EOF'; } >> "$OUT"
  else
    printf '%s=\n' "$name" >> "$OUT"
  fi
}

echo "::group::Install DSH CLI (npm @deepseek-ai/dsh@$DSH_VERSION)"
if [ ! -d "$RUN_DIR/node_modules/@deepseek-ai/dsh" ]; then
  cd "$RUN_DIR"
  npm init -y >/dev/null
  npm install "@deepseek-ai/dsh@$DSH_VERSION" --no-audit --no-fund
else
  echo "cached"
fi
INSTALLED_VERSION="$(node -p "require('$RUN_DIR/node_modules/@deepseek-ai/dsh/package.json').version" 2>/dev/null || echo unknown)"
echo "installed @deepseek-ai/dsh@$INSTALLED_VERSION"
echo "::endgroup::"

# Diff of the latest commit (needs checkout with fetch-depth >= 2).
cd "$GITHUB_WORKSPACE"
if git rev-parse HEAD~1 >/dev/null 2>&1; then
  git diff HEAD~1 HEAD > "$RUN_DIR/checkup.diff"
else
  echo "(仓库首个提交,无前驱可比对;体检基于当前全量状态)" > "$RUN_DIR/checkup.diff"
fi
# Truncate for prompt safety
head -c "$DIFF_BYTES" "$RUN_DIR/checkup.diff" > "$RUN_DIR/checkup.trunc" || true
if [ "$(wc -c < "$RUN_DIR/checkup.diff")" -gt "$DIFF_BYTES" ]; then
  printf '\n... (diff 超过 %s 字节,已截断;可自行在仓库中查证完整改动)\n' "$DIFF_BYTES" >> "$RUN_DIR/checkup.trunc"
fi

PROMPT="$(cat "$GITHUB_ACTION_PATH/scripts/prompt.txt")"
if [ -n "${EXTRA_TASK:-}" ]; then
  PROMPT="$PROMPT

补充任务要求:
$EXTRA_TASK"
fi
PROMPT="$PROMPT

--- 本次提交的 diff(可能截断) ---
$(cat "$RUN_DIR/checkup.trunc")"

echo "::group::Run dsh headless (report generation)"
cd "$GITHUB_WORKSPACE"
set +e
timeout 480 "$RUN_DIR/node_modules/.bin/dsh" headless "$PROMPT" \
  > "$RUN_DIR/report.out" 2> "$RUN_DIR/report.err"
RC=$?
set -e
echo "headless exit code: $RC"
echo "::endgroup::"

{
  echo "# DSH 五维体检报告"
  echo ""
  if [ -s "$RUN_DIR/report.out" ]; then
    cat "$RUN_DIR/report.out"
  else
    echo "_headless 未产出报告(exit=$RC),stderr 如下:_"
  fi
  if [ -s "$RUN_DIR/report.err" ]; then
    echo ""
    echo "<details><summary>headless stderr</summary>"
    echo ""
    echo '```'
    cat "$RUN_DIR/report.err"
    echo '```'
    echo "</details>"
  fi
} >> "$GITHUB_STEP_SUMMARY"

# v1.1: also echo the report into the step log (permanent, API-readable audit copy)
echo "::group::五维体检报告(日志副本,与 step summary 相同)"
cat "$RUN_DIR/report.out"
echo "::endgroup::"

# ---- publish outputs on BOTH the success and the failure path (AC-A4-1 / AC-A4-5) ----
write_output exit_code "$RC"
write_output_multiline report_text "$RUN_DIR/report.out"
if [ -s "$RUN_DIR/report.out" ]; then
  write_output report_file "$RUN_DIR/report.out"
  write_output error ""
else
  write_output report_file ""
  write_output error "dsh headless failed (exit=$RC) and produced no report; see stderr in the step summary"
fi

if [ "$RC" -ne 0 ] && [ ! -s "$RUN_DIR/report.out" ]; then
  echo "::error::dsh headless failed (exit=$RC) and produced no report. See stderr in the step summary."
  exit 1
fi
