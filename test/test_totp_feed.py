#!/usr/bin/env python3
from __future__ import annotations

import io
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import fetch  # noqa: E402
import totp_feed  # noqa: E402

RFC_SEED = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"  # base32("12345678901234567890")


class RfcVectorTests(unittest.TestCase):
    def test_sha1_vectors(self) -> None:
        totp = totp_feed.parse_totp(f"otpauth://totp/x?secret={RFC_SEED}&digits=8")
        vectors = {59: "94287082", 1111111109: "07081804", 1234567890: "89005924", 20000000000: "65353130"}
        for now, code in vectors.items():
            self.assertEqual(totp.code(now), code)

    def test_sha256_vector(self) -> None:
        seed = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA"
        totp = totp_feed.parse_totp(f"otpauth://totp/x?secret={seed}&digits=8&algorithm=SHA256")
        self.assertEqual(totp.code(59), "46119246")

    def test_expiry_is_the_next_window(self) -> None:
        totp = totp_feed.parse_totp(RFC_SEED)
        self.assertEqual(totp.expires(59), 60)
        self.assertEqual(totp.expires(60), 90)


class ParseTests(unittest.TestCase):
    def test_bare_seed_with_spaces_and_lowercase(self) -> None:
        self.assertIsNotNone(totp_feed.parse_totp("gezd gnbv gy3t qojq"))

    def test_rejects_unsupported_variants(self) -> None:
        for uri in (
            "",
            "otpauth://hotp/x?secret=GEZDGNBV",
            "otpauth://totp/x?secret=GEZDGNBV&encoder=steam",
            "otpauth://totp/x?secret=GEZDGNBV&algorithm=MD5",
            "otpauth://totp/x?secret=GEZDGNBV&digits=12",
            "otpauth://totp/x?secret=!!!",
        ):
            self.assertIsNone(totp_feed.parse_totp(uri), uri)


class FeedTests(unittest.TestCase):
    def _listing(self, *args, **kwargs):
        args = args[1]
        items = [
            {"id": "a", "content": {"content": {"Login": {"totp_uri": f"otpauth://totp/x?secret={RFC_SEED}", "password": "PW"}}}},
            {"id": "b", "content": {"content": {"Login": {"totp_uri": "", "password": "PW"}}}},
            {"id": "c", "content": {"content": {"Note": {}}}},
        ]
        return subprocess.CompletedProcess(args, 0, json.dumps({"items": items}), "")

    def test_only_items_with_seeds_are_streamed_and_seeds_never_printed(self) -> None:
        with mock.patch.object(fetch, "run_cli", side_effect=self._listing):
            seeds, status = totp_feed.load_seeds("pass-cli", ["s1"])
        self.assertEqual(status, "ready")
        self.assertEqual(list(seeds), ["s1/a"])
        buf = io.StringIO()
        with mock.patch.object(fetch, "run_cli", side_effect=self._listing), \
                mock.patch.object(totp_feed, "stdin_closed", return_value=True), \
                mock.patch.object(sys, "stdout", buf):
            totp_feed.main(["totp_feed.py", "pass-cli", "s1"])
        line = json.loads(buf.getvalue().splitlines()[0])
        self.assertTrue(line["ok"])
        self.assertEqual(set(line["codes"]), {"s1/a"})
        self.assertRegex(line["codes"]["s1/a"]["code"], r"^\d{6}$")
        self.assertNotIn(RFC_SEED, buf.getvalue())
        self.assertNotIn("PW", buf.getvalue())

    def test_session_failure_is_reported_without_codes(self) -> None:
        failed = subprocess.CompletedProcess([], 1, "", "Run pass-cli login")
        buf = io.StringIO()
        with mock.patch.object(fetch, "run_cli", return_value=failed), mock.patch.object(sys, "stdout", buf):
            totp_feed.main(["totp_feed.py", "pass-cli", "s1"])
        line = json.loads(buf.getvalue())
        self.assertFalse(line["ok"])
        self.assertEqual(line["status"], "unauthenticated")


if __name__ == "__main__":
    unittest.main()
