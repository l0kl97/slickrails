# Projekt-Review-Regeln (.slickrails/rules.md)

Projektspezifische Schwerpunkte fuer Reviews (lokal via /code-review und
im PR via claude-review.yml). Kurz halten — nur, was ueber den
Standard hinausgeht. Beispiele:

- Kein `node:`-Import in Client-Code (laeuft im Browser!).
- Alle DB-Zugriffe ueber das Repository-Layer, nie direkt im Handler.
- Deutsch in User-facing Texten, Englisch im Code.

Default-Regeln (gelten, bis sie hier bewusst gestrichen werden):

- Jeder externe Call (HTTP, DB, Queue) hat Timeout + Error-Handling + Logging.
- Keine deprecated APIs einfuehren; bestehende beim Anfassen ersetzen.
- Neue Eingaben (API, Formulare) werden validiert, bevor sie verarbeitet werden.

<!-- Ab hier projektspezifisch ergaenzen: -->
