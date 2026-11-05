# Guardrails — Das Regelwerk (slickrails)

Dieses Dokument ist der Standard für alle Projekte (neu und bestehend).
Es wird per `install.sh` in jedes Repo gezogen und dort von Menschen, CI
und Claude-Sessions gleichermaßen befolgt.

Gestohlen wurde das Beste aus drei Welten:
- **no-mistakes:** Gate vor dem Push, isoliert, Auto-Fix für Mechanisches, Eskalation für Ermessensfragen.
- **git-lrc:** Review nach Risiko-Kategorien, projekt-eigene Regeln als versionierte Datei (`.slickrails/rules.md`).
- **Eigene Learnings:** Browser-Smoke-Tests für kritische Flows (Node-Unit-Tests fangen browser-only Bugs nicht).

---

## Die 12 Regeln

### 1. Repro-Test vor Bugfix
Jeder Bugfix beginnt mit einem Test, der den Bug reproduziert und **rot** ist.
Erst dann wird gefixt, bis der Test grün ist. Kein Fix ohne Repro-Test —
sonst wissen wir nie, ob der Bug wirklich weg ist oder nur gerade nicht sichtbar.

### 2. Kritische Flows haben Smoke-Tests im echten Browser
Alles, was ein Nutzer als Kernfunktion erlebt (Login, Anlegen, Bezahlen,
Speichern), hat einen Playwright-Smoke-Test, der im echten Browser läuft.
Unit-Tests in Node reichen dafür nicht (browser-only Bugs wie
`node:crypto` im Client bleiben sonst unsichtbar). Für native Apps gilt
das Äquivalent: XCUITest bzw. ein End-to-End-Lauf der echten App.

### 3. Grün vor Push
Der `pre-push`-Hook fährt Typecheck + Tests lokal, bevor irgendetwas das
Gerät verlässt. Was lokal rot ist, wird nicht gepusht.

### 4. Keine Secrets im Repo
`pre-commit` scannt Staged Changes auf Secrets (gitleaks, mit
Fallback-Mustern) und blockiert `.env`-Dateien. Der gleiche Scan läuft
nochmal im CI — doppelter Boden.

### 5. main ist geschützt
Auf `main`/`master` wird nie direkt gepusht. Änderungen gehen über
Branches + PR, und der PR merged nur mit grünem CI. Branch Protection
wird per `slickrails protect` (gh CLI) eingerichtet; das
Skript liest die Einstellungen von GitHub zurück und meldet, was wirklich
gilt: Pflicht-Statuschecks allein erzwingen keinen PR, und Admins sind nur
gebunden, solange nicht `ENFORCE_ADMINS=0` gesetzt ist.

### 6. Jeder PR bekommt ein AI-Review
Vor dem Merge läuft ein Review — standardmäßig lokal vor jedem Push mit dem
eigenen `claude`- oder `codex`-CLI (`.slickrails/ai-review.sh`, ohne API-Key),
oder von Hand via `/code-review`; wer es serverseitig erzwingen will, ergänzt
`claude-review.yml` mit `slickrails github-review`. Reviewt wird entlang
der Risiko-Kategorien: Correctness, Reliability, Security, Performance,
Maintainability. Projekt-eigene Schwerpunkte stehen in
`.slickrails/rules.md` und fließen ins Review ein.

### 7. Dependencies unter Kontrolle
Dependabot ist aktiviert, und der Security-Workflow fährt `npm audit` /
`pip-audit` (je nach Stack) auf jedem PR. Bekannte CVEs blockieren den Merge.

### 8. Definition of Done
Ein Feature ist fertig, wenn: Code + Tests + Doku-Update vorhanden sind
und die Smoke-Tests grün sind. "Läuft bei mir" ist kein Zustand.
Und: Tests zählen nur, wenn sie echte Fehlerfälle prüfen — ungültige
Eingaben, Fehler-Antworten, Grenzwerte. Happy-Path-only-Tests sind
falsche Sicherheit und im Review ein Finding.

