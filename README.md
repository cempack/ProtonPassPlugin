# Proton Pass

Your Proton Pass vault in the Omarchy bar: search, copy passwords and live 2FA codes, inspect every item type, generate passwords and save new logins, all from the keyboard.

## Requirements

- [`pass-cli`](https://protonpass.github.io/pass-cli/) on `PATH` (or set `passCliPath` in the widget settings)
- `wl-copy` for clipboard copy
- Optional: the Proton Pass desktop app (`proton-pass`) for the header's open-app buttons

## Signing in

Open the panel and click **Sign in**. The plugin runs `pass-cli login` for you and opens the Proton sign-in page in your browser; once you finish there, your items appear. There is nothing to configure and no command to run.

The plugin keeps its own `pass-cli` session in `~/.local/share/omarchy-proton-pass` (or `$XDG_DATA_HOME/omarchy-proton-pass`), with the encryption key stored in GNOME Keyring so it survives reboots. On Omarchy the key is bound to the unlocked **Default keyring** rather than a new password-protected **Default Keyring**.

Because the session is separate, the plugin never touches your terminal's `pass-cli` session, and a `pass-cli login` or `logout` in a terminal never affects the plugin. If the plugin's own session ever becomes unreadable or locked, the panel shows **Sign in** again; signing in replaces only the plugin's session.

Install `pass-cli` on Omarchy / Arch:

```sh
omarchy pkg aur add proton-pass-cli
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

Click the key icon in the bar (or bind `omarchy-shell io.github.cempack.proton-pass toggle` to a key). Right-click the icon to sync, middle-click to open the Proton Pass app.

**List.** Type to search titles, usernames, websites, vaults and types; every word must match and title matches rank first. **Suggested** items match the focused window. Chips under the search filter by type (All, 2FA, Logins, Aliases, Notes, Cards, Identities, SSH, Wi-Fi) with counts, and a vault picker appears when you have more than one vault. Items with 2FA show their live code and a countdown ring; click the code to copy it.

**Details.** A header with the site icon and quick actions (password, username, 2FA, open website), a large live 2FA card, and every field grouped by section. Secrets stay masked until you reveal them.

**Generator.** Random passwords (length, uppercase, numbers, symbols) or passphrases (words, separator, capitalisation, numbers) from `pass-cli password generate`, with a strength meter. Copy the result or start a new login with it.

**New login.** Title, username or email, website, vault and password. Leave the password blank and one is generated on save.

The footer always shows the keys for the current page and turns into a confirmation (or error) after an action.

## Keyboard

| Where | Keys |
| --- | --- |
| Everywhere | `Ctrl+G` generator · `Ctrl+N` new login · `Ctrl+R` sync · `Tab` next bar panel · `Esc` back / close |
| List | `↑↓` `PgUp` `PgDn` move · `↵` copy password (opens other types) · `Shift+↵` copy username · `Ctrl+↵` copy 2FA code · `→` details · `Ctrl+O` open website · `Ctrl+←/→` change filter |
| Details | `↑↓` (or `j`/`k`) field · `↵` copy field · `Space` reveal · `c` password · `u` username · `t` 2FA code · `Ctrl+O` website · `←` back |
| Generator | `↵`/`c` copy · `r` regenerate · `m` switch mode · `←/→` length or words · `n` new login with this password |
| New login | `↵` next field · `Ctrl+↵` save · `Ctrl+G` generate a password |

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

## How secrets are handled

- **Listing.** `fetch.py` asks `pass-cli` for full items (`--show-secrets`) because that is the only way to get usernames, websites and the 2FA flag in one call, then immediately reduces every item to metadata. Passwords, notes, TOTP seeds, card numbers and custom field values never leave that short-lived process. Only metadata (title, type, username, email, websites, vault, 2FA flag, last used) is cached, at `~/.cache/omarchy/proton-pass.json`.
- **Live 2FA.** While a 2FA row is on screen, `totp_feed.py` reads the TOTP seeds once, keeps them in its own memory and prints only the current codes (RFC 6238). It exits when the panel closes, or after 10 minutes.
- **Copying.** Passwords and other fields go straight from `pass-cli item view` into `wl-copy` through a pipe, so they never enter the shell's memory. Values the panel already shows (2FA codes, generated passwords, usernames) are written to `wl-copy` over stdin, never as arguments. With `clipboardClearSeconds` above 0 the clipboard is cleared that many seconds later.
- **Details.** The detail view loads one item into memory and drops it when you go back or close the panel.
- **New logins** are sent to `pass-cli` as a JSON template on stdin; passwords are never process arguments.
- **Icons** are fetched from each website (`/favicon.ico`, then Google's favicon service, then the parent domain). Localhost and IP addresses are skipped.

Omarchy plugins run unsandboxed in the shell process.
