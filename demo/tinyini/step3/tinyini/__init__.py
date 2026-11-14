"""tinyini: a small INI parser."""

__all__ = ["ParseError", "parse"]


class ParseError(ValueError):
    """Raised for a line the parser cannot read; ``line_no`` counts from 1."""

    def __init__(self, line_no: int, message: str) -> None:
        super().__init__(f"line {line_no}: {message}")
        self.line_no = line_no


def _value(text: str) -> str:
    """A value without an inline comment: `` ;`` or `` #`` starts one."""
    text = text.strip()
    for marker in (" ;", " #"):
        cut = text.find(marker)
        if cut != -1:
            text = text[:cut]
    return text.strip()


def parse(text: str) -> dict:
    """Parse INI text into ``{section: {key: value}}``.

    Empty input, or input of only blank lines and comments, is an empty
    document: ``{}``.
    """
    doc: dict = {}
    section = "default"
    for line_no, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("["):
            if not line.endswith("]"):
                raise ParseError(line_no, "unterminated section header")
            section = line[1:-1].strip()
            doc.setdefault(section, {})
            continue
        key, sep, value = line.partition("=")
        if not sep:
            raise ParseError(line_no, f"expected key = value, got {line!r}")
        doc.setdefault(section, {})[key.strip()] = _value(value)
    return doc
