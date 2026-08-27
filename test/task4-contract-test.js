#!/usr/bin/env node
"use strict"

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const ROOT = path.join(__dirname, "..")
const modelSource = fs.readFileSync(path.join(ROOT, "Model.js"), "utf8")
const serviceSource = fs.readFileSync(path.join(ROOT, "PassService.qml"), "utf8")
const panelSource = fs.readFileSync(path.join(ROOT, "Panel.qml"), "utf8")
const readmeSource = fs.readFileSync(path.join(ROOT, "README.md"), "utf8")
const allRuntimeSource = [modelSource, serviceSource, panelSource].join("\n")

const recoveryCommands = [
  "PROTON_PASS_LINUX_KEYRING=dbus pass-cli logout --force",
  "PROTON_PASS_LINUX_KEYRING=dbus pass-cli login"
]

function processSection(id, nextId) {
  const start = serviceSource.indexOf("id: " + id)
  assert.ok(start >= 0, "missing process " + id)
  const end = nextId ? serviceSource.indexOf("id: " + nextId, start) : serviceSource.length
  return serviceSource.slice(start, end >= 0 ? end : serviceSource.length)
}

const copyProcessSource = processSection("copyProcess", "viewProcess")
const viewProcessSource = processSection("viewProcess", "previewProcess")
const previewProcessSource = processSection("previewProcess", "createProcess")
const createProcessSource = processSection("createProcess", "generateProcess")
const generateProcessSource = processSection("generateProcess", "clipboardProcess")
const clipboardProcessSource = processSection("clipboardProcess", "clipboardClearProcess")

