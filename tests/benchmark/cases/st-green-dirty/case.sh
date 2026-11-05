KIND=control
DESC="uncommitted but green: the session may finish"
setup() { echo 'echo changed' >> t.sh; }
act()   { printf '%s' '{"stop_hook_active":false}' | sh .slickrails/session-check.sh; }
