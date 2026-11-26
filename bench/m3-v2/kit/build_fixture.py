#!/usr/bin/env python3
"""Build the parcelpost fixture repository for the memprove memory benchmark (M3 v2).

Usage: build_fixture.py <DIR> [--after-c2 <command>...]

Creates a Git repository in <DIR> (which must not exist) with eight commits on
`main`, each with a fixed author, committer and date, so the same script gives
the same commit IDs on any machine. The story: on 2026-09-03 (commit c2) an
agent wrote down what it knew, in CLAUDE.md and (with --after-c2) in memprove;
then people changed the code for eight weeks and nobody updated either memory.

v2 against v1 (2026-11-17): docs/DEPLOY.md at c1 names the old staging host,
the notes at c2 name the new one, and c8 makes refunds round down. c1-c7 are
otherwise the same, but the commit IDs differ from v1's.

--after-c2 runs a command in <DIR> right after c2 is committed (the
benchmark uses it to record memprove's statements at that commit).

After c7 the script adds the branch `bench/no-claude-md`: c7 with CLAUDE.md
removed, the starting point of the arms that must not see CLAUDE.md.
"""

import os
import subprocess
import sys
from pathlib import Path

AUTHOR = ("parcelpost dev", "dev@parcelpost.invalid")

FILES_C1 = {
    ".gitignore": "__pycache__/\n*.pyc\n",
    "README.md": """# parcelpost

Shipping quotes for the parcelpost shop API.

    python3 -m parcelpost.cli quote --weight 1200 --zone B

Run the tests from the repository root:

    python3 -m unittest discover -s tests
""",
    "parcelpost/__init__.py": '__version__ = "1.3.0"\n',
    "parcelpost/config.py": '''"""Runtime settings for the parcelpost service."""

HOST = "127.0.0.1"
PORT = 8000
''',
    "parcelpost/pricing.py": '''"""Shipping prices. Money is integer cents everywhere."""

from decimal import ROUND_HALF_UP, Decimal

# Price per started half kilogram, in cents, by zone.
ZONE_RATES = {"A": 450, "B": 690, "C": 980}


def round_half_up(amount):
    """Round a customer-facing amount to whole cents, halves up (the finance team's rule)."""
    return int(Decimal(str(amount)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def quote(weight_g, zone):
    """Return the price in cents of shipping a parcel of weight_g grams to zone."""
    if weight_g <= 0:
        raise ValueError("weight must be positive")
    rate = ZONE_RATES[zone.upper()]
    units = -(-weight_g // 500)
    return units * rate
''',
    "parcelpost/server.py": '''"""Where the HTTP front end listens."""

from . import config


def address():
    return f"http://{config.HOST}:{config.PORT}"
''',
    "parcelpost/cli.py": '''"""Command line: parcelpost quote --weight G --zone Z."""

import argparse

from .pricing import quote


def main(argv=None):
    parser = argparse.ArgumentParser(prog="parcelpost")
    sub = parser.add_subparsers(dest="cmd", required=True)
    q = sub.add_parser("quote", help="price of one parcel")
    q.add_argument("--weight", type=int, required=True, help="grams")
    q.add_argument("--zone", required=True)
    args = parser.parse_args(argv)
    cents = quote(args.weight, args.zone)
    print(f"{cents // 100}.{cents % 100:02d} EUR")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
''',
    "docs/API.md": """# parcelpost API

## GET /quote

Query parameters: `weight` (grams, a positive whole number) and `zone`.

Returns `{"cents": <price>}`: the price in euro cents.
""",
    "docs/DEPLOY.md": """# Deploying parcelpost

Staging: https://staging-1.parcelpost.invalid

Every merge to `main` deploys to staging. Production deploys are manual.
""",
    "docs/FAQ.md": """# FAQ

## Which zones do you ship to?

Zones A, B and C. Your zone is printed on your account page.

## How is the weight charged?

Per started half kilogram.
""",
    "tests/test_pricing.py": '''import unittest

from parcelpost.pricing import quote, round_half_up


class QuoteTest(unittest.TestCase):
    def test_started_half_kilograms(self):
        self.assertEqual(quote(1, "A"), 450)
        self.assertEqual(quote(500, "A"), 450)
        self.assertEqual(quote(501, "A"), 900)

    def test_zone_is_case_insensitive(self):
        self.assertEqual(quote(1200, "b"), quote(1200, "B"))

    def test_weight_must_be_positive(self):
        with self.assertRaises(ValueError):
            quote(0, "A")


class RoundingTest(unittest.TestCase):
    def test_halves_go_up(self):
        self.assertEqual(round_half_up(2.5), 3)
        self.assertEqual(round_half_up(3.5), 4)
        self.assertEqual(round_half_up(2.4), 2)
''',
    "tests/test_server.py": '''import unittest

from parcelpost import config
from parcelpost.server import address


class AddressTest(unittest.TestCase):
    def test_address_uses_the_configured_port(self):
        self.assertEqual(address(), f"http://127.0.0.1:{config.PORT}")
''',
}

