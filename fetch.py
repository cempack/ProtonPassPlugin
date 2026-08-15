#!/usr/bin/env python3
"""List Proton Pass login metadata in one shot. Never requests secrets."""

from __future__ import annotations

import fcntl
import json
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import IO, Optional


DEFAULT_CLI_TIMEOUT = 60
LOCK_NAME = "proton-pass-fetch.lock"


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def cache_dir() -> str:
    home = os.environ.get("HOME") or os.path.expanduser("~")
    return os.path.join(home, ".cache", "omarchy")


def lock_file_path() -> str:
    return os.path.join(cache_dir(), LOCK_NAME)


class LockOpenError(Exception):
    """Fetch lock could not be opened safely."""


def cli_env() -> dict[str, str]:
    env = os.environ.copy()
    env["PROTON_PASS_LINUX_KEYRING"] = "dbus"
    return env


def _timeout_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, (bytes, bytearray)):
        return value.decode("utf-8", "replace")
    return ""


def run_cli(cli: str, args: list[str], timeout: Optional[float] = None) -> subprocess.CompletedProcess[str]:
    limit = DEFAULT_CLI_TIMEOUT if timeout is None else timeout
    try:
        return subprocess.run(
            [cli, *args],
            capture_output=True,
            text=True,
            env=cli_env(),
            timeout=limit,
        )
    except subprocess.TimeoutExpired as exc:
        return subprocess.CompletedProcess(
            [cli, *args],
            returncode=124,
            stdout=_timeout_text(exc.stdout),
            stderr=_timeout_text(exc.stderr) or "timeout waiting for pass-cli",
        )


def classify(stderr: str, code: int) -> str:
    text = (stderr or "").lower()
    if code == 127 or "command not found" in text or "no such file" in text:
        return "missing"
    if "locked" in text or "session lock" in text or "unlock" in text:
        return "locked"
    if (
        "no session" in text
        or "login" in text
        or "not logged" in text
        or "unauthenticated" in text
        or "unauthorized" in text
    ):
        return "unauthenticated"
    return "error"


def fail(status: str, message: str, code: int = 1) -> None:
    emit({"ok": False, "status": status, "message": message, "exitCode": code, "items": []})


def vault_id(vault: dict) -> str:
    return str(vault.get("share_id") or vault.get("shareId") or vault.get("id") or "")


def vault_name(vault: dict) -> str:
    return str(vault.get("name") or vault.get("vault_name") or vault.get("vaultName") or "")


def as_list(value):
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        if isinstance(value.get("items"), list):
            return value["items"]
        if isinstance(value.get("vaults"), list):
            return value["vaults"]
    return []


def list_vault_items(cli: str, vault: dict) -> list[dict]:
    share_id = vault_id(vault)
    if not share_id:
        return []
    result = run_cli(
        cli,
        [
            "item",
            "list",
            "--share-id",
            share_id,
            "--filter-type",
            "login",
            "--filter-state",
            "active",
            "--output",
            "json",
        ],
    )
    if result.returncode != 0:
        return []
    try:
        parsed = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        return []
    name = vault_name(vault)
    items = []
    for item in as_list(parsed):
        if isinstance(item, dict):
            item = dict(item)
            item["vault_name"] = name
            items.append(item)
    return items


def try_acquire_lock() -> Optional[IO[str]]:
    """Acquire a non-blocking exclusive lock.

    Returns an open file object on success, None when another process holds the
    lock (busy). Raises LockOpenError when the lock path is unsafe.
    """
    path = lock_file_path()
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)

    flags = os.O_RDWR | os.O_CREAT
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    if nofollow:
        flags |= nofollow

    raw_fd = -1
    try:
        raw_fd = os.open(path, flags, 0o600)
    except OSError as exc:
        raise LockOpenError("Could not open fetch lock") from exc

    try:
        st = os.fstat(raw_fd)
        if st.st_uid != os.getuid():
            raise LockOpenError("Fetch lock owned by another user")
        os.fchmod(raw_fd, 0o600)
        fd = os.fdopen(raw_fd, "r+", encoding="utf-8")
        raw_fd = -1
        try:
            fcntl.flock(fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            fd.close()
            return None
        return fd
    except LockOpenError:
        if raw_fd >= 0:
            os.close(raw_fd)
        raise
    except Exception:
        if raw_fd >= 0:
            os.close(raw_fd)
        raise


def release_lock(fd: Optional[IO[str]]) -> None:
    if fd is None:
        return
    try:
        fcntl.flock(fd.fileno(), fcntl.LOCK_UN)
    finally:
        fd.close()


def scan(cli: str) -> int:
    if shutil.which(cli) is None and not os.path.isfile(cli):
        fail("missing", "pass-cli is not installed", 127)
        return 0

    info = run_cli(cli, ["info", "--output", "json"])
    if info.returncode != 0:
        stderr = (info.stderr or info.stdout or "").strip()
        fail(classify(stderr, info.returncode), stderr, info.returncode)
        return 0

    try:
        info_json = json.loads(info.stdout or "{}")
    except json.JSONDecodeError:
        info_json = {}
    email = str(info_json.get("email") or info_json.get("username") or "")

    vaults_result = run_cli(cli, ["vault", "list", "--output", "json"])
    if vaults_result.returncode != 0:
        stderr = (vaults_result.stderr or vaults_result.stdout or "").strip()
        fail(classify(stderr, vaults_result.returncode), stderr, vaults_result.returncode)
        return 0

    try:
        vaults = as_list(json.loads(vaults_result.stdout or "[]"))
    except json.JSONDecodeError:
        fail("error", "Could not read vault list")
        return 0

    items: list[dict] = []
    workers = min(8, max(1, len(vaults)))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(list_vault_items, cli, vault) for vault in vaults if isinstance(vault, dict)]
        for future in as_completed(futures):
            items.extend(future.result())

    emit({"ok": True, "status": "ready", "email": email, "items": items})
    return 0


def main() -> int:
    try:
        lock_fd = try_acquire_lock()
    except LockOpenError as exc:
        fail("error", str(exc) or "Could not open fetch lock")
        return 0
    if lock_fd is None:
        emit({"ok": False, "status": "busy", "message": "", "items": []})
        return 0
    try:
        cli = sys.argv[1] if len(sys.argv) > 1 else "pass-cli"
        return scan(cli)
    finally:
        release_lock(lock_fd)


if __name__ == "__main__":
    raise SystemExit(main())
