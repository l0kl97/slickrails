KIND=fault
DESC="plainly red tests must block the push"
setup() { echo 'exit 1' > t.sh; git add t.sh; git commit -q --no-verify -m "red"; }
act()   { git push -q origin main; }
