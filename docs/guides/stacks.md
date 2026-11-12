# Stack support

`install.sh` detects the stack and writes matching checks into
`.slickrails/config.sh` plus a CI workflow. Detection order (last match
wins): python → swift → go → rust → ruby → jvm → **node**.

| Stack | Detected by | Local checks (pre-push / session) | CI template |
|---|---|---|---|
| Node/TS | `package.json` | typecheck + test via your package manager | `ci-node.yml` (PM-aware) |
| Python | `pyproject.toml` / `requirements.txt` | `pytest` (if `tests/`) | `ci-python.yml` |
| Swift | `Package.swift` / `*.xcodeproj` | `swift test` | `ci-swift.yml` |
| Go | `go.mod` | `go build ./...` + `go test ./...` | `ci-go.yml` |
| Rust | `Cargo.toml` | `cargo check` + `cargo test` | `ci-rust.yml` |
| Ruby | `Gemfile` | `rspec` (if `spec/`) or `rake test` | `ci-ruby.yml` |
| JVM | `pom.xml` / `build.gradle(.kts)` | `mvn test` / `gradlew test` | `ci-jvm.yml` |

**One set of checks:** the CI template runs the commands from
`.slickrails/config.sh` (after installing the stack's dependencies), the
same ones the pre-push hook and the Stop gate run. Change a check there
and CI follows. Lint, formatting and build steps stay in the template.

**Dependency audit** (`security.yml`): npm, pnpm, pip, Go
(`govulncheck`), Rust (`cargo audit`), Ruby (`bundler-audit`), each only
when its lockfile is there. Not covered: yarn, bun, JVM.

**Node package managers:** the lockfile decides — `pnpm-lock.yaml`,
`yarn.lock`, `bun.lockb`/`bun.lock`, else npm. Local checks and the CI
template both follow it.

**Monorepos:** the hooks run one command from the repo root — point
`CHECK_TEST` at your workspace runner (`pnpm -r test`,
`turbo run test`, `cargo test --workspace`). Path-filtered per-package
CI is on the roadmap.

**Windows:** hooks and installer are POSIX `sh` and run under Git
Bash (Git for Windows). The full suite runs in CI on `windows-latest`
and blocks merges like Linux and macOS. Without symlink permission
`bootstrap.sh` installs a small launcher instead of a link.

**Wrong guess?** `.slickrails/config.sh` is yours — edit the commands;
`install.sh` never overwrites it.