assert.doesNotMatch(
  serviceSource,
  /createProcess\.command\s*=[^\n]*password|--password|--generate-password|--title|--username|--email|--url/,
  "login-creation fields must never enter the create process argv"
)
assert.doesNotMatch(modelSource, /--generate-password|--title|--username|--email|--url/)
assert.doesNotMatch(
  serviceSource,
  /execDetached\(\s*\[["']bash["']/,
  "clipboard copies must not put secrets or usernames in bash -c argv"
)
assert.doesNotMatch(allRuntimeSource, /Util\.shellQuote/)
assert.match(serviceSource, /stdinEnabled:\s*(?:true|false)/, "create process declares stdin lifecycle")
assert.match(serviceSource, /onStarted:[\s\S]*?write\(/, "serialized login template is written after process start")
assert.match(
  serviceSource,
  /onStarted:[\s\S]*?_createStdinPayload\s*=\s*""/,
  "pending serialized login payload is cleared immediately after write"
)
assert.match(
  serviceSource,
  /onExited:[\s\S]*?_createStdinPayload\s*=\s*""|onRunningChanged:[\s\S]*?_createStdinPayload\s*=\s*""/,
  "pending serialized login payload is also cleared on process failure or exit"
)
assert.match(
  serviceSource,
  /onStarted:[\s\S]*?stdinEnabled\s*=\s*false/,
  "stdin is closed after the template write so pass-cli receives EOF"
)
assert.doesNotMatch(allRuntimeSource, /console\.(?:log|warn|error)[^\n]*(?:password|_createStdinPayload)/i)

for (const name of ["copy", "view", "preview", "create", "generate", "clipboard"]) {
  assert.match(serviceSource, new RegExp("id:\\s*" + name + "Watchdog\\b"), name + " process has a finite watchdog")
  assert.match(
    serviceSource,
    new RegExp(name + "Watchdog\\.restart\\(\\)"),
    name + " watchdog starts with its process"
  )
  assert.match(
    serviceSource,
    new RegExp(name + "Process\\.signal\\(9\\)"),
    name + " timeout force-kills a hung process"
  )
}
assert.match(
  serviceSource,
  /function handleCreateTimeout[\s\S]*_createStdinPayload\s*=\s*""[\s\S]*creating\s*=\s*false/,
  "create timeout clears pending stdin and busy state"
)
assert.match(serviceSource, /timed out/i, "watchdogs surface a sanitized timeout message")

assert.match(
  serviceSource,
  /copyProcess\.command\s*=\s*\["timeout",\s*"--signal=TERM",\s*"--kill-after=2s",\s*"30s",\s*"bash",\s*"-o",\s*"pipefail"/,
  "copy pipeline uses GNU timeout process-group termination with kill escalation and pipefail"
)
assert.doesNotMatch(
  serviceSource,
  /copyProcess\.command\s*=\s*\[[^\n]*--foreground/,
  "copy timeout must retain GNU timeout child process-group behavior"
)
assert.match(
  copyProcessSource,
  /exitCode\s*===\s*124[\s\S]*timeoutMessage\("Copy"\)/,
  "GNU timeout exits surface the sanitized copy timeout message"
)
assert.doesNotMatch(copyProcessSource, /stdout:\s*StdioCollector/, "copied secret output never enters QML memory")
assert.match(copyProcessSource, /classifyError/, "copy pipeline stderr remains classifiable")
assert.match(
  copyProcessSource,
  /latchSessionBlockingFailure\(kind,\s*stderr\)/,
  "copy failures apply migration, locked, and unauthenticated session states"
)

for (const [name, section, busyFlag] of [
  ["copy", copyProcessSource, "copying"],
  ["view", viewProcessSource, "viewing"],
  ["preview", previewProcessSource, "previewing"],
  ["create", createProcessSource, "creating"],
  ["generate", generateProcessSource, "generatingPassword"],
  ["clipboard", clipboardProcessSource, "_clipboardActive"]
]) {
  assert.match(section, /onRunningChanged:[\s\S]*Qt\.callLater/, name + " handles failed launch without exited")
  assert.match(section, new RegExp(busyFlag + "\\s*=\\s*false"), name + " failed launch clears its busy flag")
}
assert.match(createProcessSource, /onRunningChanged:[\s\S]*_createStdinPayload\s*=\s*""/, "failed create launch clears stdin payload")

assert.match(viewProcessSource, /stdout:\s*SplitParser/, "view secret output uses a non-retaining parser")
assert.doesNotMatch(viewProcessSource, /stdout:\s*StdioCollector/, "view secret output is not retained by StdioCollector")
assert.match(generateProcessSource, /stdout:\s*SplitParser/, "generated secret output uses a non-retaining parser")
assert.doesNotMatch(generateProcessSource, /stdout:\s*StdioCollector/, "generated secret output is not retained by StdioCollector")
assert.match(previewProcessSource, /stdout:\s*SplitParser/, "preview JSON also avoids retaining embedded secrets")
assert.match(serviceSource, /function resetViewed[\s\S]*_viewOutput\s*=\s*""/, "view reset clears its manual secret buffer")
assert.match(generateProcessSource, /_generateOutput\s*=\s*""/, "generated secret buffer is cleared after use")

assert.match(serviceSource, /parsed\.status\s*===\s*"partial"|warning/, "partial fetch results have a UI path")
assert.match(
  serviceSource,
  /mergePartialItemLists/,
  "partial refreshes preserve cached rows from failed vaults while applying available items"
)
assert.match(
  panelSource,
  /showList[\s\S]*pass\.lastError|pass\.lastError[\s\S]*showList/,
  "a ready list can display a non-blocking partial warning"
)
assert.match(
  panelSource,
  /listReady\s*&&\s*pass\.items\.length\s*===\s*0\s*&&\s*pass\.lastError\s*!==\s*""[\s\S]*return pass\.lastError/,
  "an empty partial result displays its warning instead of claiming there are no logins"
)
assert.match(serviceSource, /property string fetchWarning:\s*""/, "partial failures use dedicated warning state")
assert.match(
  serviceSource,
  /parsed\.status\s*===\s*"partial"[\s\S]*fetchWarning\s*=[\s\S]*else[\s\S]*fetchWarning\s*=\s*""/,
  "partial warning remains until a full successful refresh clears it"
)
assert.match(panelSource, /pass\.fetchWarning/, "panel renders the dedicated non-blocking warning")
assert.match(
  panelSource,
  /visible:\s*root\.showList\s*&&\s*root\.statusHint\s*===\s*""\s*&&\s*pass\.fetchWarning\s*!==\s*""/,
  "empty partial state does not render its warning twice"
)

for (const command of recoveryCommands) {
  assert.ok(readmeSource.includes(command), "README must document exact migration recovery command: " + command)
  assert.ok(!panelSource.includes(command), "panel must not dump recovery commands as UI text: " + command)
  assert.ok(!serviceSource.includes(command), "service must not dump recovery commands as UI text: " + command)
}
assert.match(
  panelSource,
  /if \(pass\.status === "migration-required"\) return "[^"]*pass-cli login[^"]*"/,
  "migration status uses a human-readable hint"
)
assert.match(
  serviceSource,
  /if \(kind === "migration-required"\)\s*\n?\s*return "[^"]*pass-cli login[^"]*"/,
  "migration lastError is a human-readable hint"
)
assert.match(serviceSource, /migration-required/, "migration status is handled by the service")
assert.match(panelSource, /migration-required/, "migration status blocks the normal panel flow")
assert.match(
  serviceSource,
  /function latchSessionBlockingFailure[\s\S]*previewProcess\.running\s*=\s*false/,
  "migration handling terminates an in-flight preview"
)
assert.match(
  serviceSource,
  /id:\s*generateProcess[\s\S]*stderr:[\s\S]*classifyError/,
  "password generation also surfaces migration-required failures"
)
assert.match(readmeSource, /never|does not automatically|will not automatically/i, "README states recovery is not automatic")

assert.match(panelSource, /Create Login/, "create view has a clear title and primary action")
assert.match(panelSource, /ACCOUNT DETAILS/, "create view separates account details")
assert.match(panelSource, /SECURITY/, "create view separates password security")
assert.match(panelSource, /text:\s*"Title"/, "title field has a visible label")
assert.match(panelSource, /text:\s*"Username"/, "username field has a visible label")
assert.match(panelSource, /text:\s*"Website"/, "website field has a visible label")
assert.match(panelSource, /text:\s*"Password"/, "password field has a visible label")
assert.match(panelSource, /text:\s*"Vault"/, "vault chooser has a visible label")
assert.match(panelSource, /text:\s*pass\.creating\s*\?\s*"Creating…"\s*:\s*"Create Login"/, "primary action has a busy label")
assert.match(panelSource, /function saveCreate[\s\S]*createSubmitAttempted\s*=\s*true/, "save attempts enable inline validation")
assert.match(panelSource, /createSubmitAttempted[\s\S]*draftTitle/, "empty titles have inline validation")
assert.match(
  panelSource,
  /generatePassword:\s*(?:String\()?draftPassword(?:\s*\|\|\s*"")?\)?\s*===\s*""/,
  "only a truly blank password requests generated-password creation"
)
assert.match(
  serviceSource,
  /needsPasswordGeneration[\s\S]*_pendingCreateFields[\s\S]*password", "generate", "random"/,
  "blank-password creation generates first, then creates from a stdin template"
)
assert.match(
  serviceSource,
  /pendingCreate[\s\S]*startCreateProcess\(/,
  "generated-password creation continues through stdin template launch, not argv flags"
)
assert.match(
  serviceSource,
  /function copyText[\s\S]*stdinEnabled\s*=\s*true[\s\S]*wl-copy/,
  "username and URL copies send clipboard text over wl-copy stdin"
)
assert.match(clipboardProcessSource, /onStarted:[\s\S]*write\(/, "clipboard text is written after wl-copy starts")
assert.match(
  clipboardProcessSource,
  /onStarted:[\s\S]*stdinEnabled\s*=\s*false/,
  "clipboard stdin is closed after the write so wl-copy receives EOF"
)
assert.doesNotMatch(panelSource, /tooltipText:\s*"Save"/, "header does not duplicate the full-width primary action")
assert.match(
  panelSource,
  /blocked:[^\n]*root\.showCreate[^\n]*!keyCatcher\.activeFocus/,
  "key catcher yields to focused dropdown and buttons"
)
assert.match(panelSource, /id:\s*createButton[\s\S]*enabled:\s*!pass\.creating\s*&&\s*!pass\.generatingPassword/, "create is disabled during password generation")
assert.match(panelSource, /function saveCreate[\s\S]*pass\.generatingPassword[\s\S]*return/, "keyboard submit is disabled during generation")
assert.match(
  panelSource,
  /visible:\s*root\.showDetail\s*\|\|\s*root\.showCreate[\s\S]*enabled:\s*!pass\.generatingPassword/,
  "create header action is disabled during generation"
)

assert.match(panelSource, /TextEdit\s*\{[\s\S]*selectByMouse:\s*true/, "migration commands are mouse-selectable")
assert.match(panelSource, /TextEdit\s*\{[\s\S]*selectByKeyboard:\s*true/, "migration commands are keyboard-selectable")
assert.match(
  panelSource,
  /id:\s*statusText[\s\S]*Keys\.onEscapePressed:[\s\S]*root\.handleCloseRequest\(\)/,
  "Escape closes the panel while recovery commands have focus"
)
assert.match(
  panelSource,
  /id:\s*vaultDropdown[\s\S]*Keys\.onPressed:[\s\S]*Qt\.Key_Escape[\s\S]*vaultDropdown\.popupOpen[\s\S]*vaultDropdown\.close\(\)[\s\S]*root\.closeCreate\(\)/,
  "Escape closes the vault popup first and otherwise cancels create"
)
assert.match(
  panelSource,
  /id:\s*generateButton[\s\S]*focusable:\s*true[\s\S]*Keys\.onEscapePressed:[\s\S]*root\.closeCreate\(\)/,
  "Escape cancels create while Generate has focus"
)
assert.match(
  panelSource,
  /id:\s*createButton[\s\S]*focusable:\s*true[\s\S]*Keys\.onEscapePressed:[\s\S]*root\.closeCreate\(\)/,
  "Escape cancels create while Create Login has focus"
)

assert.match(panelSource, /function resetDraft[\s\S]*draftPassword\s*=\s*""/, "draft model password is cleared")
assert.match(panelSource, /function resetDraft[\s\S]*passwordField\.text\s*=\s*""/, "password input storage is cleared")
assert.match(panelSource, /function close\(\)[\s\S]*resetDraft\(\)/, "panel close clears draft secrets")
assert.match(panelSource, /function closeCreate[\s\S]*resetDraft\(\)/, "create cancel clears draft secrets")
assert.match(panelSource, /function onCreated[\s\S]*closeCreate\(\)/, "successful create clears draft secrets")
assert.match(
  panelSource,
  /function onPasswordGenerated[\s\S]*if\s*\(!root\.opened\s*\|\|\s*!root\.showCreate(?:\s*\|\|\s*pass\.creating)?\)\s*return[\s\S]*draftPassword\s*=/,
  "a generated password cannot repopulate draft state after cancel or panel close"
)

assert.match(
  serviceSource,
  /function showCopied[\s\S]*scheduleClipboardClear\(/,
  "successful copies schedule the optional clipboard clear"
)
assert.match(
  serviceSource,
  /function scheduleClipboardClear[\s\S]*clipboardClearMs\s*<=\s*0[\s\S]*return/,
  "clipboard clear stays off when the delay is 0"
)
assert.match(
  serviceSource,
  /id:\s*clipboardClearTimer/,
  "clipboard clear uses a one-shot timer"
)
assert.match(
  serviceSource,
  /id:\s*clipboardClearProcess/,
  "clipboard clear uses a dedicated process"
)
assert.match(
  serviceSource,
  /clipboardClearProcess\.command\s*=\s*\[[^\]]*"wl-copy"[^\]]*"--clear"/,
  "clipboard clear invokes wl-copy --clear as argv"
)
assert.doesNotMatch(
  serviceSource,
  /clipboardClearProcess\.command\s*=\s*\[[^\]]*bash/,
  "clipboard clear must not use bash -c"
)
const clearClipboardFn = serviceSource.match(/function clearClipboard\(\) \{[\s\S]*?\n  function /)
assert.ok(clearClipboardFn, "clearClipboard is defined before the next function")
assert.doesNotMatch(
  clearClipboardFn[0],
  /lastError/,
  "clipboard auto-clear must not surface secrets or errors as lastError"
)
assert.match(
  readmeSource,
  /clipboardClearSeconds/,
  "README documents the optional clipboard clear setting"
)

console.log("ok")