### 9. Ein Test-Stack pro Sprache
- TypeScript/Node: **Vitest** (Unit) + **Playwright** (Smoke/E2E)
- Python: **pytest**
- Swift: **swift test / XCTest** (+ XCUITest für UI)

Keine Parallel-Frameworks im selben Repo. Neue Projekte starten mit
diesem Stack, bestehende migrieren bei Gelegenheit.

### 10. Lücken sind sichtbar, nicht geheim
Jedes Repo hat nach dem Install eine `.slickrails/STATUS.md`: welche
Regeln greifen schon, welche noch nicht. Eine Lücke ist ein TODO mit
Datum — kein stilles Weglassen.

### 11. Kontext bleibt erhalten (die Builder-Regel)
In einer Builder-Organisation bauen Menschen ohne Software-Hintergrund
Features mit AI-Tools. Der Kontext — Auftrag, Entscheidungen, Testweg —
lebt dann nur im Chat-Verlauf und im Kopf, und beides ist weg, wenn zwei
Monate später ein Dev einen Bug fixen muss und im Commit zwei Zeilen
stehen. Deshalb, mechanisch abgesichert:

- **Feature-Dossiers:** Jedes Feature hat `docs/features/<slug>.md` —
  Auftrag in Alltagssprache (Original-Wunsch!), Entscheidungen, wo es
  lebt, Testweg, Bugfix-Historie. Die AI-Session schreibt und pflegt es;
  der Mensch muss nichts dokumentieren können.
- **Commit-Bodies:** Der `commit-msg`-Hook blockiert Commits ab ~30
  geänderten Zeilen ohne erklärenden Body (Warum + Was).
- **PR-Template:** Warum / Was / Wie getestet / Risiken — plus Checkbox
  fürs Dossier.

### 12. Kleine, reviewbare PRs
AI macht riesige Änderungen billig — und damit unreviewbar. Ein PR
bleibt unter ~800 geänderten Zeilen (ohne Lockfiles); `pr-size.yml`
blockiert darüber. Bewusste Ausnahmen (generierter Code, Migration)
bekommen das Label `size-ok` — eine sichtbare Entscheidung statt eines
durchgewunkenen Monsters.

---

## Escape Hatch (erlaubt, aber laut)

Not-Pushes gehen mit `SLICKRAILS_SKIP=1 git push` am Hook vorbei bzw.
`git commit --no-verify`. Bedingung: Der Grund steht im Commit-Text.
Skips sind für kaputte CI-Umgebungen gedacht, nicht für rote Tests.

## Ebenen-Modell

| Ebene | Wann | Was | Dauer |
|---|---|---|---|
| pre-commit | bei jedem Commit | Secrets-Scan, .env-Block, Lint (staged) | Sekunden |
| commit-msg | bei jedem Commit | Body-Pflicht ab ~30 geänderten Zeilen | Sekunden |
| pre-push | bei jedem Push | Typecheck + Tests | < 2 min |
| CI (PR) | bei jedem PR | Lint, Typecheck, Tests, Build, Security-Scan, Smoke | Minuten |
| Review | vor Merge | AI-Review (+ Mensch bei Ermessensfragen) | Minuten |
| Session | Claude will "fertig" sagen | Stop-Hook: Typecheck + Tests | < 2 min |

Lokal schnell und streng beim Mechanischen; CI vollständig und
unbestechlich; Review für alles, was Urteilsvermögen braucht.

## Session-Ebene: Durchsetzung statt Versprechen

