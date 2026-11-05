<!-- slickrails:start — dieser Block wird von install.sh in die CLAUDE.md des Projekts eingefuegt -->
## Guardrails (verbindlich)

Dieses Repo folgt dem Guardrails-Standard (siehe `.slickrails/SLICKRAILS.md`). Fuer jede Claude-Session gilt:

- **Bugfix = erst Repro-Test (rot), dann Fix (gruen).** Nie umgekehrt, nie ohne Test.
- **Kritische User-Flows brauchen Playwright-Smoke-Tests im echten Browser** — Node-Unit-Tests reichen nicht. Neuer kritischer Flow ⇒ neuer Smoke-Test im selben PR.
- **Vor "fertig":** Checks aus `.slickrails/config.sh` lokal ausfuehren (Typecheck, Tests, Smoke falls vorhanden). Rot = nicht fertig.
- **Definition of Done:** Code + Tests + Doku-Update + Smoke gruen.
- **Nie** direkt auf main pushen, **nie** Hooks mit `--no-verify`/`SLICKRAILS_SKIP` umgehen, ausser der Mensch sagt es explizit — dann Grund in den Commit-Text.
- **Keine Secrets** in Code oder Commits; `.env` bleibt lokal, `.env.example` wird gepflegt.
- **Sicherheitsrelevante Aenderungen** (Auth, Eingaben, Krypto, Datei-/Netzwerkzugriff) bekommen vor dem Merge ein lokales `/security-review`.
- Projektspezifische Review-Schwerpunkte stehen in `.slickrails/rules.md` — bei Reviews und groesseren Aenderungen beruecksichtigen.
- **Feature-Dossier pflegen (Regel 11):** Beim Bauen eines Features `docs/features/<slug>.md` anlegen (Vorlage `_TEMPLATE.md`): Auftrag in Alltagssprache (den Original-Wunsch des Menschen festhalten!), Entscheidungen, wo es lebt, Testweg. Bei Aenderungen/Bugfixes die Historie ergaenzen (Symptom → Ursache → Fix).
- **Commit-Bodies erzaehlen Warum + Was** in Alltagssprache — nicht nur was, sondern wofuer. Der commit-msg-Hook erzwingt das bei groesseren Commits.
- **Tests pruefen Fehlerfaelle**, nicht nur den Happy Path: ungueltige Eingaben, Fehler-Antworten, Grenzwerte. Happy-Path-only ist nicht fertig.
- **Kein Code im Vakuum:** Externe Calls (HTTP, DB, Queue) bekommen Timeout, Error-Handling und Logging. Keine deprecated APIs einfuehren.
- **PRs klein halten** (< ~800 geaenderte Zeilen): Grosse Aufgaben in mehrere PRs schneiden, statt einen unreviewbaren zu bauen.
- **Validator-Gedaechtnis:** Faengt ein Hook, ein Review oder ein Mensch einen echten Fehler in AI-gebautem Code, die Lehre in `.slickrails/review-learnings.md` nachtragen — jeder gefangene Fehler macht das naechste Review schlauer.
- Erledigte/neue Luecken im Standard in `.slickrails/STATUS.md` nachfuehren.
<!-- slickrails:end -->
