import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Talks to pass-cli for one panel instance: item list + cache, sign-in, copying,
// the item inspector, live 2FA codes, the password generator and login creation.
// Secrets only pass through pass-cli | wl-copy pipes or the open inspector; the
// on-disk cache holds metadata only.
Item {
  id: root
  visible: false

  property var settings: ({})

  // ── List state ──────────────────────────────────────────────────────────────
  property string status: "idle"  // idle | loading | ready | missing | unauthenticated | locked | migration-required | error
  property string lastError: ""
  property string fetchWarning: ""
  property var fetchWarningMetadata: null
  property string email: ""
  property var items: []
  property double fetchedAt: 0
  property bool refreshing: false
  property bool signingIn: false

  // ── Inspector ───────────────────────────────────────────────────────────────
  property var inspector: null
  property string inspectorKey: ""
  property var totpCodes: ({})
  readonly property bool inspecting: inspectJob.running

  // ── Live 2FA codes for list rows: { "<shareId>/<itemId>": { code, period, expires } }
  property var liveCodes: ({})
  property double now: Date.now()
  readonly property bool liveTotpRunning: totpFeed.running

  // ── Generator ───────────────────────────────────────────────────────────────
  property string generated: ""
  readonly property bool generating: generateJob.running

  // ── Feedback ────────────────────────────────────────────────────────────────
  property string notice: ""
  property string noticeTone: "info"  // info | success | error
  readonly property bool copying: copyJob.running || clipboardJob.running
  readonly property bool creating: createJob.running || _pendingCreate !== null

  readonly property bool needsSignIn: Model.isSessionBlockingStatus(status)
  readonly property int cacheMs: {
    var minutes = parseInt(String(setting("cacheMinutes", 15)), 10)
    if (!isFinite(minutes) || minutes < 1) minutes = 15
    return Math.min(minutes, 120) * 60 * 1000
  }
  readonly property int clipboardClearMs: Model.clipboardClearDelayMs(setting("clipboardClearSeconds", 0))
  readonly property string passCli: String(setting("passCliPath", "pass-cli") || "").trim() || "pass-cli"
  // The plugin keeps its own pass-cli session so a `pass-cli login` run in a terminal
  // (which uses a different key store) can never make the stored database unreadable here.
  readonly property string sessionDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/omarchy-proton-pass"
  readonly property var passCliEnvironment: ({
    "PROTON_PASS_LINUX_KEYRING": "dbus",
    "PROTON_PASS_SESSION_DIR": sessionDir
  })
  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/omarchy"
  readonly property string cachePath: cacheDir + "/proton-pass.json"
  readonly property int peerLockMs: 90000

  signal copied(string label)
  signal created()
  signal createFailed(string message)
  signal itemUpdated(var item)

  property var _pendingCreate: null
  property bool _signInCancelled: false
  property bool _dirReady: false
  property bool _cacheHydrated: false
  property bool _startupRefreshDone: false
  property bool _openWantsFresh: false
  property bool _writingCache: false
  property double _peerRefreshingAt: 0
  property string _lastCacheText: ""
  property bool _liveTotpWanted: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function pluginFile(name) {
    var url = String(Qt.resolvedUrl(name))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
  }

  function statusMessageFor(kind, detail) {
    if (kind === "missing") return "pass-cli is not installed"
    if (kind === "unauthenticated") return "Sign in to Proton Pass"
    if (kind === "locked") return "Session is locked. Sign in again"
    if (kind === "migration-required")
      return "The saved session could not be read. Sign in again"
    if (kind === "timeout") return "pass-cli did not answer in time."
    if (kind === "launch") return "Could not start pass-cli."
    return Model.displayError(detail) || "Could not load Proton Pass"
  }

  function notify(text, tone) {
    notice = String(text || "")
    noticeTone = tone || "info"
    noticeTimer.interval = noticeTone === "error" ? 4000 : 1600
    noticeTimer.restart()
  }

  function clearNotice() {
    noticeTimer.stop()
    notice = ""
  }

  // A job failed: latch session problems into `status`, otherwise surface the error.
  function handleFailure(result, fallback) {
    if (Model.isSessionBlockingStatus(result.kind) || result.kind === "missing") {
      blockSession(result.kind)
      return
    }
    var message = result.kind === "error"
      ? (Model.displayError(result.stderr || result.stdout) || fallback)
      : statusMessageFor(result.kind, result.stderr)
    notify(message, "error")
  }

  function blockSession(kind) {
    stopLiveTotp()
    closeInspector()
    status = kind
    lastError = statusMessageFor(kind, "")
    refreshing = false
  }

  function applyReady() {
    status = "ready"
    lastError = ""
    refreshing = false
    if (_liveTotpWanted) startLiveTotp()
  }

  // ── Refresh & cache ─────────────────────────────────────────────────────────

  function isStale() {
    return fetchedAt === 0 || (Date.now() - fetchedAt) > cacheMs
  }

  function isPeerRefreshing() {
    return _peerRefreshingAt > 0 && (Date.now() - _peerRefreshingAt) < peerLockMs
  }

  function ensureFresh() {
    if (fetchJob.running) return
    if (!_cacheHydrated) {
      _openWantsFresh = true
      return
    }
    if (items.length > 0 && !isStale()) return
    refresh(false)
  }

  function refresh(force, silent) {
    if (fetchJob.running) return
    if (needsSignIn && force !== true) return
    if (force !== true && (!isStale() || isPeerRefreshing())) return
    if (silent !== true || items.length === 0) {
      if (items.length === 0 && !needsSignIn && status !== "missing") status = "loading"
      refreshing = true
    }
    lastError = ""
    _peerRefreshingAt = Date.now()
    writeCache(_peerRefreshingAt)
    fetchJob.run(["python3", pluginFile("fetch.py"), passCli])
  }

  function applyFetch(result) {
    refreshing = false
    _peerRefreshingAt = 0
    var parsed = Model.parseFetchResult(result.stdout)
    if (parsed.status === "busy") {
      writeCache(0)
      return
    }
    if (!parsed.ok) {
      var kind = parsed.status && parsed.status !== "error"
        ? parsed.status
        : (result.ok ? "error" : result.kind)
      if (Model.isSessionBlockingStatus(kind) || kind === "missing") {
        blockSession(kind)
      } else {
        var message = statusMessageFor(kind, parsed.message || result.stderr || result.stdout)
        if (items.length === 0) {
          status = kind
          lastError = message
        } else {
          notify(message, "error")
        }
      }
      writeCache(0)
      return
    }
    email = parsed.email
    var warning = parsed.warning || null
    items = parsed.status === "partial"
      ? Model.mergePartialItemLists(items, parsed.items, warning ? warning.failedShareIds : [])
      : Model.mergeItemLists(items, parsed.items)
    fetchedAt = Date.now()
    fetchWarningMetadata = parsed.status === "partial" ? warning : null
    fetchWarning = fetchWarningMetadata ? String(fetchWarningMetadata.message || "") : ""
    applyReady()
    writeCache(0)
  }

  function applyCache(raw) {
    var parsed = Model.parseCache(raw)
    _peerRefreshingAt = parsed.refreshingAt || 0
    _cacheHydrated = true
    if (parsed.ok && parsed.fetchedAt >= fetchedAt) {
      email = parsed.email || email
      items = Model.mergeItemLists(items, parsed.items)
      if (parsed.fetchedAt > fetchedAt) {
        fetchWarningMetadata = parsed.warning || null
        fetchWarning = parsed.warning ? String(parsed.warning.message || "") : ""
      }
      fetchedAt = parsed.fetchedAt
      if ((items.length > 0 || parsed.fetchedAt > 0) && (status === "idle" || status === "loading"))
        applyReady()
    }
    afterCacheReady()
  }

  function afterCacheReady() {
    if (!_dirReady || !_cacheHydrated) return
    if (_openWantsFresh) {
      _openWantsFresh = false
      ensureFresh()
    }
    if (_startupRefreshDone) return
    _startupRefreshDone = true
    if (!fetchJob.running && (items.length === 0 || isStale())) refresh(false)
  }

  function writeCache(refreshingAt) {
    if (!_dirReady) return
    if (!_cacheHydrated && items.length === 0 && fetchedAt === 0 && !(refreshingAt > 0)) return
    var started = Number(refreshingAt || 0)
    var text = JSON.stringify(Model.serializeCache(email, fetchedAt, items, isFinite(started) ? started : 0, fetchWarningMetadata)) + "\n"
    if (text === _lastCacheText) return
    _lastCacheText = text
    _writingCache = true
    cacheFile.setText(text)
    Qt.callLater(function() { root._writingCache = false })
  }

  function findItem(item) {
    if (!item) return null
    for (var i = 0; i < items.length; i++) {
      var current = items[i]
      if (current && current.id === item.id && current.shareId === item.shareId) return current
    }
    return null
  }

  function replaceItem(updated) {
    if (!updated || !updated.id) return
    var next = []
    for (var i = 0; i < items.length; i++) {
      var current = items[i]
      next.push(current && current.id === updated.id && current.shareId === updated.shareId ? updated : current)
    }
    items = next
    itemUpdated(updated)
    cacheWriteTimer.restart()
  }

  function touchItem(item) {
    var current = findItem(item)
    if (current) replaceItem(Model.withChanges(current, { lastUsedAt: Date.now() }))
  }

  // ── Sign-in ─────────────────────────────────────────────────────────────────

  // Runs `pass-cli login` in the plugin's own session and opens the sign-in page it prints.
  // A locked or unreadable session belongs to this plugin alone, so it is cleared first.
  function signIn() {
    if (signingIn || status === "missing") return
    var reset = status === "locked" || status === "migration-required"
    signingIn = true
    _signInCancelled = false
    lastError = ""
    loginJob.run(["sh", "-c",
      'if [ "$2" = reset ]; then "$1" logout --force >/dev/null 2>&1; fi; exec "$1" login',
      "proton-pass-sign-in", passCli, reset ? "reset" : "keep"])
  }

  function cancelSignIn() {
    if (!signingIn) return
    loginJob.stop()
    signingIn = false
  }

  function handleSignInLine(line) {
    var url = String(line || "").trim()
    if (!/^https:\/\/account\.proton\.me\/\S+$/.test(url)) return
    Quickshell.execDetached(["xdg-open", url])
  }

  function finishSignIn(result) {
    signingIn = false
    if (!result.ok) {
      lastError = result.kind === "timeout"
        ? "Sign-in timed out."
        : (Model.displayError(result.stderr) || "Sign-in did not complete.")
      return
    }
    status = "idle"
    lastError = ""
    refresh(true)
  }

  // ── Clipboard ───────────────────────────────────────────────────────────────

  // Copies one field straight from pass-cli to wl-copy; the secret never enters QML.
  function copyField(item, field, label) {
    var uri = Model.passUri(item, field || "password")
    if (uri === "" || copying) return
    touchItem(item)
    clearNotice()
    clipboardClearTimer.stop()
    copyJob.label = label || Model.fieldLabel(field)
    copyJob.run(["timeout", "--signal=TERM", "--kill-after=2s", "30s",
      "bash", "-o", "pipefail", "-c", "\"$0\" item view \"$1\" | wl-copy", passCli, uri])
  }

  // Copies a value the panel already holds (a 2FA code, a generated password).
  function copyText(value, label) {
    var text = String(value || "")
    if (text === "" || clipboardJob.running) return
    clearNotice()
    clipboardClearTimer.stop()
    clipboardJob.label = label || "Value"
    clipboardJob.run(["timeout", "--signal=TERM", "--kill-after=2s", "30s", "wl-copy"], text)
  }

  function copyLiveCode(item) {
    var entry = liveCodes[Model.itemKey(item)]
    if (!entry || !entry.code) return false
    touchItem(item)
    copyText(entry.code, "2FA code")
    return true
  }

  function finishCopy(result, label) {
    if (result.ok) {
      notify(label + " copied", "success")
      copied(label)
      if (clipboardClearMs > 0) clipboardClearTimer.restart()
    } else {
      handleFailure(result, "Could not copy " + label.toLowerCase() + ".")
    }
  }

  function clearClipboard() {
    if (copying) {
      clipboardClearTimer.restart()
      return
    }
    Quickshell.execDetached(["timeout", "10s", "wl-copy", "--clear"])
  }

  // ── Inspector ───────────────────────────────────────────────────────────────

  function inspect(item) {
    if (!item || !item.shareId || !item.id) return
    closeInspector()
    inspectorKey = Model.itemKey(item)
    inspectJob.run([passCli, "item", "view", "--share-id=" + item.shareId, "--item-id=" + item.id, "--output", "json"])
  }

  function closeInspector() {
    inspectJob.stop()
    inspectTotpJob.stop()
    inspector = null
    inspectorKey = ""
    totpCodes = ({})
  }

  function refreshInspectorTotp() {
    if (!inspector || inspector.hasTotp !== true || inspectorKey === "") return
    var parts = inspectorKey.split("/")
    inspectTotpJob.run([passCli, "item", "totp", "--share-id=" + parts[0], "--item-id=" + parts.slice(1).join("/"), "--output", "json"])
  }

  // ── Live 2FA ────────────────────────────────────────────────────────────────

  function startLiveTotp() {
    _liveTotpWanted = true
    if (totpFeed.running || status !== "ready") return
    var shareIds = Model.totpShareIds(items)
    if (shareIds.length === 0) return
    totpFeed.run(["python3", pluginFile("totp_feed.py"), passCli].concat(shareIds))
  }

  function stopLiveTotp() {
    _liveTotpWanted = false
    totpFeed.stop()
    liveCodes = ({})
  }

  function applyLiveCodes(line) {
    var parsed = Model.parseTotpFeedLine(line)
    if (!parsed) return
    if (!parsed.ok) {
      if (Model.isSessionBlockingStatus(parsed.status)) blockSession(parsed.status)
      return
    }
    liveCodes = parsed.codes
  }

  // ── Generator & creation ────────────────────────────────────────────────────

  function generate(options) {
    generateJob.forCreate = false
    generateJob.run([passCli].concat(Model.generatorArgs(options)))
  }

  function createLogin(fields) {
    if (creating) return
    var data = fields || {}
    var title = String(data.title || "").trim()
    if (title === "") {
      createFailed("Title is required.")
      return
    }
    var request = {
      shareId: data.shareId,
      title: title,
      username: String(data.username || "").trim(),
      email: String(data.email || "").trim(),
      password: String(data.password || ""),
      url: String(data.url || "").trim()
    }
    if (request.password === "") {
      // Generate first, then create with the result over stdin.
      _pendingCreate = request
      generateJob.forCreate = true
      generateJob.run([passCli].concat(Model.generatorArgs({ mode: "random", length: 20 })))
      return
    }
    startCreate(request)
  }

  function startCreate(request) {
    _pendingCreate = null
    var built = Model.buildCreateLoginRequest({
      shareId: request.shareId,
      title: request.title,
      username: request.username,
      email: request.email,
      password: request.password,
      generatePassword: false,
      url: request.url
    })
    createJob.run([passCli].concat(built.args), built.stdin)
  }

  function launchApp() {
    Quickshell.execDetached(["proton-pass"])
  }

  function openUrl(url) {
    var target = Model.openableUrl(url)
    if (target !== "") Quickshell.execDetached(["xdg-open", target])
  }

  // ── Jobs ────────────────────────────────────────────────────────────────────

  CliJob {
    id: fetchJob
    environment: root.passCliEnvironment
    timeoutMs: 120000
    maxOutput: 16777216
    onFinished: function(result) { root.applyFetch(result) }
  }

  CliJob {
    id: loginJob
    environment: root.passCliEnvironment
    timeoutMs: 300000
    streamLines: true
    onLine: function(text) { root.handleSignInLine(text) }
    onFinished: function(result) { root.finishSignIn(result) }
  }

  CliJob {
    id: copyJob
    property string label: "Password"
    environment: root.passCliEnvironment
    onFinished: function(result) { root.finishCopy(result, label) }
  }

  CliJob {
    id: clipboardJob
    property string label: "Value"
    timeoutMs: 35000
    onFinished: function(result) { root.finishCopy(result, label) }
  }

  CliJob {
    id: inspectJob
    environment: root.passCliEnvironment
    onFinished: function(result) {
      if (!result.ok) {
        root.handleFailure(result, "Could not open this item.")
        return
      }
      var parsed = Model.parseItemInspector(result.stdout)
      if (!parsed) {
        root.notify("Could not read this item.", "error")
        return
      }
      root.inspector = parsed
      root.refreshInspectorTotp()
    }
  }

  CliJob {
    id: inspectTotpJob
    environment: root.passCliEnvironment
    maxOutput: 8192
    onFinished: function(result) {
      if (result.ok) root.totpCodes = Model.parseTotpCodes(result.stdout)
      else if (Model.isSessionBlockingStatus(result.kind)) root.blockSession(result.kind)
    }
  }

  CliJob {
    id: totpFeed
    environment: root.passCliEnvironment
    timeoutMs: 0
    streamLines: true
    holdStdin: true
    onLine: function(text) { root.applyLiveCodes(text) }
    onFinished: function(result) {
      // The feed ends itself after a while; keep codes flowing while someone is looking.
      if (root._liveTotpWanted && result.ok) restartFeed.restart()
    }
  }

  CliJob {
    id: generateJob
    property bool forCreate: false
    environment: root.passCliEnvironment
    maxOutput: 4096
    onFinished: function(result) {
      var password = result.ok ? Model.parseGeneratedPassword(result.stdout) : ""
      if (!forCreate) {
        if (password !== "") root.generated = password
        else root.handleFailure(result.ok ? { kind: "error", stderr: "No password was generated." } : result, "Could not generate a password.")
        return
      }
      var pending = root._pendingCreate
      if (!pending) return
      if (password === "") {
        root._pendingCreate = null
        root.handleFailure(result.ok ? { kind: "error", stderr: "No password was generated." } : result, "Could not generate a password.")
        root.createFailed(root.notice)
        return
      }
      pending.password = password
      root.startCreate(pending)
    }
  }

  CliJob {
    id: createJob
    environment: root.passCliEnvironment
    onFinished: function(result) {
      if (result.ok) {
        root.notify("Login created", "success")
        root.created()
        root.refresh(true, true)
        return
      }
      root.handleFailure(result, "Could not create the login.")
      root.createFailed(root.notice || root.lastError)
    }
  }

  // ── Timers & files ──────────────────────────────────────────────────────────

  Timer {
    id: noticeTimer
    interval: 1600
    onTriggered: root.notice = ""
  }

  Timer {
    id: clipboardClearTimer
    interval: Math.max(1, root.clipboardClearMs)
    onTriggered: root.clearClipboard()
  }

  Timer {
    id: cacheWriteTimer
    interval: 1500
    onTriggered: root.writeCache(fetchJob.running ? root._peerRefreshingAt : 0)
  }

  Timer {
    id: restartFeed
    interval: 250
    onTriggered: root.startLiveTotp()
  }

  // Drives countdown rings and the inspector's 2FA refresh.
  Timer {
    interval: 1000
    repeat: true
    running: root._liveTotpWanted || (root.inspector !== null && root.inspector.hasTotp === true)
    triggeredOnStart: true
    onTriggered: {
      var previous = root.now
      root.now = Date.now()
      if (root.inspector && root.inspector.hasTotp === true
          && Math.floor(previous / 30000) !== Math.floor(root.now / 30000))
        root.refreshInspectorTotp()
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      if (root._cacheHydrated && !fetchJob.running && !root.needsSignIn && root.status !== "missing" && root.isStale())
        root.refresh(false)
    }
  }

  Component.onCompleted: ensureKeyring.running = true

  Process {
    id: ensureKeyring
    command: ["python3", root.pluginFile("ensure_keyring.py")]
    onExited: ensureDirs.running = true
  }

  Process {
    id: ensureDirs
    command: ["mkdir", "-p", "-m", "0700", root.cacheDir, root.sessionDir]
    onExited: {
      root._dirReady = true
      cacheFile.reload()
      root.afterCacheReady()
    }
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root._writingCache) return
      var raw = text()
      root._lastCacheText = raw
      root.applyCache(raw)
    }
    onLoadFailed: {
      root._cacheHydrated = true
      root.afterCacheReady()
    }
    onFileChanged: reload()
  }
}
