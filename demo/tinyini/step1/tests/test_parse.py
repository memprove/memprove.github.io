import pytest

from tinyini import ParseError, parse


def test_sections_and_keys():
    assert parse("[core]\nname = demo\n[paths]\nroot = /srv\n") == {
        "core": {"name": "demo"},
        "paths": {"root": "/srv"},
    }


def test_keys_before_a_header_go_to_default():
    assert parse("debug = true\n[core]\nname = demo\n") == {
        "default": {"debug": "true"},
        "core": {"name": "demo"},
    }


def test_duplicate_key_keeps_last_value():
    assert parse("[core]\nname = a\nname = b\n") == {"core": {"name": "b"}}


def test_line_without_equals_is_an_error():
    with pytest.raises(ParseError) as err:
        parse("[core]\njust words\n")
    assert err.value.line_no == 2
