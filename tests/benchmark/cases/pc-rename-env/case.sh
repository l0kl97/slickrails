KIND=fault
DESC="rename of a plain file onto .env must be blocked (diff-filter ACM misses renames)"
setup() {
  echo 'DB_PASSWORD=hunter2' > public.txt; git add public.txt; git commit -q --no-verify -m "plain"
  git mv public.txt .env
}
act()   { bench_commit "rename to env"; }
