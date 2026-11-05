KIND=control
DESC="green HEAD, clean tree: push passes"
setup() { echo '# change' >> t.sh; git add t.sh; git commit -q --no-verify -m "green"; }
act()   { git push -q origin main; }
