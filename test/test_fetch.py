#!/usr/bin/env python3
"""Unit tests for fetch.py lock, timeout, and vault failure behavior."""

from __future__ import annotations

import fcntl
import io
import json
import os
import stat
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
        self._old_home = os.environ.get("HOME")
        self._old_xdg = os.environ.get("XDG_CACHE_HOME")
        os.environ["HOME"] = self._tmp.name
        # Ensure XDG does not divert the lock/cache root away from PassService.
        os.environ["XDG_CACHE_HOME"] = os.path.join(self._tmp.name, "xdg-cache-should-be-ignored")
        self.addCleanup(self._restore_env)

    def _restore_env(self) -> None:
        if self._old_home is None:
            os.environ.pop("HOME", None)
        else:
            os.environ["HOME"] = self._old_home
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
    def test_lock_path_matches_home_cache_omarchy(self) -> None:
        expected = os.path.join(self._tmp.name, ".cache", "omarchy", "proton-pass-fetch.lock")
        self.assertEqual(fetch.lock_file_path(), expected)
        self.assertEqual(
            fetch.cache_dir(),
            os.path.join(self._tmp.name, ".cache", "omarchy"),
        )
        self.assertNotIn("xdg-cache-should-be-ignored", fetch.lock_file_path())

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

        lock_path = fetch.lock_file_path()
        with open(lock_path, "a+", encoding="utf-8") as fd:
            fcntl.flock(fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(fd.fileno(), fcntl.LOCK_UN)

    def test_lock_file_created_mode_0600(self) -> None:
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
                code, payload = self._capture_main()

        self.assertEqual(code, 0)
        self.assertTrue(payload.get("ok"))
        mode = stat.S_IMODE(os.stat(fetch.lock_file_path()).st_mode)
        self.assertEqual(mode, 0o600)

    def test_wrong_owner_fails_safely_without_cli(self) -> None:
        lock_path = fetch.lock_file_path()
        os.makedirs(os.path.dirname(lock_path), mode=0o700, exist_ok=True)
        with open(lock_path, "w", encoding="utf-8"):
            pass

        real_fstat = os.fstat

        def fake_fstat(fd):
            st = real_fstat(fd)
            return os.stat_result(
                (st.st_mode, st.st_ino, st.st_dev, st.st_nlink, st.st_uid + 1, st.st_gid,
                 st.st_size, st.st_atime, st.st_mtime, st.st_ctime)
            )

        with mock.patch.object(os, "fstat", side_effect=fake_fstat):
            with mock.patch.object(fetch, "run_cli") as run_cli:
                with mock.patch.object(fetch.shutil, "which", return_value="/usr/bin/pass-cli"):
                    code, payload = self._capture_main()

        self.assertEqual(code, 0)
        self.assertEqual(payload.get("ok"), False)
        self.assertEqual(payload.get("status"), "error")
        self.assertNotEqual(payload.get("status"), "busy")
        self.assertEqual(payload.get("items"), [])
        run_cli.assert_not_called()

    def test_symlink_lock_path_fails_safely(self) -> None:
        if not hasattr(os, "O_NOFOLLOW"):
            self.skipTest("O_NOFOLLOW unavailable")
        lock_path = fetch.lock_file_path()
        os.makedirs(os.path.dirname(lock_path), mode=0o700, exist_ok=True)
        target = os.path.join(self._tmp.name, "evil-target")
        with open(target, "w", encoding="utf-8") as fd:
            fd.write("x")
        os.symlink(target, lock_path)

        with mock.patch.object(fetch, "run_cli") as run_cli:
            with mock.patch.object(fetch.shutil, "which", return_value="/usr/bin/pass-cli"):
                code, payload = self._capture_main()

        self.assertEqual(code, 0)
        self.assertEqual(payload.get("ok"), False)
        self.assertEqual(payload.get("status"), "error")
        self.assertEqual(payload.get("items"), [])
        run_cli.assert_not_called()


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

    def test_every_cli_path_has_a_finite_default_timeout(self) -> None:
        vaults = [
            {"share_id": "share-1", "name": "Personal"},
            {"share_id": "share-2", "name": "Work"},
        ]

        def fake_subprocess_run(command, **kwargs):
            if command[1:2] == ["info"]:
                stdout = '{"email":"a@b.c"}'
            elif command[1:3] == ["vault", "list"]:
                stdout = json.dumps(vaults)
            elif command[1:3] == ["item", "list"]:
                stdout = '{"items":[]}'
            else:
                raise AssertionError(f"unexpected command: {command}")
            return subprocess.CompletedProcess(command, 0, stdout, "")

        buf = io.StringIO()
        with mock.patch.object(fetch.shutil, "which", return_value="/usr/bin/pass-cli"):
            with mock.patch.object(subprocess, "run", side_effect=fake_subprocess_run) as run:
                with mock.patch.object(sys, "stdout", buf):
                    fetch.scan("pass-cli")

        self.assertGreaterEqual(run.call_count, 4)
        for call in run.call_args_list:
            timeout = call.kwargs.get("timeout")
            self.assertIsNotNone(timeout)
            self.assertGreater(timeout, 0)


class ClassificationTests(unittest.TestCase):
    def test_sqlcipher_and_database_key_failures_require_migration(self) -> None:
        messages = [
            "sqlcipher_page_cipher: hmac check failed for pgno=1",
            "Failed to open encrypted database: file is not a database. The encryption key may not match",
            "sqlite3Codec: error decrypting page 1 data",
            "Database decryption failed because the database key is incorrect",
        ]
        for message in messages:
            with self.subTest(message=message):
                self.assertEqual(fetch.classify(message, 1), "migration-required")

    def test_generic_login_network_and_password_text_are_not_session_errors(self) -> None:
        messages = [
            "Could not load login item",
            "Network login request failed",
            "Password authentication failed",
            "Unauthorized network response",
        ]
        for message in messages:
            with self.subTest(message=message):
                self.assertEqual(fetch.classify(message, 1), "error")

    def test_precise_session_messages_remain_unauthenticated(self) -> None:
        for message in ["Please login first", "There is no session", "Not logged in"]:
            with self.subTest(message=message):
                self.assertEqual(fetch.classify(message, 1), "unauthenticated")


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
        self.assertEqual(payload.get("status"), "partial")
        self.assertEqual(payload.get("email"), "a@b.c")
        items = payload.get("items") or []
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["title"], "GitHub")
        self.assertEqual(items[0]["vault_name"], "Personal")
        warning = payload.get("warning") or {}
        self.assertEqual(warning.get("kind"), "partial-vault-failure")
        self.assertEqual(warning.get("failedVaultCount"), 1)
        self.assertEqual(warning.get("failedVaultNames"), ["Broken"])
        self.assertEqual(warning.get("failedShareIds"), ["share-bad"])
        self.assertIn("Broken", warning.get("message", ""))
        self.assertNotIn("vault unavailable", json.dumps(warning))
        dumped = json.dumps(payload)
        self.assertNotIn("password", dumped)
        self.assertNotIn("--show-secrets", dumped)

    def test_vault_timeout_is_a_sanitized_partial_warning(self) -> None:
        info = subprocess.CompletedProcess(["pass-cli", "info"], 0, '{"email":"a@b.c"}', "")
        vaults = subprocess.CompletedProcess(
            ["pass-cli", "vault", "list"],
            0,
            json.dumps([
                {"share_id": "ok", "name": "Personal"},
                {"share_id": "slow", "name": "Slow\nVault\u001b[31m"},
            ]),
            "",
        )

        def fake_run(cli: str, args: list[str], timeout=None):
            if args[:1] == ["info"]:
                return info
            if args[:2] == ["vault", "list"]:
                return vaults
            share = args[args.index("--share-id") + 1]
            if share == "ok":
                return subprocess.CompletedProcess(
                    args, 0, json.dumps({"items": [_login_item("item-1", "ok", "GitHub")]}), ""
                )
            return subprocess.CompletedProcess(args, 124, "", "timeout waiting for pass-cli: internal detail")

        with mock.patch.object(fetch, "run_cli", side_effect=fake_run):
            with mock.patch.object(fetch.shutil, "which", return_value="/usr/bin/pass-cli"):
                _, payload = self._capture_main()

        self.assertTrue(payload.get("ok"))
        self.assertEqual(payload.get("status"), "partial")
        warning = payload.get("warning") or {}
        self.assertEqual(warning.get("failedVaultCount"), 1)
        self.assertEqual(warning.get("failedVaultNames"), ["Slow Vault"])
        self.assertNotIn("internal detail", json.dumps(payload))

    def test_worker_count_is_capped_at_four_and_vault_count(self) -> None:
        vaults = [{"share_id": f"share-{idx}", "name": f"Vault {idx}"} for idx in range(7)]
        info = subprocess.CompletedProcess(["pass-cli", "info"], 0, '{"email":"a@b.c"}', "")
        vault_result = subprocess.CompletedProcess(
            ["pass-cli", "vault", "list"], 0, json.dumps(vaults), ""
        )
        real_executor = fetch.ThreadPoolExecutor
        seen_workers = []

        def recording_executor(*args, **kwargs):
            seen_workers.append(kwargs.get("max_workers", args[0] if args else None))
            return real_executor(*args, **kwargs)

        def fake_run(cli: str, args: list[str], timeout=None):
            if args[:1] == ["info"]:
                return info
            if args[:2] == ["vault", "list"]:
                return vault_result
            return subprocess.CompletedProcess(args, 0, '{"items":[]}', "")

        with mock.patch.object(fetch, "ThreadPoolExecutor", side_effect=recording_executor):
            with mock.patch.object(fetch, "run_cli", side_effect=fake_run):
                with mock.patch.object(fetch.shutil, "which", return_value="/usr/bin/pass-cli"):
                    _, payload = self._capture_main()

        self.assertTrue(payload.get("ok"))
        self.assertEqual(seen_workers, [4])

    def test_all_vault_failures_are_not_reported_as_success(self) -> None:
        info = subprocess.CompletedProcess(["pass-cli", "info"], 0, '{"email":"a@b.c"}', "")
        vaults = subprocess.CompletedProcess(
            ["pass-cli", "vault", "list"],
            0,
            json.dumps([{"share_id": "bad", "name": "Broken"}]),
            "",
        )

        def fake_run(cli: str, args: list[str], timeout=None):
            if args[:1] == ["info"]:
                return info
            if args[:2] == ["vault", "list"]:
                return vaults
            return subprocess.CompletedProcess(args, 1, "", "private backend detail")

        with mock.patch.object(fetch, "run_cli", side_effect=fake_run):
            with mock.patch.object(fetch.shutil, "which", return_value="/usr/bin/pass-cli"):
                _, payload = self._capture_main()

        self.assertFalse(payload.get("ok"))
        self.assertEqual(payload.get("status"), "error")
        self.assertEqual((payload.get("warning") or {}).get("failedVaultNames"), ["Broken"])
        self.assertNotIn("private backend detail", json.dumps(payload))


if __name__ == "__main__":
    unittest.main()
