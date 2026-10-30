#!/usr/bin/env bash
# Monitor script for the "Ledger inbox" cron job.
#
# Cron runs this each tick BEFORE the agent; identical bytes suppress the agent
# run entirely, so the agent only wakes when @USER@ has actually written something
# new. That is why the output must be his lines verbatim and nothing else — no
# timestamps of "now", no counts that drift on their own.
set -u
grep '^- \[?\] ' "$HOME/.hermes/ledger.md" 2>/dev/null || true
exit 0
