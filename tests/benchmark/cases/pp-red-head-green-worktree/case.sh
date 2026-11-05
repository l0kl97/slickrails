KIND=fault
DESC="HEAD is red, the uncommitted working copy is green: push must be blocked"
setup() { echo 'exit 1' > t.sh; git add t.sh; git commit -q --no-verify -m "red"; echo 'exit 0' > t.sh; }
act()   { git push -q origin main; }
