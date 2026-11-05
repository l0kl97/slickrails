# Feature-Dossiers

Hier lebt der Kontext, der sonst verloren geht: In einer
Builder-Organisation bauen Menschen ohne Software-Hintergrund Features
mit Claude Code, Codex & Co. Der Auftrag, die Entscheidungen und der
Testweg stehen dann nur im Chat-Verlauf — und der ist in zwei Monaten
weg, wenn ein Dev einen Bug fixen muss und im Commit zwei Zeilen stehen.

**Deshalb gilt (Regel 11):** Jedes Feature hat hier ein Dossier
(`<feature-slug>.md`, Vorlage: `_TEMPLATE.md`). Die AI-Session legt es
beim Bauen an und haelt es aktuell — der Mensch muss nichts schreiben,
nur drauf achten, dass es passiert.

- **Neu bauen** → Dossier anlegen (Auftrag in Alltagssprache, Entscheidungen, Landkarte der Dateien, Testweg).
- **Aendern/Bugfix** → Historie im Dossier ergaenzen (Symptom → Ursache → Fix).
- **Feature entfernt** → Status auf `entfernt` setzen, Dossier behalten (Archiv).

Fuer den Dev in 2 Monaten: erst `git log` zur Datei, dann das Dossier
hier lesen — Auftrag, Entscheidungen und Testweg stehen drin.

Eine Gewohnheit zahlt sich zusaetzlich aus: eine `docs/CONTEXT.md` mit
dem gemeinsamen Vokabular des Projekts, also den Namen, die euer Team
fuer Konzepte, Module und Flows benutzt. Agents, die das Vokabular
kennen, schreiben praeziseren Code und praezisere Dossiers; Agents ohne
erfinden eigene Woerter fuer eure Dinge.
