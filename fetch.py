#!/usr/bin/env python3
"""List Proton Pass login metadata in one shot. Never requests secrets."""

from __future__ import annotations

import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import IO, Optional


DEFAULT_CLI_TIMEOUT = 60
MAX_VAULT_WORKERS = 4
LOCK_NAME = "proton-pass-fetch.lock"
ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


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
    if (
        "sqlcipher_page_cipher" in text
        or "hmac check failed" in text
        or "sqlite3codec: error decrypting" in text
        or "failed to open encrypted database" in text
        or "file is not a database" in text
        or "encryption key may not match" in text
        or "encryption key mismatch" in text
        or (
            "database" in text
            and ("decrypt" in text or "decryption" in text)
            and ("key" in text or "sqlite" in text or "codec" in text)
        )
        or (
            "database key" in text
            and any(word in text for word in ("incorrect", "invalid", "mismatch", "wrong"))
        )
    ):
        return "migration-required"
    if (
        "session is locked" in text
        or "session lock" in text
        or "unlock the session" in text
        or "pass-cli session unlock" in text
    ):
        return "locked"
    if (
        "no session" in text
        or "not logged in" in text
        or "unauthenticated" in text
        or "please login" in text
        or "login first" in text
        or "login required" in text
        or "must login" in text
        or "run pass-cli login" in text
        or "pass-cli login" in text
        or "local encryption key not found" in text
        or "forcing logout" in text
    ):
        return "unauthenticated"
    return "error"


def fail(status: str, message: str, code: int = 1) -> None:
    emit({"ok": False, "status": status, "message": message, "exitCode": code, "items": []})


def vault_id(vault: dict) -> str:
    return str(vault.get("share_id") or vault.get("shareId") or vault.get("id") or "")


def vault_name(vault: dict) -> str:
    return str(vault.get("name") or vault.get("vault_name") or vault.get("vaultName") or "")


def sanitized_vault_name(vault: dict) -> str:
    name = ANSI_ESCAPE_RE.sub("", vault_name(vault))
    name = "".join(char if char.isprintable() else " " for char in name)
    name = " ".join(name.split())
    if not name:
        name = "Unnamed vault"
    return name[:64]


def as_list(value):
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        if isinstance(value.get("items"), list):
            return value["items"]
        if isinstance(value.get("vaults"), list):
            return value["vaults"]
    return []


def list_vault_items(cli: str, vault: dict) -> dict:
    share_id = vault_id(vault)
    name = sanitized_vault_name(vault)
    if not share_id:
        return {"ok": False, "status": "error", "name": name, "shareId": "", "items": []}
    result = run_cli(
        cli,
        [
            "item",
            "list",
            f"--share-id={share_id}",
            "--filter-type",
            "login",
            "--filter-state",
            "active",
            "--output",
            "json",
        ],
    )
    if result.returncode != 0:
        detail = result.stderr or result.stdout or ""
        return {
            "ok": False,
            "status": classify(detail, result.returncode),
            "name": name,
            "shareId": share_id,
            "items": [],
        }
    try:
        parsed = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        return {"ok": False, "status": "error", "name": name, "shareId": share_id, "items": []}
    items = []
    for item in as_list(parsed):
        if isinstance(item, dict):
            item = dict(item)
            item["vault_name"] = name
            items.append(item)
    return {"ok": True, "status": "ready", "name": name, "shareId": share_id, "items": items}


def vault_failure_warning(failures: list[dict]) -> dict:
    names = [str(failure.get("name") or "Unnamed vault") for failure in failures]
    share_ids = [str(failure.get("shareId") or "") for failure in failures]
    share_ids = [share_id for share_id in share_ids if share_id]
    count = len(failures)
    noun = "vault" if count == 1 else "vaults"
    return {
        "kind": "partial-vault-failure",
        "failedVaultCount": count,
        "failedVaultNames": names,
        "failedShareIds": share_ids,
        "message": f"Could not refresh {count} {noun}: {', '.join(names)}.",
    }


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

    valid_vaults = [vault for vault in vaults if isinstance(vault, dict)]
    items: list[dict] = []
    failures: list[dict] = []
    successful_vaults = 0
    if valid_vaults:
        workers = min(MAX_VAULT_WORKERS, len(valid_vaults))
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {
                pool.submit(list_vault_items, cli, vault): vault
                for vault in valid_vaults
            }
            for future in as_completed(futures):
                vault = futures[future]
                try:
                    result = future.result()
                except Exception:
                    result = {
                        "ok": False,
                        "status": "error",
                        "name": sanitized_vault_name(vault),
                        "shareId": vault_id(vault),
                        "items": [],
                    }
                if result.get("ok"):
                    successful_vaults += 1
                    items.extend(result.get("items") or [])
                else:
                    failures.append(result)

    if failures:
        warning = vault_failure_warning(failures)
        blocking = next(
            (
                failure.get("status")
                for failure in failures
                if failure.get("status") in {"migration-required", "locked", "unauthenticated", "missing"}
            ),
            "",
        )
        if blocking:
            emit({
                "ok": False,
                "status": blocking,
                "message": warning["message"],
                "exitCode": 1,
                "items": [],
                "warning": warning,
            })
            return 0
        if successful_vaults == 0:
            emit({
                "ok": False,
                "status": "error",
                "message": warning["message"],
                "exitCode": 1,
                "items": [],
                "warning": warning,
            })
            return 0
        emit({
            "ok": True,
            "status": "partial",
            "email": email,
            "items": items,
            "warning": warning,
        })
        return 0

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
