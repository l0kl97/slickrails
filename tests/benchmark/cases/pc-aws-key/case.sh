KIND=fault
NEEDS_NO_GITLEAKS=1
DESC="AWS access key id in the diff (regex fallback)"
# assembled from parts so this file never matches the scanner itself
setup() { printf 'aws_key = "%s%s"\n' "AKIA" "IOSFODNN7EXAMPLE" > deploy.js; git add deploy.js; }
act()   { bench_commit "add deploy"; }
