# Durations as people type them (parse_duration)

**Status:** active · **As of:** 2026-11-28 · **Built by:** the time tracker's developer with Claude Code

## The ask (plain language)
"In the time tracker people should type how long something took the way they say it: 1h30m, 45m, 2h. Store minutes.
If someone types nonsense, tell them what a valid input looks like instead of saving zero."

## Decisions
- **Hours and minutes only** (`1h30m`, `45m`, `2h`), case and spaces do not matter. Rejected: decimal hours
  (`1.5h`): people mix up 1.5h and 1h50m, and the tracker shows minutes anyway.
- **Errors say what is valid.** `ValueError` with examples in the message, `TypeError` for anything but text. The
  form shows the message as it is.
- **Range 1 minute to 24 hours.** One entry is one task on one day; 0 and more than a day are typing mistakes.
- **Minutes of 60 or more next to hours are refused** (`1h75m`), with the spelling to use instead. `90m` alone is
  fine.

## Where it lives
- `src/duration/__init__.py`: `parse_duration(text)` and `MAX_MINUTES`
- `tests/test_duration.py`: valid inputs, the 24-hour limit, refusals

## How to test it
1. `python3 -m pip install pytest` once, then `python3 -m pytest -q` (the pre-push hook runs the same).
2. By hand: `PYTHONPATH=src python3 -c 'from duration import parse_duration; print(parse_duration("1h30m"))'`
   prints `90`.

## Limits & open items
- No seconds and no days. If the tracker ever logs machine time, this needs a second function, not more syntax.
- The messages are English; the form has no translation for them yet.

## History
- 2026-11-28: created.
- 2026-11-28: `1h75m` was stored as 135 minutes, nobody noticed the typo → hours and minutes were simply added →
  minutes of 60 or more next to hours are refused; repro case `1h75m` in `test_refuses_what_is_no_duration` first.