Der Guardrails-Block in der CLAUDE.md ist eine Anweisung — der Stop-Hook
in `.claude/settings.json` ist die Durchsetzung. Er läuft, sobald eine
Claude-Session ihren Task beenden will: Gibt es ungecommittete Änderungen
oder Commits, die noch nicht auf dem Upstream-/Default-Branch liegen,
fährt `.slickrails/session-check.sh` die Checks aus `config.sh` und
blockiert das Beenden, solange sie rot sind (Exit 2 → Claude muss fixen).
Der Hook überlässt dem Host nie die Entscheidung: Er hat eine eigene
Deadline (`SLICKRAILS_STOP_DEADLINE_MS`, Default 270 s — ein Host-Timeout
ließe die Session still enden), ein Absturz zählt als rot, ein bereits
grün geprüfter Stand wird nicht erneut geprüft, und nach 3 Blockaden bei
unverändertem Stand lässt er die Session mit einem lauten „NOT done" enden.
Mechanische Checks gehören in deterministische Hooks, nicht an Subagents
delegiert — ein Hook lässt sich nicht überreden. AI-Instanzen (frisch,
ohne Autoren-Bias) sind für das Urteilen zuständig: `/code-review` lokal,
`claude-review.yml` auf dem PR. Optional pro Repo: `CHECK_SESSION` in
`config.sh` überschreibt, was der Stop-Hook fährt. Ein `PreToolUse`-Bash-Guard
(`.slickrails/bash-guard.sh`) blockiert die offensichtlichen Umgehungen durch
einen Agenten (`git … --no-verify`, `SLICKRAILS_SKIP=`, Schreiben auf die
Guardrail-Dateien) und Befehle, die Arbeit oder Daten vernichten
(`git reset --hard`, Force-Push, `rm -rf ~`, DB-Reset); der Ausweg gehört dem
Menschen (`SLICKRAILS_ALLOW_BYPASS=1` bzw. `SLICKRAILS_ALLOW_DESTRUCTIVE=1` in
der Umgebung des Agenten, oder er führt den Befehl selbst aus). Das ist
ein Hinweis, keine Grenze — CI und Branch Protection halten wirklich.

## Abgrenzung: LLM-Feature-Guardrails

Dieses Regelwerk sichert *unseren Code*. Sobald ein Produkt selbst
LLM-Features hat (Chat, Generierung, Agents), braucht es zusätzlich
Guardrails auf App-Ebene: PII-Redaction, Prompt-Injection-Abwehr,
Output-Validierung (strukturiert statt Freitext parsen). Dafür sind
Frameworks wie guardrails-ai (hub: Detect PII, Detect Prompt Injection,
Provenance) das richtige Werkzeug — das ist Produkt-Code und gehört in
das jeweilige Projekt, nicht in dieses Kit.

## Die 10 typischen AI-Code-Fallen — und wo sie hängen bleiben

| Falle | Fängt ab |
|---|---|
| Insecure Defaults (Validierung, Secrets, Injection) | Secrets: pre-commit + gitleaks-CI. Validierung/Injection: AI-Review-Kategorie Security |
| Subtile Logikfehler / Edge Cases | Regel 1 (Repro-Tests), AI-Review-Kategorie Correctness |
| Skill Attrition | Nicht per Tooling lösbar. Milderung: Dossiers + Commit-Bodies in Alltagssprache — man kann nachlesen und verstehen, was gebaut wurde |
| Wartungs-Albtraum (deprecated APIs, Struktur) | AI-Review-Kategorie Maintainability, Lint im CI, /simplify |
| Ignorierte Architektur / Konventionen | `.slickrails/rules.md` fließt in jedes Review ein — genau dafür ist die Datei da |
| Falsche Test-Sicherheit (Happy Path only) | Regel 8: Failure-Mode-Tests Pflicht; Review meldet Happy-Path-only als Finding |
| Versteckte Concurrency-Fehler | AI-Review-Kategorie Reliability: Races + DB-Transaktionen unter Last; Smoke unter realem Browser |
| Aufgeblähte PRs | Regel 12 + `pr-size.yml` (Limit ~800 Zeilen, Label `size-ok` als bewusste Ausnahme) |
| Lizenz-/IP-Risiko | Teilweise: Review meldet wortwörtlich wirkenden Fremdcode; Dependency-Lizenzen via Audit. Restrisiko bleibt — bei Verdacht Quelle prüfen |
| Fehlender Betriebskontext (Logging, Timeouts, Monitoring) | AI-Review-Kategorie Betrieb; Default-Regel in `rules.md`: externe Calls brauchen Timeout + Error-Handling + Logging |
