"""Reads a duration as people type it ("1h30m", "45m", "2h") and returns minutes."""
import re

MAX_MINUTES = 24 * 60
_PATTERN = re.compile(r"(?:(\d+)h)?(?:(\d+)m)?")


def parse_duration(text: str) -> int:
    if not isinstance(text, str):
        raise TypeError("parse_duration: text must be a string")
    match = _PATTERN.fullmatch(text.strip().lower().replace(" ", ""))
    if match is None or not any(match.groups()):
        raise ValueError(f"parse_duration: not a duration: {text!r} (examples: 1h30m, 45m, 2h)")
    hours, minutes = (int(g) if g else 0 for g in match.groups())
    if minutes >= 60 and hours:
        raise ValueError(f"parse_duration: {minutes} minutes next to hours, write {hours + minutes // 60}h{minutes % 60}m")
    total = hours * 60 + minutes
    if total == 0 or total > MAX_MINUTES:
        raise ValueError(f"parse_duration: {total} minutes is outside 1..{MAX_MINUTES}")
    return total
