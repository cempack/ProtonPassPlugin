#!/usr/bin/env python3
"""Unit tests for Omarchy keyring file repair. Never asserts on secret values."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
import sys

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import keyring_store  # noqa: E402


MULTILINE_JSON = """\
[keyring]
display-name=Default keyring
ctime=1
mtime=0
lock-on-idle=false
lock-after=false

[1]
item-type=0
display-name=Password for 'demo' on 'Proton'
secret={"UID": "abc", "vpn": "-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEANm3a
-----END PUBLIC KEY-----"}
mtime=2
ctime=2

[1:attribute0]
name=service
type=string
value=Proton

[2]
item-type=0
display-name=Chromium Safe Storage
secret=single-line-secret
mtime=3
ctime=3

[2:attribute0]
name=xdg:schema
type=string
value=chrome_libsecret_os_crypt_password_v2
"""


class KeyringStoreTests(unittest.TestCase):
    def test_detects_multiline_secret(self) -> None:
        self.assertTrue(keyring_store.has_multiline_secrets(MULTILINE_JSON))
        self.assertFalse(
            keyring_store.has_multiline_secrets(
                "[keyring]\n[1]\nsecret=ok\nmtime=1\n"
            )
        )

    def test_parse_keeps_both_items(self) -> None:
        items = keyring_store.parse_keyring(MULTILINE_JSON)
        labels = [item["label"] for item in items]
        self.assertEqual(
            labels,
            ["Password for 'demo' on 'Proton'", "Chromium Safe Storage"],
        )
        self.assertIn("\n", items[0]["secret"])
        self.assertEqual(items[0]["attrs"]["service"], "Proton")

    def test_durable_secret_is_single_line_json(self) -> None:
        items = keyring_store.parse_keyring(MULTILINE_JSON)
        fixed = keyring_store.durable_secret(items[0]["label"], items[0]["secret"])
        self.assertNotIn("\n", fixed)
        payload = json.loads(fixed)
        self.assertEqual(payload["UID"], "abc")
        self.assertIn("BEGIN PUBLIC KEY", payload["vpn"])

    def test_rewrite_file_is_valid_and_preserves_labels(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "Default_keyring.keyring"
            path.write_text(MULTILINE_JSON)
            changed = keyring_store.repair_keyring_file(path)
            self.assertTrue(changed)
            text = path.read_text()
            self.assertFalse(keyring_store.has_multiline_secrets(text))
            items = keyring_store.parse_keyring(text)
            self.assertEqual(len(items), 2)
            self.assertEqual(items[0]["label"], "Password for 'demo' on 'Proton'")
            self.assertEqual(items[1]["secret"], "single-line-secret")
            self.assertEqual(json.loads(items[0]["secret"])["UID"], "abc")

    def test_rewrite_is_noop_when_already_valid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "Default_keyring.keyring"
            path.write_text(
                keyring_store.empty_keyring_text()
                + "\n[1]\nitem-type=0\ndisplay-name=x\nsecret=y\nmtime=1\nctime=1\n"
            )
            self.assertFalse(keyring_store.repair_keyring_file(path))

    def test_never_uses_gnome_create_label(self) -> None:
        self.assertEqual(keyring_store.OMARCHY_LABEL, "Default keyring")
        self.assertNotEqual(keyring_store.OMARCHY_LABEL, keyring_store.GNOME_CREATE_LABEL)


if __name__ == "__main__":
    unittest.main()
