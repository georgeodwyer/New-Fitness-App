#!/usr/bin/env bash
# Runs xcodebuild with full output saved to a log file, prints only the useful
# lines (errors, test results), and shows the end of the log on failure.
# Usage: xcodebuild-step.sh <logfile> <xcodebuild args...>
set -uo pipefail
log="$1"; shift
xcodebuild "$@" > "$log" 2>&1
status=$?
grep -E "error:|Test Case .* (passed|failed)|\*\* (BUILD|TEST|TEST BUILD|TEST EXECUTE)" "$log" || true
if [ "$status" -ne 0 ]; then
  echo "---- last 80 lines of $log ----"
  tail -n 80 "$log"
fi
exit $status
