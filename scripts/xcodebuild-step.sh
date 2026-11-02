#!/usr/bin/env bash
# Runs xcodebuild with full output saved to a log file, prints only the useful
# lines (errors, test results), and shows the end of the log on failure.
# Usage: xcodebuild-step.sh <logfile> <xcodebuild args...>
set -uo pipefail
log="$1"; shift
# Progress as it happens (a test that hangs shows as the last one started).
xcodebuild "$@" 2>&1 | tee "$log" | grep --line-buffered -E "error:|Test Case .* (started|passed|failed)|\*\* (BUILD|TEST|TEST BUILD|TEST EXECUTE)"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  echo "---- last 80 lines of $log ----"
  tail -n 80 "$log"
fi
exit $status
