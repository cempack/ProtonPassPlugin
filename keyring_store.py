"""Repair Omarchy's unlocked GNOME keyring file. Never print secret values."""

from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

OMARCHY_LABEL = "Default keyring"
GNOME_CREATE_LABEL = "Default Keyring"
ITEM_FIELD = re.compile(r"^(item-type|display-name|secret|mtime|ctime)=")
PEM_BLOCK = re.compile(r"-----BEGIN [^-]+-----.*?-----END [^-]+-----", re.S)


def keyring_dir(home: str | None = None) -> Path:
    root = home if home is not None else os.environ.get("HOME") or os.path.expanduser("~")
    return Path(root) / ".local/share/keyrings"


def keyring_path(home: str | None = None) -> Path:
    return keyring_dir(home) / "Default_keyring.keyring"


def default_pointer_path(home: str | None = None) -> Path:
    return keyring_dir(home) / "default"


def empty_keyring_text() -> str:
    return (
        "[keyring]\n"
        f"display-name={OMARCHY_LABEL}\n"
        f"ctime={int(time.time())}\n"
        "mtime=0\n"
        "lock-on-idle=false\n"
        "lock-after=false\n"
    )


def has_multiline_secrets(text: str) -> bool:
    in_secret = False
    for line in text.splitlines():
        if line.startswith("[") and line.endswith("]"):
            in_secret = False
            continue
        if line.startswith("secret="):
            in_secret = True
            continue
        if in_secret:
            if line.startswith("mtime=") or line.startswith("ctime="):
                in_secret = False
            else:
                return True
    return False


def parse_keyring(text: str) -> list[dict]:
    items: dict[str, dict] = {}
    current_id: str | None = None
    mode: str | None = None
    attr: dict[str, str] = {}

    def ensure_item(item_id: str) -> dict:
        return items.setdefault(item_id, {"label": None, "secret": None, "attrs": {}, "mtime": "0", "ctime": "0"})

    for line in text.splitlines():
        if line.startswith("[") and line.endswith("]"):
            name = line[1:-1]
            if name == "keyring":
                current_id = None
                mode = None
                continue
            if ":attribute" in name:
                current_id = name.split(":", 1)[0]
                ensure_item(current_id)
                mode = "attr"
                attr = {}
                continue
            current_id = name
            ensure_item(current_id)
            mode = "item"
            continue
        if current_id is None:
            continue
        item = items[current_id]
        if mode == "item":
            if line.startswith("display-name="):
                item["label"] = line.split("=", 1)[1]
            elif line.startswith("mtime="):
                item["mtime"] = line.split("=", 1)[1]
            elif line.startswith("ctime="):
                item["ctime"] = line.split("=", 1)[1]
            elif line.startswith("secret="):
                item["secret"] = line.split("=", 1)[1]
                mode = "secret_cont"
        elif mode == "secret_cont":
            if ITEM_FIELD.match(line) or (line.startswith("[") and line.endswith("]")):
                if line.startswith("[") and line.endswith("]"):
                    name = line[1:-1]
                    if ":attribute" in name:
                        current_id = name.split(":", 1)[0]
                        ensure_item(current_id)
                        mode = "attr"
                        attr = {}
                    else:
                        current_id = name
                        ensure_item(current_id)
                        mode = "item"
                elif line.startswith("mtime="):
                    item["mtime"] = line.split("=", 1)[1]
                    mode = "item"
                elif line.startswith("ctime="):
                    item["ctime"] = line.split("=", 1)[1]
                    mode = "item"
                else:
                    mode = "item"
                continue
            item["secret"] = (item["secret"] or "") + "\n" + line
        elif mode == "attr":
            if line.startswith("name="):
                attr["name"] = line.split("=", 1)[1]
            elif line.startswith("value="):
                attr["value"] = line.split("=", 1)[1]
                if "name" in attr:
                    item["attrs"][attr["name"]] = attr.get("value", "")
                attr = {}
    return [item for item in items.values() if item["label"] and item["secret"] is not None]


def durable_secret(label: str, secret: str) -> str:
    if not secret or ("\n" not in secret and "\r" not in secret):
        return secret
    candidate = secret.replace("\r\n", "\n").replace("\r", "\n")
    escaped_pem = PEM_BLOCK.sub(lambda match: match.group(0).replace("\n", "\\n"), candidate)
    try:
        payload = json.loads(escaped_pem.replace("\n", "\\n"))
        dumped = json.dumps(payload, separators=(",", ":"))
    except json.JSONDecodeError:
        dumped = candidate.replace("\n", "\\n")
    if "\n" in dumped or "\r" in dumped:
        raise ValueError(f"could not flatten secret for {label!r}")
    return dumped


def render_keyring(items: list[dict]) -> str:
    lines = [empty_keyring_text().rstrip(), ""]
    for index, item in enumerate(items, start=1):
        secret = durable_secret(item["label"], item["secret"])
        lines.extend(
            [
                f"[{index}]",
                "item-type=0",
                f"display-name={item['label']}",
                f"secret={secret}",
                f"mtime={item.get('mtime') or '0'}",
                f"ctime={item.get('ctime') or '0'}",
                "",
            ]
        )
        attrs = item.get("attrs") or {}
        for attr_index, (name, value) in enumerate(attrs.items()):
            lines.extend(
                [
                    f"[{index}:attribute{attr_index}]",
                    f"name={name}",
                    "type=string",
                    f"value={value}",
                    "",
                ]
            )
    return "\n".join(lines).rstrip() + "\n"


def write_empty_keyring(path: Path) -> None:
    path.parent.mkdir(mode=0o700, exist_ok=True)
    path.write_text(empty_keyring_text())
    path.chmod(0o600)
    pointer = path.parent / "default"
    if not pointer.exists():
        pointer.write_text("Default_keyring\n")
        pointer.chmod(0o644)


def repair_keyring_file(path: Path) -> bool:
    if not path.exists():
        write_empty_keyring(path)
        return True
    text = path.read_text()
    if not has_multiline_secrets(text):
        return False
    rendered = render_keyring(parse_keyring(text))
    path.write_text(rendered)
    path.chmod(0o600)
    return True
