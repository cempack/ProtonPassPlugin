#!/usr/bin/env python3
"""Stream live 2FA codes for the Proton Pass list while the panel is open.

Reads each vault once with `--show-secrets`, keeps only the TOTP seeds in this
process's memory, and prints one JSON line of codes whenever any code rolls over:

    {"ok":true,"now":1700000000,"codes":{"<shareId>/<itemId>":{"code":"123456","period":30,"expires":1700000010}}}

Seeds are never printed. The feed exits when stdin closes (the panel stopped it)
or after MAX_LIFETIME seconds, whichever comes first.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import select
import struct
import sys
import time
from typing import Optional
from urllib.parse import parse_qs, unquote, urlparse

import fetch

MAX_LIFETIME = 600
ALGORITHMS = {"SHA1": hashlib.sha1, "SHA256": hashlib.sha256, "SHA512": hashlib.sha512}


class Totp:
    __slots__ = ("secret", "digits", "period", "digest")

    def __init__(self, secret: bytes, digits: int = 6, period: int = 30, algorithm: str = "SHA1") -> None:
        self.secret = secret
        self.digits = digits
        self.period = period
        self.digest = ALGORITHMS[algorithm]

    def code(self, now: float) -> str:
        counter = int(now // self.period)
        mac = hmac.new(self.secret, struct.pack(">Q", counter), self.digest).digest()
        offset = mac[-1] & 0x0F
        value = struct.unpack(">I", mac[offset:offset + 4])[0] & 0x7FFFFFFF
        return str(value % (10 ** self.digits)).zfill(self.digits)

    def expires(self, now: float) -> int:
        return (int(now // self.period) + 1) * self.period


def _b32(secret: str) -> Optional[bytes]:
    cleaned = "".join(secret.split()).replace("-", "").upper()
    if not cleaned:
        return None
    try:
        return base64.b32decode(cleaned + "=" * (-len(cleaned) % 8))
    except ValueError:  # binascii.Error is a ValueError
        return None


def parse_totp(uri: str) -> Optional[Totp]:
    """Accept an otpauth:// URI or a bare base32 seed. Unsupported variants return None."""
    text = (uri or "").strip()
    if not text:
        return None
    if not text.lower().startswith("otpauth://"):
        secret = _b32(text)
        return Totp(secret) if secret else None
    parsed = urlparse(text)
    if parsed.netloc.lower() != "totp":
        return None
    query = {key.lower(): values[-1] for key, values in parse_qs(parsed.query).items() if values}
    if query.get("encoder"):
        return None  # Steam Guard and other non-RFC encoders
    secret = _b32(unquote(query.get("secret", "")))
    if not secret:
        return None
    try:
        digits = int(query.get("digits", 6))
        period = int(query.get("period", 30))
    except ValueError:
        return None
    algorithm = query.get("algorithm", "SHA1").upper()
    if algorithm not in ALGORITHMS or not 6 <= digits <= 8 or not 1 <= period <= 300:
        return None
    return Totp(secret, digits, period, algorithm)


def load_seeds(cli: str, share_ids: list[str]) -> tuple[dict[str, Totp], str]:
    seeds: dict[str, Totp] = {}
    for share_id in share_ids:
        result = fetch.run_cli(
            cli,
            ["item", "list", f"--share-id={share_id}", "--filter-state", "active", "--output", "json", "--show-secrets"],
        )
        if result.returncode != 0:
            return {}, fetch.classify(result.stderr or result.stdout or "", result.returncode)
        try:
            items = fetch.as_list(json.loads(result.stdout or "[]"))
        except json.JSONDecodeError:
            return {}, "error"
        del result
        for item in items:
            _, payload = fetch._tagged(item) if isinstance(item, dict) else ("", {})
            totp = parse_totp(payload.get("totp_uri") or "") if payload else None
            item_id = item.get("id") if isinstance(item, dict) else None
            if totp and isinstance(item_id, str) and item_id:
                seeds[f"{share_id}/{item_id}"] = totp
        del items
    return seeds, "ready"


def snapshot(seeds: dict[str, Totp], now: float) -> dict:
    return {
        key: {"code": totp.code(now), "period": totp.period, "expires": totp.expires(now)}
        for key, totp in seeds.items()
    }


def stdin_closed(timeout: float) -> bool:
    try:
        readable, _, _ = select.select([sys.stdin], [], [], timeout)
    except (OSError, ValueError):
        return True
    if not readable:
        return False
    try:
        return os.read(sys.stdin.fileno(), 4096) == b""
    except OSError:
        return True


def main(argv: list[str]) -> int:
    cli = argv[1] if len(argv) > 1 else "pass-cli"
    share_ids = [share_id for share_id in argv[2:] if share_id]
    seeds, status = load_seeds(cli, share_ids)
    if status != "ready":
        fetch.emit({"ok": False, "status": status, "codes": {}})
        return 0
    started = time.time()
    next_expiry = 0.0
    while time.time() - started < MAX_LIFETIME:
        now = time.time()
        if now >= next_expiry:
            codes = snapshot(seeds, now)
            fetch.emit({"ok": True, "status": "ready", "now": int(now), "codes": codes})
            next_expiry = min((entry["expires"] for entry in codes.values()), default=now + MAX_LIFETIME)
        if stdin_closed(max(0.05, min(1.0, next_expiry - time.time()))):
            break
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