CLAUDE_MD = """# parcelpost: notes for coding agents

- Run the tests with `python3 -m unittest discover -s tests` from the repository root.
- Money is integer cents everywhere. Customer-facing amounts are rounded half-up to whole cents with `pricing.round_half_up`, never with `round()`.
- API clients are rate limited to 100 requests per minute per API key.
- Orders of €50.00 or more ship free.
- Ops allocated port 7431 to parcelpost in the shared host's port registry; the code still defaults to 8000 until we switch.
- Ops moved staging to https://staging-2.parcelpost.invalid on 2026-09-02; staging-1 is retired. docs/DEPLOY.md still names staging-1 until someone updates it.
"""

RATELIMIT_PY = '''"""Fixed-window rate limiting per API key."""

import time

from . import config


class RateLimiter:
    def __init__(self, limit=None, clock=time.monotonic):
        self.limit = config.RATE_LIMIT_PER_MIN if limit is None else limit
        self.clock = clock
        self.windows = {}

    def allow(self, key):
        window = int(self.clock() // 60)
        start, count = self.windows.get(key, (window, 0))
        if start != window:
            start, count = window, 0
        if count >= self.limit:
            return False
        self.windows[key] = (start, count + 1)
        return True
'''

TEST_RATELIMIT = '''import unittest

from parcelpost import config
from parcelpost.ratelimit import RateLimiter


class RateLimiterTest(unittest.TestCase):
    def test_limit_per_minute(self):
        self.assertEqual(config.RATE_LIMIT_PER_MIN, {limit})

    def test_refuses_above_the_limit_in_one_minute(self):
        limiter = RateLimiter(clock=lambda: 0)
        for _ in range(config.RATE_LIMIT_PER_MIN):
            self.assertTrue(limiter.allow("k"))
        self.assertFalse(limiter.allow("k"))
        self.assertTrue(limiter.allow("other"))

    def test_new_minute_new_window(self):
        now = [0]
        limiter = RateLimiter(limit=1, clock=lambda: now[0])
        self.assertTrue(limiter.allow("k"))
        self.assertFalse(limiter.allow("k"))
        now[0] = 61
        self.assertTrue(limiter.allow("k"))
'''

TEST_FREE_SHIPPING = '''import unittest

from parcelpost.pricing import FREE_SHIPPING_MIN_CENTS, quote, shipping_for_order


class FreeShippingTest(unittest.TestCase):
    def test_threshold(self):
        self.assertEqual(FREE_SHIPPING_MIN_CENTS, {threshold})

    def test_at_or_above_the_threshold_ships_free(self):
        self.assertEqual(shipping_for_order({threshold}, 1200, "B"), 0)
        self.assertEqual(shipping_for_order({threshold} - 1, 1200, "B"), quote(1200, "B"))
'''


