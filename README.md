# Proton Pass

Search and copy Proton Pass logins from the Omarchy bar, in an Apple Passwords-style popover.

## Requirements

- [`pass-cli`](https://protonpass.github.io/pass-cli/) on `PATH` (or set `passCliPath` in the widget settings)
- A logged-in `pass-cli` session (`pass-cli login`)
- `wl-copy` for clipboard copy
- Optional: the Proton Pass desktop app (`proton-pass`) for the header's open-app buttons

The plugin sets `PROTON_PASS_LINUX_KEYRING=dbus` so the session is stored in GNOME Keyring and survives reboots. After installing or switching to this, run `pass-cli login` once more (an old kernel-keyring session will not carry over).

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

Click the key icon in the bar to open or close the panel. Press Escape to close it (or to go back from a login).

- Search filters titles, usernames, and URLs
- **Suggested** matches the active window
- **Most recent** is last used in this panel (then last modified)
- Click a row for details (copy username, password, TOTP, URL)
- Enter copies the password (header shows **Copying…**) and closes when the clipboard is ready
- `+` adds a new login; the window button opens the Proton Pass app
- Right-click the bar icon to force-refresh; middle-click opens Proton Pass
- Login titles, usernames, and URLs are cached on disk (never passwords). The panel opens from cache and refreshes in the background when the cache is older than `cacheMinutes` (default 15).

## Keyboard

- `/`: focus search
- `j` / `k` or arrows: move
- Enter: copy password and close
- `c`: copy password on the detail view
- `r`: refresh
- Escape: back / close
- On the new-password form, Enter advances fields and saves from Website

## Configure

```sh
omarchy bar move io.github.cempack.proton-pass --section right
```

Widget settings (`passCliPath`, `cacheMinutes`) live on the plugin's bar entry in `~/.config/omarchy/shell.json`. Metadata cache is `~/.cache/omarchy/proton-pass.json`.

## Remove

```sh
omarchy plugin remove io.github.cempack.proton-pass
```

## License

MIT. See [LICENSE](LICENSE).

The plugin talks to a local `pass-cli` process and copies secrets to the clipboard with `wl-copy`. It never writes passwords, TOTP codes, or `--show-secrets` list output to disk or logs. Title, username, and URL metadata may be cached at `~/.cache/omarchy/proton-pass.json`. Omarchy plugins run unsandboxed in the shell process.
