import pytest

from duration import MAX_MINUTES, parse_duration


@pytest.mark.parametrize("text, minutes", [("1h30m", 90), ("45m", 45), ("2h", 120), (" 1H 5M ", 65), ("90m", 90)])
def test_reads_what_people_type(text, minutes):
    assert parse_duration(text) == minutes


def test_a_whole_day_is_the_limit():
    assert parse_duration("24h") == MAX_MINUTES
    with pytest.raises(ValueError):
        parse_duration("24h1m")


@pytest.mark.parametrize("text", ["", "abc", "1.5h", "h", "30s", "0m", "1h75m"])
def test_refuses_what_is_no_duration(text):
    with pytest.raises(ValueError):
        parse_duration(text)


def test_refuses_anything_but_text():
    with pytest.raises(TypeError):
        parse_duration(90)
