#!/usr/bin/env python3
"""Write the benchmark's task files into the parcelpost fixture (M3 v2: eight tasks).

Usage: make_evals.py <FIXTURE> [<ARM>...]

For every arm (default: every arm whose base branch exists) writes
evals/<arm>/<task>.json, and writes the hidden tests as
evals/checks/<task>.check.patch. Every arm gets the same eight prompts and the
same checks; arms differ only in the commit the agent starts from (with or
without CLAUDE.md, or with the CLAUDE.md stalebrain corrected) and in what
run_bench.sh passes to `memprove eval run` (--memory pack for memprove).
evals/ is in the fixture's .git/info/exclude, so it is never part of a commit.
"""

import json
import subprocess
import sys
from pathlib import Path

# arm -> the branch its tasks start from
ARMS = {
    "none": "bench/no-claude-md",
    "claude-md": "main",
    "memprove": "bench/no-claude-md",
    "stalebrain": "bench/stalebrain",
}

CHECK = {"argv": ["python3", "-m", "unittest", "discover", "-s", "tests"], "timeout_secs": 300}

TASKS = [
    {
        "id": "port",
        "title": "switch to the port ops allocated (memory needed, still true)",
        "kind": "needs-memory",
        "prompt": "Switch parcelpost's default port to the port ops allocated to this service.",
        "test_file": "tests/test_bench_port.py",
        "test": '''import unittest

from parcelpost import config
from parcelpost.server import address


class BenchPortTest(unittest.TestCase):
    def test_default_port_is_the_allocated_one(self):
        self.assertEqual(config.PORT, 7431)

    def test_address_uses_it(self):
        self.assertTrue(address().endswith(":7431"))
''',
    },
    {
        "id": "ratelimit-docs",
        "title": "document the rate limit (memory outdated: 100, code: 60)",
        "kind": "memory-outdated",
        "prompt": "docs/API.md says nothing about rate limits. Add a short section that tells API clients "
                  "how many requests per minute they may make.",
        "test_file": "tests/test_bench_ratelimit_docs.py",
        "test": '''import re
import unittest
from pathlib import Path

DOC = Path(__file__).resolve().parents[1] / "docs" / "API.md"


class BenchRateLimitDocsTest(unittest.TestCase):
    def test_api_doc_states_the_limit_in_force(self):
        text = DOC.read_text(encoding="utf-8")
        self.assertRegex(text.lower(), r"rate[ -]?limit")
        self.assertRegex(text, r"(?<![0-9.,])60(?![0-9])")
        self.assertNotRegex(text, r"(?<![0-9.,])100(?![0-9])")
''',
    },
    {
        "id": "free-shipping-faq",
        "title": "answer 'when is shipping free?' (memory outdated: EUR 50, code: EUR 75)",
        "kind": "memory-outdated",
        "prompt": "Customers keep asking when shipping is free. Add an entry to docs/FAQ.md that answers it.",
        "test_file": "tests/test_bench_free_shipping_faq.py",
        "test": '''import re
import unittest
from pathlib import Path

DOC = Path(__file__).resolve().parents[1] / "docs" / "FAQ.md"


class BenchFreeShippingFaqTest(unittest.TestCase):
    def test_faq_states_the_threshold_in_force(self):
        text = DOC.read_text(encoding="utf-8")
        self.assertIn("free", text.lower())
        self.assertRegex(text, r"(?<![0-9.,])75(?:[.,]00)?(?![0-9])|(?<![0-9.,])7500(?![0-9])")
        self.assertNotRegex(text, r"(?<![0-9.,])50(?:[.,]00)?(?![0-9])|(?<![0-9.,])5000(?![0-9])")
''',
    },
    {
        "id": "discount",
        "title": "add apply_discount (memory and code agree; control)",
        "kind": "control",
        "prompt": "Add `apply_discount(cents, percent)` to parcelpost/pricing.py: it returns the price after "
                  "taking `percent` percent off, in whole cents, rounded the way this project rounds "
                  "customer-facing amounts. Add a test for it.",
        "test_file": "tests/test_bench_discount.py",
        "test": '''import unittest

from parcelpost.pricing import apply_discount


class BenchDiscountTest(unittest.TestCase):
    def test_halves_round_up(self):
        self.assertEqual(apply_discount(1005, 50), 503)
        self.assertEqual(apply_discount(1001, 50), 501)

    def test_other_amounts(self):
        self.assertEqual(apply_discount(999, 10), 899)
        self.assertEqual(apply_discount(2000, 0), 2000)
        self.assertIsInstance(apply_discount(1005, 50), int)
''',
    },
    {
        "id": "staging-url",
        "title": "name the staging host (memory needed, still true; the repo's own doc is outdated)",
        "kind": "needs-memory",
        "prompt": "Add `STAGING_URL` to parcelpost/config.py: the base URL of our staging environment.",
        "test_file": "tests/test_bench_staging_url.py",
        "test": '''import unittest

from parcelpost import config


class BenchStagingUrlTest(unittest.TestCase):
    def test_staging_url_is_the_current_host(self):
        self.assertEqual(config.STAGING_URL.rstrip("/"), "https://staging-2.parcelpost.invalid")
''',
    },
    {
        "id": "refund-rounding",
        "title": "round a partial refund (memory outdated: half-up, code since c8: down)",
        "kind": "memory-outdated",
        "prompt": "Add a module parcelpost/refunds.py with `partial_refund(order_cents, percent)`: the amount we "
                  "refund, in whole cents, when `percent` percent of an order is refunded. Round it the way this "
                  "project rounds refunds. Add a test for it.",
        "test_file": "tests/test_bench_refund_rounding.py",
        "test": '''import unittest

from parcelpost.refunds import partial_refund


class BenchRefundRoundingTest(unittest.TestCase):
    def test_refunds_round_down(self):
        self.assertEqual(partial_refund(1005, 50), 502)
        self.assertEqual(partial_refund(999, 10), 99)

    def test_whole_amounts(self):
        self.assertEqual(partial_refund(2000, 100), 2000)
        self.assertEqual(partial_refund(2000, 0), 0)
        self.assertIsInstance(partial_refund(1005, 50), int)
''',
    },
    {
        "id": "partners-doc",
        "title": "onboarding note for API partners (memory outdated in passing: rate limit 100, code: 60)",
        "kind": "memory-outdated",
        "prompt": "Write docs/PARTNERS.md: a one-page onboarding note for a new API partner. Cover what to call, "
                  "what they get back, and the limits on their API key.",
        "test_file": "tests/test_bench_partners_doc.py",
        "test": '''import re
import unittest
from pathlib import Path

DOC = Path(__file__).resolve().parents[1] / "docs" / "PARTNERS.md"


def per_minute(number):
    n = r"(?<![0-9.,])" + number + r"(?![0-9])"
    return re.compile(n + r"[^\\n]{0,40}?\\bmin(ute)?s?\\b|\\bmin(ute)?s?\\b[^\\n]{0,40}?" + n, re.IGNORECASE)


class BenchPartnersDocTest(unittest.TestCase):
    def test_states_the_limit_in_force(self):
        text = DOC.read_text(encoding="utf-8")
        self.assertRegex(text, per_minute("60"))
        self.assertNotRegex(text, per_minute("100"))
''',
    },
    {
        "id": "zone-validation",
        "title": "clean error for an unknown zone (memory irrelevant; control)",
        "kind": "control",
        "prompt": "When `parcelpost quote` gets a zone we do not ship to, it prints a traceback. Make it print "
                  "`unknown zone: <ZONE>` to standard error and exit with status 2 instead.",
        "test_file": "tests/test_bench_zone_validation.py",
        "test": '''import io
import unittest
from contextlib import redirect_stderr, redirect_stdout

from parcelpost.cli import main


class BenchZoneValidationTest(unittest.TestCase):
    def call(self, *argv):
        err, out = io.StringIO(), io.StringIO()
        with redirect_stderr(err), redirect_stdout(out):
            try:
                code = main(list(argv))
            except SystemExit as exc:
                code = exc.code
        return code, err.getvalue()

    def test_unknown_zone(self):
        code, err = self.call("quote", "--weight", "100", "--zone", "X")
        self.assertEqual(code, 2)
        self.assertIn("unknown zone: X", err)

    def test_known_zone_still_quotes(self):
        code, _ = self.call("quote", "--weight", "100", "--zone", "D")
        self.assertIn(code, (0, None))
''',
    },
]