MONEY_PY = '''"""Rounding of refunds. Money is integer cents everywhere."""

import math


def refund_cents(amount):
    """Round a refund to whole cents, always down (finance rule FIN-112, from 2026-10-28).

    Prices and every other customer-facing amount still round half-up with
    pricing.round_half_up; refunds never do.
    """
    return int(math.floor(amount))
'''

TEST_MONEY = '''import unittest

from parcelpost.money import refund_cents


class RefundRoundingTest(unittest.TestCase):
    def test_refunds_round_down(self):
        self.assertEqual(refund_cents(502.5), 502)
        self.assertEqual(refund_cents(99.9), 99)
        self.assertEqual(refund_cents(100), 100)
'''


def pricing_c2(text):
    text = text.replace(
        '# Price per started half kilogram',
        'FREE_SHIPPING_MIN_CENTS = 5000\n\n# Price per started half kilogram',
    )
    return text + '''

def shipping_for_order(order_cents, weight_g, zone):
    """Shipping in cents for an order: free from FREE_SHIPPING_MIN_CENTS on."""
    if order_cents >= FREE_SHIPPING_MIN_CENTS:
        return 0
    return quote(weight_g, zone)
'''


def commits():
    """Yield (name, date, message, {path: content or None})."""
    yield ("c1", "2026-09-01T09:00:00+00:00", "initial: quotes by weight and zone", dict(FILES_C1))

    pricing = pricing_c2(FILES_C1["parcelpost/pricing.py"])
    yield ("c2", "2026-09-03T14:00:00+00:00", "add per-key rate limiting and the free-shipping threshold", {
        "parcelpost/config.py": FILES_C1["parcelpost/config.py"]
        + "RATE_LIMIT_PER_MIN = 100  # requests per minute per API key\n",
        "parcelpost/ratelimit.py": RATELIMIT_PY,
        "parcelpost/pricing.py": pricing,
        "tests/test_ratelimit.py": TEST_RATELIMIT.replace("{limit}", "100"),
        "tests/test_free_shipping.py": TEST_FREE_SHIPPING.replace("{threshold}", "5000"),
        "CLAUDE.md": CLAUDE_MD,
    })

    cli = FILES_C1["parcelpost/cli.py"]
    cli = cli.replace("import argparse\n", "import argparse\nimport json\n")
    cli = cli.replace(
        '    q.add_argument("--zone", required=True)\n',
        '    q.add_argument("--zone", required=True)\n'
        '    q.add_argument("--json", action="store_true", help="print {\\"cents\\": N}")\n',
    )
    cli = cli.replace(
        '    print(f"{cents // 100}.{cents % 100:02d} EUR")\n',
        '    if args.json:\n'
        '        print(json.dumps({"cents": cents}))\n'
        '    else:\n'
        '        print(f"{cents // 100}.{cents % 100:02d} EUR")\n',
    )
    yield ("c3", "2026-09-10T10:30:00+00:00", "cli: --json prints the quote as JSON", {
        "parcelpost/cli.py": cli,
        "tests/test_cli.py": '''import io
import json
import unittest
from contextlib import redirect_stdout

from parcelpost.cli import main


class CliTest(unittest.TestCase):
    def run_cli(self, *argv):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(main(list(argv)), 0)
        return out.getvalue().strip()

    def test_text(self):
        self.assertEqual(self.run_cli("quote", "--weight", "1200", "--zone", "A"), "13.50 EUR")

    def test_json(self):
        self.assertEqual(json.loads(self.run_cli("quote", "--weight", "1200", "--zone", "A", "--json")), {"cents": 1350})
''',
    })

    pricing_c4 = pricing.replace('{"A": 450, "B": 690, "C": 980}', '{"A": 450, "B": 690, "C": 980, "D": 1450}')
    faq_c4 = FILES_C1["docs/FAQ.md"].replace("Zones A, B and C.", "Zones A, B and C, and zone D for the islands.")
    yield ("c4", "2026-09-18T16:00:00+00:00", "pricing: zone D for the islands", {
        "parcelpost/pricing.py": pricing_c4,
        "docs/FAQ.md": faq_c4,
        "tests/test_zones.py": '''import unittest

from parcelpost.pricing import quote


class ZoneDTest(unittest.TestCase):
    def test_islands(self):
        self.assertEqual(quote(400, "D"), 1450)
''',
    })

    yield ("c5", "2026-10-02T08:15:00+00:00",
           "rate limit: 60 requests per minute per key after the 2026-09-30 incident", {
        "parcelpost/config.py": FILES_C1["parcelpost/config.py"]
        + "RATE_LIMIT_PER_MIN = 60  # requests per minute per API key\n",
        "tests/test_ratelimit.py": TEST_RATELIMIT.replace("{limit}", "60"),
    })

    yield ("c6", "2026-10-15T11:45:00+00:00", "pricing: free shipping from 7500 cents", {
        "parcelpost/pricing.py": pricing_c4.replace("FREE_SHIPPING_MIN_CENTS = 5000", "FREE_SHIPPING_MIN_CENTS = 7500"),
        "tests/test_free_shipping.py": TEST_FREE_SHIPPING.replace("{threshold}", "7500"),
    })

    yield ("c7", "2026-10-20T13:00:00+00:00", "docs: describe the quote endpoint's errors", {
        "docs/API.md": FILES_C1["docs/API.md"] + """
Errors: `400 Bad Request` when `weight` is not a positive whole number or
`zone` is not a zone we ship to.
""",
    })

    yield ("c8", "2026-10-28T09:20:00+00:00", "money: refunds round down to whole cents (finance rule FIN-112)", {
        "parcelpost/money.py": MONEY_PY,
        "tests/test_money.py": TEST_MONEY,
    })


