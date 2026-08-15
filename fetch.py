#!/usr/bin/env python3
"""List Proton Pass login metadata in one shot. Never requests secrets."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def cli_env() -> dict[str, str]:
    env = os.environ.copy()
    env["PROTON_PASS_LINUX_KEYRING"] = "dbus"
    return env


def run_cli(cli: str, args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [cli, *args],
        capture_output=True,
        text=True,
        env=cli_env(),
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


def main() -> int:
    cli = sys.argv[1] if len(sys.argv) > 1 else "pass-cli"
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


if __name__ == "__main__":
    raise SystemExit(main())
