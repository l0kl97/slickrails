KIND=control
DESC="an ordinary Bash call (git status) passes the installed PreToolUse guard"
# Counterpart of agent-no-verify: a guard that blocks every Bash call fails here.
setup() { sh "$KIT_DIR/install.sh" >/dev/null 2>&1; }
act() {
  printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status && git log --oneline -3"}}' \
    | sh .slickrails/bash-guard.sh
}
