KIND=fault
BLOCK_RC=2   # a PreToolUse hook blocks the tool call only on exit 2
DESC="an agent's Bash call 'git commit --no-verify' must be stopped by the installed PreToolUse guard"
setup() { sh "$KIT_DIR/install.sh" >/dev/null 2>&1; }
act() {
  printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m wip"}}' \
    | sh .slickrails/bash-guard.sh
}
