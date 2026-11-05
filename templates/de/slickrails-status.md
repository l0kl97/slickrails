# Guardrails-Status

Stand: __DATE__ (von install.sh erzeugt; bei jeder Aenderung nachfuehren — Regel 10)

| # | Regel | Status | Notiz |
|---|---|---|---|
| 1 | Repro-Test vor Bugfix | ☐ | Arbeitsregel — gilt ab sofort |
| 2 | Browser-Smoke-Tests fuer kritische Flows | ☐ | Flows auflisten + Playwright-Tests anlegen |
| 3 | pre-push: Typecheck + Tests | __HOOKS__ | |
| 4 | Secrets-Scan (pre-commit + CI) | __HOOKS__ | gitleaks lokal installieren: `brew install gitleaks` |
| 5 | Branch Protection auf main | ☐ | `slickrails protect` (braucht gh) |
| 6 | AI-Review vor dem Merge | __REVIEW__ | Lokal vor jedem Push mit deinem claude- oder codex-CLI (`CHECK_PREPUSH_REVIEW="1"`); zusätzlich serverseitig auf GitHub: `slickrails github-review` |
| 7 | Dependabot + Audit im CI | __WORKFLOWS__ | |
| 8 | Definition of Done gelebt | ☐ | Arbeitsregel |
| 9 | Standard-Test-Stack (__STACK__) | ☐ | pruefen/migrieren |
| 10 | Dieses Dokument aktuell halten | ☑ | |
| 11 | Feature-Dossiers + Commit-Bodies (Kontext bleibt) | __HOOKS__ | Bestehende Kern-Features nach und nach nachdokumentieren |
| 12 | PR-Groessen-Limit (pr-size.yml) | __WORKFLOWS__ | Label `size-ok` fuer bewusste Ausnahmen anlegen |

## Offene Luecken (mit Datum)

- __DATE__: Initial-Install — offene Punkte siehe Tabelle.
