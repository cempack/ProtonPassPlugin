#!/usr/bin/env python3
"""Point Secret Service at Omarchy's unlocked keyring. Never create 'Default Keyring'."""

from __future__ import annotations

import argparse
import sys

import keyring_store


def repair_file(home: str | None = None) -> str:
    path = keyring_store.keyring_path(home)
    if keyring_store.repair_keyring_file(path):
        return "repaired"
    return "ok"


def _load_secret():
    import gi

    gi.require_version("Secret", "1")
    from gi.repository import Secret

    return Secret


def ensure_collection() -> str:
    Secret = _load_secret()
    svc = Secret.Service.get_sync(
        Secret.ServiceFlags.OPEN_SESSION | Secret.ServiceFlags.LOAD_COLLECTIONS,
        None,
    )
    omarchy = None
    gnome_created = None
    for collection in svc.get_collections():
        label = collection.get_label()
        if label == keyring_store.OMARCHY_LABEL:
            omarchy = collection
        elif label == keyring_store.GNOME_CREATE_LABEL:
            gnome_created = collection
    if omarchy is None:
        raise SystemExit(
            "Omarchy keyring 'Default keyring' is not loaded. "
            "Do not create a password-protected 'Default Keyring'."
        )
    if omarchy.get_locked():
        svc.unlock_sync([omarchy], None)
    if omarchy.get_locked():
        raise SystemExit("Omarchy keyring is locked")
    svc.set_alias_sync("default", omarchy, None)
    pointer = keyring_store.default_pointer_path()
    pointer.write_text("Default_keyring\n")
    pointer.chmod(0o644)
    extra = ""
    if gnome_created is not None:
        extra = " ignored-gnome-Default-Keyring"
    return f"default={keyring_store.OMARCHY_LABEL} unlocked=1{extra}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Use Omarchy's unlocked Default keyring")
    parser.add_argument(
        "--repair-file",
        action="store_true",
        help="Rewrite a corrupt keyring file only (safe before gnome-keyring starts)",
    )
    args = parser.parse_args(argv)
    status = repair_file()
    if args.repair_file:
        print(status)
        return 0
    print(f"{status} {ensure_collection()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
