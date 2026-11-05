KIND=fault
NEEDS_NO_GITLEAKS=1
DESC="generic hex api_key assignment (not covered by the regex fallback)"
setup() { printf 'api_key = "%s%s"\n' "9f8e7d6c5b4a3928" "1706f5e4d3c2b1a0" > client.py; git add client.py; }
act()   { bench_commit "add client"; }
