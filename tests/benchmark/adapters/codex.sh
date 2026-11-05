#!/bin/sh
# slickrails benchmark — Codex REVIEW layer (L3). Exit 77 = BLOCKED (never counted as caught, missed or green).
# What exists for Codex: the session hooks (Stop gate, Bash guard), checked against the real CLI by
# tests/benchmark/host/codex-gate.sh. What does NOT exist: a Codex review backend for the pre-push review
# (decision E2: cross-review is an option, not built), so there is nothing for this layer to measure yet.

if ! command -v codex >/dev/null 2>&1 && [ ! -x "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex" ]; then
  echo "L3 codex review: BLOCKED — codex CLI not found (the session-hook check is separate: tests/benchmark/host/codex-gate.sh)"
  exit 77
fi
echo "L3 codex review: BLOCKED — the kit ships no Codex review backend (the session-hook check is separate: tests/benchmark/host/codex-gate.sh)"
exit 77