def git(repo, *args, date=None):
    env = dict(os.environ)
    for key in list(env):
        if key.startswith("GIT_"):
            del env[key]
    env.update({
        "GIT_AUTHOR_NAME": AUTHOR[0], "GIT_AUTHOR_EMAIL": AUTHOR[1],
        "GIT_COMMITTER_NAME": AUTHOR[0], "GIT_COMMITTER_EMAIL": AUTHOR[1],
        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
    })
    if date:
        env["GIT_AUTHOR_DATE"] = date
        env["GIT_COMMITTER_DATE"] = date
    return subprocess.run(["git", "-C", str(repo), *args], env=env, check=True,
                          capture_output=True, text=True).stdout.strip()


def write(repo, changes):
    for path, content in changes.items():
        target = repo / path
        if content is None:
            target.unlink()
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    repo = Path(argv[1]).resolve()
    after_c2 = None
    if len(argv) > 2:
        if argv[2] != "--after-c2" or len(argv) < 4:
            print(__doc__, file=sys.stderr)
            return 2
        after_c2 = argv[3:]
    if repo.exists():
        print(f"{repo} exists; remove it first", file=sys.stderr)
        return 2
    repo.mkdir(parents=True)
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "core.autocrlf", "false")
    git(repo, "config", "commit.gpgsign", "false")
    git(repo, "config", "core.hooksPath", os.devnull)
    for name, date, message, changes in commits():
        write(repo, changes)
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", message, date=date)
        print(f"{name} {git(repo, 'rev-parse', 'HEAD')} {message}")
        if name == "c2" and after_c2:
            subprocess.run(after_c2, cwd=repo, check=True)
    # The arms without CLAUDE.md start from this commit.
    git(repo, "checkout", "-q", "-b", "bench/no-claude-md")
    git(repo, "rm", "-q", "CLAUDE.md")
    git(repo, "commit", "-q", "-m", "bench: the same tree without CLAUDE.md", date="2026-10-20T13:00:00+00:00")
    print(f"no-claude-md {git(repo, 'rev-parse', 'HEAD')}")
    git(repo, "checkout", "-q", "main")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
