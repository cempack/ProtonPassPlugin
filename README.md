# Proton Pass

Search Proton Pass items from the Omarchy bar and inspect logins, notes, cards, identities, aliases, Wi-Fi, SSH keys, and custom fields in a popover.

## Requirements

- [`pass-cli`](https://protonpass.github.io/pass-cli/) on `PATH` (or set `passCliPath` in the widget settings)
- A logged-in `pass-cli` session (`pass-cli login`)
- `wl-copy` for clipboard copy
- Optional: the Proton Pass desktop app (`proton-pass`) for the header's open-app buttons

The plugin sets `PROTON_PASS_LINUX_KEYRING=dbus` so the session is stored in GNOME Keyring and survives reboots. After installing or switching to this, run `pass-cli login` once more (an old kernel-keyring session will not carry over).

If `pass-cli` reports an SQLCipher HMAC, database decryption, or encryption-key mismatch after switching keyrings, run these one-time recovery commands exactly:

```sh
PROTON_PASS_LINUX_KEYRING=dbus pass-cli logout --force
PROTON_PASS_LINUX_KEYRING=dbus pass-cli login
```

The plugin never runs these commands automatically and never deletes or resets local `pass-cli` state. Until recovery is complete, fetching and secret previews stop and the panel asks you to run `pass-cli login`, then right-click the bar icon to refresh.

On Omarchy / Arch:

```sh
omarchy pkg aur add proton-pass-cli
pass-cli login
```

## Install

```sh
omarchy plugin add https://github.com/cempack/ProtonPassPlugin.git --enable
```

For a local checkout:

```sh
PLUGIN_ID="io.github.cempack.proton-pass"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
rsync -a --delete --exclude .git --exclude test "$PWD/" "$PLUGIN_DIR/"
omarchy plugin validate "$PLUGIN_DIR"
omarchy-shell shell rescanPlugins
omarchy plugin enable "$PLUGIN_ID" --section right
```

## Usage

Click the key icon in the bar to open or close the panel. Press Escape to close it (or to go back from an item).

- Search filters titles, usernames, URLs, vault names, and item types
- **Suggested** matches the active window
- **Most recent** is last used in this panel (then last modified)
- Click a row to open the inspector (copy fields, reveal secrets, live TOTP)
- Enter copies a login password and closes when the clipboard is ready. For every other type, Enter opens the inspector instead of dumping notes or keys onto the clipboard. Copied secrets stay on the clipboard until something overwrites them unless `clipboardClearSeconds` is set above 0.
- `+` opens a single-page login form with account details, vault selection, password generation, and one Create Login action; the window button opens the Proton Pass app
- Right-click the bar icon to force-refresh; middle-click opens Proton Pass
- Titles, usernames, URLs, and item types are cached on disk (never passwords, TOTP, notes, card numbers, or extra field values). The panel opens from cache and refreshes in the background when the cache is older than `cacheMinutes` (default 15).

## Keyboard

- `/`: focus search
- `j` / `k` or arrows: move
- Enter: copy a login password and close, or open the inspector for other types
- `c`: copy the login password on the detail view
- `r`: refresh
- Escape: back / close
- On the create-login form, Enter advances fields and submits from Password

## Configure

```sh
omarchy bar move io.github.cempack.proton-pass --section right
```

Widget settings (`passCliPath`, `cacheMinutes`, `clipboardClearSeconds`) live on the plugin's bar entry in `~/.config/omarchy/shell.json`. Metadata cache is `~/.cache/omarchy/proton-pass.json`. `clipboardClearSeconds` is 0 (off) by default; set it to clear the clipboard that many seconds after a copy.

## Remove

```sh
omarchy plugin remove io.github.cempack.proton-pass
```

## License

MIT. See [LICENSE](LICENSE).

The plugin talks to a local `pass-cli` process and copies secrets to the clipboard with `wl-copy`. User-entered passwords for new logins are serialized as a JSON login template and sent only over the child process's standard input; they are never placed in process arguments. Blank-password creation generates a password first, then sends that value over stdin with the rest of the login template. Username and URL clipboard copies also send the text to `wl-copy` over stdin rather than command-line arguments. If `clipboardClearSeconds` is greater than 0, the plugin later runs `wl-copy --clear` so a copied secret does not stay on the clipboard indefinitely. The plugin never writes passwords, TOTP codes, note bodies, card numbers, or `--show-secrets` list output to disk or logs. The inspector loads one item at a time into memory and clears it when you go back or close the panel. Title, username, URL, and item-type metadata may be cached at `~/.cache/omarchy/proton-pass.json`. Login row icons try every website on the item: first `https://<host>/favicon.ico`, then `https://www.google.com/s2/favicons?domain=<host>&sz=64`, then the parent domain (so `konsoleh.hetzner.com` can still land on `hetzner.com`). Localhost and IP addresses are skipped. The type glyph stays until one image loads. Cached usernames no longer skip the one-time website preview, so icons can fill in after a refresh. Omarchy plugins run unsandboxed in the shell process.
