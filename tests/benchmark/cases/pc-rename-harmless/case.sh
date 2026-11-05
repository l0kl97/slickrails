KIND=control
DESC="renaming an ordinary file must pass"
setup() { echo hi > a.txt; git add a.txt; git commit -q --no-verify -m "a"; git mv a.txt b.txt; }
act()   { bench_commit "rename a to b"; }
