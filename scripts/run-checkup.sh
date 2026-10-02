#!/usr/bin/env bash
# DSH Harness Checkup - composite action runner (v1)
# Route: npm @deepseek-ai/dsh@0.2.0-rc.2 (verified on ubuntu-latest by T5.0 probe v2,
# run 36880871917; dsh-headless@0.0.1-rc.1 is NOT installable - unpublished dep).
set -euo pipefail

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "::error::DEEPSEEK_API_KEY is not set. Add it as a secret in the caller repo and pass it via job-level env."
  exit 1
fi

DIFF_BYTES="${DIFF_BYTES:-50000}"
RUN_DIR="$RUNNER_TEMP/dsh-action-run"
mkdir -p "$RUN_DIR"

echo "::group::Install DSH CLI (npm @deepseek-ai/dsh@0.2.0-rc.2)"
if [ ! -d "$RUN_DIR/node_modules/@deepseek-ai/dsh" ]; then
  cd "$RUN_DIR"
  npm init -y >/dev/null
  npm install @deepseek-ai/dsh@0.2.0-rc.2 --no-audit --no-fund
else
  echo "cached"
fi
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

if [ "$RC" -ne 0 ] && [ ! -s "$RUN_DIR/report.out" ]; then
  echo "::error::dsh headless failed (exit=$RC) and produced no report. See stderr in the step summary."
  exit 1
fi
