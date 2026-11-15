#!/usr/bin/env node
"use strict"

// Source-level guarantees that unit tests can't see: how secrets flow between
// pass-cli, the shell and the clipboard, and how the UI is wired.

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const ROOT = path.join(__dirname, "..")
const read = function (name) { return fs.readFileSync(path.join(ROOT, name), "utf8") }
const service = read("PassService.qml")
const job = read("CliJob.qml")
const panel = read("Panel.qml")
const list = read("ListPage.qml")
const detail = read("DetailPage.qml")
const create = read("CreatePage.qml")
const generator = read("GeneratorPage.qml")
const readme = read("README.md")
const fetchPy = read("fetch.py")
const feedPy = read("totp_feed.py")
const manifest = JSON.parse(read("manifest.json"))
const qmlFiles = fs.readdirSync(ROOT).filter(function (f) { return f.endsWith(".qml") })
const allQml = qmlFiles.map(read).join("\n")

function block(source, id) {
  const start = source.indexOf("id: " + id)
  assert.ok(start >= 0, "missing " + id)
  const open = source.lastIndexOf("{", start)
  let depth = 0
  for (let i = open; i < source.length; i++) {
    if (source[i] === "{") depth++
    else if (source[i] === "}" && --depth === 0) return source.slice(open, i + 1)
  }
  throw new Error("unterminated " + id)
}

// ── Session ──────────────────────────────────────────────────────────────────
assert.match(service, /"PROTON_PASS_SESSION_DIR":\s*sessionDir/, "pass-cli runs in the plugin's private session")
assert.match(service, /"\/omarchy-proton-pass"/, "the session lives outside the read-only omarchy data symlink")
assert.match(fetchPy, /setdefault\("PROTON_PASS_SESSION_DIR"/, "fetch.py inherits the same session")
for (const id of ["fetchJob", "loginJob", "copyJob", "inspectJob", "inspectTotpJob", "totpFeed", "generateJob", "createJob"])
  assert.match(block(service, id), /environment:\s*root\.passCliEnvironment/, id + " uses the private session")
assert.match(service, /\^https:\\\/\\\/account\\\.proton\\\.me\\\//, "sign-in only opens Proton account URLs")
assert.strictEqual(service.split("logout --force").length - 1, 1, "only the plugin's own sign-in reset logs out")
assert.match(readme, /never touches your terminal/i)

// ── Secrets ──────────────────────────────────────────────────────────────────
assert.match(service, /item view \\"\$1\\" \| wl-copy/, "copied secrets go pass-cli → wl-copy without entering QML")
assert.match(service, /"timeout", "--signal=TERM", "--kill-after=2s"[\s\S]*"-o", "pipefail"/, "copy pipeline is bounded and fails loudly")
assert.match(block(service, "clipboardJob"), /onFinished/, "in-panel values go to wl-copy over stdin")
assert.match(service, /clipboardJob\.run\(\[[^\]]*"wl-copy"\], text\)/, "copyText writes the value on stdin, not argv")
assert.match(service, /createJob\.run\(\[passCli\]\.concat\(built\.args\), built\.stdin\)/, "new logins are sent on stdin")
assert.ok(!/"--password"/.test(allQml + read("Model.js")), "passwords are never passed as flags")
assert.match(job, /if \(!job\.holdStdin\) stdinEnabled = false/, "stdin closes after the write so wl-copy sees EOF")
assert.match(service, /function closeInspector\(\)[\s\S]*?inspector = null[\s\S]*?totpCodes = \(\{\}\)/, "closing the inspector drops secrets")
assert.match(panel, /onOpenedChanged:[\s\S]*?pass\.closeInspector\(\)[\s\S]*?pass\.generated = ""[\s\S]*?createPage\.prepare\("", "", ""\)/, "closing the panel clears inspector, generator and form")
assert.match(create, /onVisibleChanged: if \(!visible\) awaitingGenerated = false/, "a late generated password cannot refill a closed form")
assert.ok(!/print\([^)]*(totp_uri|secret|seed)/i.test(feedPy), "the 2FA feed never prints seeds")
assert.match(fetchPy, /def sanitize_item/, "fetch.py reduces items to metadata")

// ── Clipboard clearing ───────────────────────────────────────────────────────
assert.strictEqual(manifest.barWidget.defaults.clipboardClearSeconds, 0, "auto-clear is opt-in")
assert.match(service, /execDetached\(\["timeout", "10s", "wl-copy", "--clear"\]\)/, "clearing uses argv, not a shell")

// ── Jobs ─────────────────────────────────────────────────────────────────────
assert.match(job, /function _complete\(gen, result\) \{\s*if \(gen !== _generation \|\| !_active\) return/, "stale or cancelled results are dropped")
assert.match(job, /if \(job\._exitedGeneration === gen\) return/, "a normal exit is never reported as a launch failure")
assert.match(job, /proc\.signal\(9\)[\s\S]*kind: "timeout"/, "the watchdog kills hung commands")

// ── Refresh & cache ──────────────────────────────────────────────────────────
assert.match(service, /"mkdir", "-p", "-m", "0700"/, "cache and session dirs are owner-only")
assert.match(block(service, "cacheFile"), /atomicWrites: true/)
assert.match(service, /if \(parsed\.status === "busy"\) \{\s*writeCache\(0\)\s*return/, "a busy peer fetch keeps the list")
assert.match(service, /if \(needsSignIn && force !== true\) return/, "automatic refreshes stop while signed out")

// ── Keyboard & UI wiring ─────────────────────────────────────────────────────
assert.match(panel, /event\.key === Qt\.Key_Tab[\s\S]*switchPanel/, "Tab switches bar panels")
assert.match(list, /Key_Escape\) \{\s*panel\.back\(\)/, "Escape clears search, then closes")
assert.match(list, /if \(ctrl\) panel\.copyCode\(\)\s*else if \(shift\) panel\.copy\(panel\.cursorItem, "username"\)\s*else panel\.activate\(\)/, "Enter / Shift+Enter / Ctrl+Enter")
assert.match(list, /panel\.commitQuery\(\)/, "Enter acts on the live query, not a stale debounce")
assert.match(panel, /if \(Model\.primaryCopyField\(target\)\) copy\(target, "password"\)\s*else openDetail\(target\)/, "Enter copies logins and opens other types")
assert.match(detail, /event\.key === Qt\.Key_Space\)[\s\S]*toggleReveal/, "Space reveals the selected secret")
assert.match(generator, /pass\.generate\(options\)/)
assert.match(panel, /setCenterHoverRevealSuppressed\(value\)/, "uses the bar API setter, not a read-only property")
assert.ok(!/\.centerHoverRevealSuppressed\s*=/.test(allQml), "never assigns the read-only bar property")
assert.match(service, /Model\.openableUrl\(url\)/, "only web URLs reach xdg-open")
for (const file of ["ItemRow.qml", "Favicon.qml"]) assert.match(read(file), /asynchronous: true|Favicon \{/, file + " loads icons off the UI thread")

// ── Manifest ─────────────────────────────────────────────────────────────────
assert.strictEqual(manifest.entryPoints.barWidget, "BarWidget.qml")
for (const file of qmlFiles) assert.ok(read(file).trim().length > 0, file)

console.log("ok")
