KIND=fault
BLOCK_RC=2   # Stop hooks block only on exit 2; exit 1 is a non-blocking error
DESC="red change already committed, tree clean: the session must still not be allowed to finish"
setup() { echo 'exit 1' > t.sh; git add t.sh; git commit -q --no-verify -m "red"; }
act()   { printf '%s' '{"stop_hook_active":false}' | sh .slickrails/session-check.sh; }
