KIND=control
DESC="nothing changed: question-only sessions finish immediately"
setup() { :; }
act()   { printf '%s' '{"stop_hook_active":false}' | sh .slickrails/session-check.sh; }
