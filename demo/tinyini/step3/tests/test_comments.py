from tinyini import parse


def test_inline_comment_is_not_part_of_the_value():
    assert parse("[core]\nname = demo ; the project\n") == {"core": {"name": "demo"}}


def test_hash_inside_a_value_is_kept():
    assert parse("[core]\ncolor = #1f6f4a\n") == {"core": {"color": "#1f6f4a"}}
