import pytest

from tinyini import parse


@pytest.mark.parametrize("text", ["", "\n", "   \n\t\n"])
def test_empty_input_is_an_empty_document(text):
    assert parse(text) == {}


def test_comments_only_is_an_empty_document():
    assert parse("# a comment\n; another\n") == {}
