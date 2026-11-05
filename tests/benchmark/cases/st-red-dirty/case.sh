KIND=fault
BLOCK_RC=2   # Stop hooks block only on exit 2; exit 1 is a non-blocking error
DESC="red checks with uncommitted changes: the session must not be allowed to finish"
setup() { echo 'exit 1' > t.sh; }
act()   { printf '%s' '{"stop_hook_active":false}' | sh .slickrails/session-check.sh; }
