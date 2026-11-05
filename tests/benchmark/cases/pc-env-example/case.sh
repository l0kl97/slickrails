KIND=control
DESC=".env.example with placeholders must pass"
setup() { printf 'DB_PASSWORD=\nAPI_URL=http://localhost\n' > .env.example; git add .env.example; }
act()   { bench_commit "add env example"; }
