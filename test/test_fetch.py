#!/usr/bin/env python3
"""Unit tests for fetch.py lock, timeout, and vault failure behavior."""

from __future__ import annotations

import fcntl
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import fetch  # noqa: E402


def _login_item(item_id: str, share_id: str, title: str) -> dict:
    return {
        "id": item_id,
        "share_id": share_id,
        "title": title,
        "item_type": "login",
        "state": "Active",
    }


class FetchTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self._old_xdg = os.environ.get("XDG_CACHE_HOME")
        os.environ["XDG_CACHE_HOME"] = self._tmp.name
        self.addCleanup(self._restore_xdg)

    def _restore_xdg(self) -> None:
        if self._old_xdg is None:
            os.environ.pop("XDG_CACHE_HOME", None)
        else:
            os.environ["XDG_CACHE_HOME"] = self._old_xdg

    def _capture_main(self, argv: list[str] | None = None) -> tuple[int, dict]:
        buf = io.StringIO()
        with mock.patch.object(sys, "argv", argv or ["fetch.py", "pass-cli"]):
            with mock.patch.object(sys, "stdout", buf):
                code = fetch.main()
        line = (buf.getvalue().strip().splitlines() or [""])[-1]
        payload = json.loads(line) if line else {}
        return code, payload


class LockTests(FetchTestCase):
    def test_contending_process_returns_busy_without_cli(self) -> None:
        lock_path = fetch.lock_file_path()
        os.makedirs(os.path.dirname(lock_path), exist_ok=True)
        holder = open(lock_path, "a+", encoding="utf-8")
        self.addCleanup(holder.close)
        fcntl.flock(holder.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

        with mock.patch.object(fetch, "run_cli") as run_cli:
            with mock.patch.object(fetch.shutil, "which", return_value="/usr/bin/pass-cli"):
                code, payload = self._capture_main()

        self.assertEqual(code, 0)
        self.assertEqual(payload.get("ok"), False)
        self.assertEqual(payload.get("status"), "busy")
        self.assertEqual(payload.get("items"), [])
        self.assertNotIn("password", json.dumps(payload))
        run_cli.assert_not_called()

    def test_lock_releases_so_second_run_can_acquire(self) -> None:
        info = subprocess.CompletedProcess(
            ["pass-cli", "info"], 0, '{"email":"a@b.c"}', ""
        )
        vaults = subprocess.CompletedProcess(
            ["pass-cli", "vault", "list"], 0, "[]", ""
        )

        def fake_run(cli: str, args: list[str], timeout=None):
            if args[:1] == ["info"]:
                return info
            if args[:2] == ["vault", "list"]:
                return vaults
            raise AssertionError(f"unexpected args: {args}")

        with mock.patch.object(fetch, "run_cli", side_effect=fake_run):
            with mock.patch.object(fetch.shutil, "which", return_value="/usr/bin/pass-cli"):
                code1, payload1 = self._capture_main()
                code2, payload2 = self._capture_main()

        self.assertEqual(code1, 0)
        self.assertEqual(payload1.get("ok"), True)
        self.assertEqual(code2, 0)
        self.assertEqual(payload2.get("ok"), True)

        # After release, a fresh exclusive non-blocking lock must succeed.
        lock_path = fetch.lock_file_path()
        with open(lock_path, "a+", encoding="utf-8") as fd:
            fcntl.flock(fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(fd.fileno(), fcntl.LOCK_UN)


class TimeoutTests(FetchTestCase):
    def test_run_cli_passes_timeout_and_maps_expiry(self) -> None:
        expired = subprocess.TimeoutExpired(cmd=["pass-cli", "info"], timeout=12)

        with mock.patch("subprocess.run", side_effect=expired) as run:
            result = fetch.run_cli("pass-cli", ["info", "--output", "json"], timeout=12)

        run.assert_called_once()
        self.assertEqual(run.call_args.kwargs.get("timeout"), 12)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("timeout", (result.stderr or "").lower())

    def test_info_timeout_returns_structured_error(self) -> None:
        timed_out = subprocess.CompletedProcess(
            ["pass-cli", "info"], 1, "", "timeout waiting for pass-cli"
        )

        with mock.patch.object(fetch, "run_cli", return_value=timed_out):
            with mock.patch.object(fetch.shutil, "which", return_value="/usr/bin/pass-cli"):
                code, payload = self._capture_main()

        self.assertEqual(code, 0)
        self.assertEqual(payload.get("ok"), False)
        self.assertEqual(payload.get("status"), "error")
        self.assertNotIn("password", json.dumps(payload).lower())


class PartialVaultTests(FetchTestCase):
    def test_one_vault_failure_keeps_other_vault_items(self) -> None:
        info = subprocess.CompletedProcess(
            ["pass-cli", "info"], 0, '{"email":"a@b.c"}', ""
        )
        vaults = subprocess.CompletedProcess(
            ["pass-cli", "vault", "list"],
            0,
            json.dumps(
                [
                    {"share_id": "share-ok", "name": "Personal"},
                    {"share_id": "share-bad", "name": "Broken"},
                ]
            ),
            "",
        )
        ok_items = subprocess.CompletedProcess(
            ["pass-cli", "item", "list"],
            0,
            json.dumps({"items": [_login_item("item-1", "share-ok", "GitHub")]}),
            "",
        )
        bad_items = subprocess.CompletedProcess(
            ["pass-cli", "item", "list"], 1, "", "vault unavailable"
        )

        def fake_run(cli: str, args: list[str], timeout=None):
            if args[:1] == ["info"]:
                return info
            if args[:2] == ["vault", "list"]:
                return vaults
            if args[:2] == ["item", "list"]:
                share = args[args.index("--share-id") + 1]
                if share == "share-ok":
                    return ok_items
                if share == "share-bad":
                    return bad_items
            raise AssertionError(f"unexpected args: {args}")

        with mock.patch.object(fetch, "run_cli", side_effect=fake_run):
            with mock.patch.object(fetch.shutil, "which", return_value="/usr/bin/pass-cli"):
                code, payload = self._capture_main()

        self.assertEqual(code, 0)
        self.assertEqual(payload.get("ok"), True)
        self.assertEqual(payload.get("email"), "a@b.c")
        items = payload.get("items") or []
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["title"], "GitHub")
        self.assertEqual(items[0]["vault_name"], "Personal")
        dumped = json.dumps(payload)
        self.assertNotIn("password", dumped)
        self.assertNotIn("--show-secrets", dumped)


if __name__ == "__main__":
    unittest.main()
