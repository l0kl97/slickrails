KIND=fault
DESC="newly staged .env.production must be blocked"
setup() { echo 'DB_PASSWORD=hunter2' > .env.production; git add -f .env.production; }
act()   { bench_commit "add env"; }