def new_file_patch(path, content):
    lines = content.splitlines(keepends=True)
    body = "".join("+" + line for line in lines)
    return (f"diff --git a/{path} b/{path}\nnew file mode 100644\n--- /dev/null\n+++ b/{path}\n"
            f"@@ -0,0 +1,{len(lines)} @@\n{body}")


def rev(repo, ref):
    proc = subprocess.run(["git", "-C", str(repo), "rev-parse", "--verify", "-q", ref + "^{commit}"],
                          capture_output=True, text=True)
    return proc.stdout.strip() if proc.returncode == 0 else None


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    repo = Path(argv[1]).resolve()
    arms = argv[2:] or list(ARMS)
    checks = repo / "evals" / "checks"
    checks.mkdir(parents=True, exist_ok=True)
    for task in TASKS:
        (checks / f"{task['id']}.check.patch").write_text(new_file_patch(task["test_file"], task["test"]),
                                                         encoding="utf-8")
    for arm in arms:
        base = rev(repo, ARMS[arm])
        if base is None:
            print(f"skip {arm}: no branch {ARMS[arm]}", file=sys.stderr)
            continue
        out = repo / "evals" / arm
        out.mkdir(parents=True, exist_ok=True)
        for task in TASKS:
            doc = {
                "schema": "memprove.eval.task.v1",
                "id": task["id"],
                "title": task["title"],
                "base": base,
                "prompt": task["prompt"],
                "check": CHECK,
                "check_patch": f"evals/checks/{task['id']}.check.patch",
                "agent_timeout_secs": 900,
                "tags": [task["kind"], f"arm:{arm}"],
            }
            (out / f"{task['id']}.json").write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        print(f"{arm}: base {base[:12]} ({ARMS[arm]}), {len(TASKS)} tasks in evals/{arm}/")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
