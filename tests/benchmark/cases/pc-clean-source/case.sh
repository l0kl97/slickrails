KIND=control
DESC="ordinary source change must pass"
setup() { printf 'export const add = (a, b) => a + b;\n' > add.js; git add add.js; }
act()   { bench_commit "add helper"; }
