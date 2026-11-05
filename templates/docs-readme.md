# Feature Dossiers

This is where the context lives that otherwise dies: in a builder
organization, people without a software background ship features with
Claude Code, Codex & co. The ask, the decisions, and the test path then
exist only in a chat history — which is gone in two months, when a
developer has to fix a bug and the commit says two lines.

**Therefore (rule 11):** every feature has a dossier here
(`<feature-slug>.md`, template: `_TEMPLATE.md`). The AI session creates
it while building and keeps it current — the human doesn't have to
write anything, only make sure it happens.

- **Building something new** → create a dossier (ask in plain language, decisions, map of files, test path).
- **Changing / fixing** → extend the history in the dossier (symptom → cause → fix).
- **Feature removed** → set status to `removed`, keep the dossier (archive).

For the developer two months from now: `git log` on the file first,
then read the dossier here — the ask, the decisions, and the test path
are all in it.

One more habit that pays off: keep a `docs/CONTEXT.md` with the
project's shared vocabulary, the names your team uses for its concepts,
modules, and flows. Agents that know the vocabulary write tighter code
and tighter dossiers; agents that don't will invent their own words for
your things.
