import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool refreshing: false
  property bool copying: false
  property bool viewing: false
  property bool inspecting: false
  property bool totpLoading: false
  property bool previewing: false
  property bool creating: false
  property bool generatingPassword: false
  property string status: "idle"  // idle | loading | ready | missing | unauthenticated | locked | migration-required | error
  property string lastError: ""
  property string fetchWarning: ""
  property var fetchWarningMetadata: null
  property string email: ""
  property var items: []
  property string copiedMessage: ""
  property string viewedValue: ""
  property string viewedField: ""
  property var inspector: null
  property var totpCodes: ({})
  property int totpRemaining: 30
  property double fetchedAt: 0

  readonly property int cacheMs: {
    var minutes = parseInt(String(setting("cacheMinutes", 15)), 10)
    if (!isFinite(minutes) || minutes < 1) minutes = 15
    if (minutes > 120) minutes = 120
    return minutes * 60 * 1000
  }
  readonly property int clipboardClearMs: Model.clipboardClearDelayMs(setting("clipboardClearSeconds", 0))
  readonly property bool busy: fetchProcess.running || copyProcess.running || clipboardProcess.running || viewProcess.running || previewProcess.running || createProcess.running || generateProcess.running || inspectProcess.running || totpProcess.running
  readonly property string passCli: {
    var value = String(setting("passCliPath", "pass-cli") || "pass-cli").trim()
    return value !== "" ? value : "pass-cli"
  }
  readonly property var passCliEnvironment: ({
    "PROTON_PASS_LINUX_KEYRING": "dbus"
  })
  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/omarchy"
  readonly property string cachePath: cacheDir + "/proton-pass.json"
  readonly property int peerLockMs: 90000
  readonly property int directCliTimeoutMs: 45000

  property var _previewItem: null
  property var _previewQueue: []
  property string _urgentPreviewKey: ""
  property bool previewsEnabled: false
  property var _pendingPreviewUpdates: ({})
  property var _failedPreviewKeys: ({ map: {}, order: [] })
  property bool _previewSessionBlocked: false
  property string _fetchOutput: ""
  property string _fetchError: ""
  property string _copyError: ""
  property string _viewOutput: ""
  property string _viewError: ""
  property int _viewGeneration: 0
  property int _viewProcessGeneration: 0
  property bool _discardViewResult: true
  property string _previewOutput: ""
  property string _previewError: ""
  property string _createError: ""
  property string _createStdinPayload: ""
  property var _pendingCreateFields: null
  property string _clipboardPayload: ""
  property string _clipboardError: ""
  property bool _clipboardActive: false
  property string _generateOutput: ""
  property string _generateError: ""
  property bool _copyTimedOut: false
  property bool _clipboardTimedOut: false
  property bool _viewTimedOut: false
  property bool _previewTimedOut: false
  property bool _createTimedOut: false
  property bool _generateTimedOut: false
  property bool _inspectTimedOut: false
  property bool _totpTimedOut: false
  property string _inspectOutput: ""
  property string _inspectError: ""
  property string _totpOutput: ""
  property string _totpError: ""
  property string _inspectShareId: ""
  property string _inspectItemId: ""
  property int _lastTotpRemaining: 0
  property bool _writingCache: false
  property bool _cacheHydrated: false
  property bool _dirReady: false
  property bool _startupRefreshDone: false
  property bool _openWantsFresh: false
  property double _peerRefreshingAt: 0
  property double _pendingRefreshingAt: 0
  property string _lastCacheText: ""
  signal copied()
  signal copyFailed(string message)
  signal itemUpdated(var item)
  signal created()
  signal createFailed(string message)
  signal passwordGenerated(string password)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function pluginFile(name) {
    var url = String(Qt.resolvedUrl(name))
    if (url.indexOf("file://") === 0) return decodeURIComponent(url.slice(7))
    return url
  }

  function elideStatus(text) {
    return Model.displayError(text)
  }

  function resetViewed(forceKill) {
    _viewGeneration = _viewGeneration + 1
    _discardViewResult = true
    viewWatchdog.stop()
    if (viewProcess.running) {
      if (forceKill === true) viewProcess.signal(9)
      else viewProcess.signal(15)
      viewProcess.running = false
    }
    viewedValue = ""
    viewedField = ""
    viewing = false
    _viewOutput = ""
    _viewError = ""
  }

  function resetInspector(forceKill) {
    totpTickTimer.stop()
    inspectWatchdog.stop()
    totpWatchdog.stop()
    if (inspectProcess.running) {
      if (forceKill === true) inspectProcess.signal(9)
      else inspectProcess.signal(15)
      inspectProcess.running = false
    }
    if (totpProcess.running) {
      if (forceKill === true) totpProcess.signal(9)
      else totpProcess.signal(15)
      totpProcess.running = false
    }
    inspector = null
    totpCodes = ({})
    totpRemaining = 30
    inspecting = false
    totpLoading = false
    _inspectOutput = ""
    _inspectError = ""
    _totpOutput = ""
    _totpError = ""
    _inspectShareId = ""
    _inspectItemId = ""
    _lastTotpRemaining = 0
    _inspectTimedOut = false
    _totpTimedOut = false
  }

  function appendBounded(current, chunk, limit) {
    var existing = String(current || "")
    var incoming = String(chunk || "")
    var room = Math.max(0, limit - existing.length)
    return existing + incoming.slice(0, room)
  }

  function launchFailureMessage() {
    return "Could not start pass-cli."
  }

  function timeoutMessage(operation) {
    return operation + " timed out."
  }

  function handleCopyTimeout() {
    if (!copyProcess.running) return
    _copyTimedOut = true
    copying = false
    _copyError = ""
    copiedMessage = ""
    var message = timeoutMessage("Copy")
    lastError = message
    copyFailed(message)
    copyProcess.signal(9)
    copyProcess.running = false
  }

  function handleViewTimeout() {
    if (!viewProcess.running) return
    _viewTimedOut = true
    resetViewed(true)
    var message = timeoutMessage("Secret lookup")
    lastError = message
  }

  function handlePreviewTimeout() {
    if (!previewProcess.running) return
    _previewTimedOut = true
    var target = _previewItem
    _previewItem = null
    previewing = false
    _urgentPreviewKey = ""
    _previewOutput = ""
    _previewError = ""
    if (target) markPreviewFailed(Model.itemKey(target))
    lastError = timeoutMessage("Login preview")
    previewProcess.signal(9)
    previewProcess.running = false
    if (previewsEnabled) previewTimer.restart()
  }

  function handleCreateTimeout() {
    if (!createProcess.running) return
    _createTimedOut = true
    _createStdinPayload = ""
    _pendingCreateFields = null
    createProcess.stdinEnabled = false
    creating = false
    _createError = ""
    var message = timeoutMessage("Login creation")
    lastError = message
    createFailed(message)
    createProcess.signal(9)
    createProcess.running = false
  }

  function handleClipboardTimeout() {
    if (!clipboardProcess.running) return
    _clipboardTimedOut = true
    _clipboardActive = false
    _clipboardPayload = ""
    clipboardProcess.stdinEnabled = false
    _clipboardError = ""
    copiedMessage = ""
    var message = timeoutMessage("Copy")
    lastError = message
    copyFailed(message)
    clipboardProcess.signal(9)
    clipboardProcess.running = false
  }

  function handleGenerateTimeout() {
    if (!generateProcess.running) return
    _generateTimedOut = true
    var pendingCreate = _pendingCreateFields !== null
    _pendingCreateFields = null
    generatingPassword = false
    _generateOutput = ""
    _generateError = ""
    var message = timeoutMessage(pendingCreate ? "Login creation" : "Password generation")
    lastError = message
    if (pendingCreate) {
      creating = false
      createFailed(message)
    }
    generateProcess.signal(9)
    generateProcess.running = false
  }

  function handleInspectTimeout() {
    if (!inspectProcess.running) return
    _inspectTimedOut = true
    inspecting = false
    _inspectOutput = ""
    _inspectError = ""
    lastError = timeoutMessage("Item lookup")
    inspectProcess.signal(9)
    inspectProcess.running = false
  }

  function handleTotpTimeout() {
    if (!totpProcess.running) return
    _totpTimedOut = true
    totpLoading = false
    _totpOutput = ""
    _totpError = ""
    totpProcess.signal(9)
    totpProcess.running = false
  }

  function handleInspectLaunchFailure() {
    if (inspectProcess.running || !inspecting) return
    inspectWatchdog.stop()
    inspecting = false
    _inspectOutput = ""
    _inspectError = ""
    lastError = launchFailureMessage()
  }

  function handleTotpLaunchFailure() {
    if (totpProcess.running || !totpLoading) return
    totpWatchdog.stop()
    totpLoading = false
    _totpOutput = ""
    _totpError = ""
  }

  function handleCopyLaunchFailure() {
    if (copyProcess.running || !copying) return
    copyWatchdog.stop()
    copying = false
    _copyError = ""
    copiedMessage = ""
    lastError = launchFailureMessage()
    copyFailed(lastError)
  }

  function handleViewLaunchFailure() {
    if (viewProcess.running || !viewing) return
    viewWatchdog.stop()
    resetViewed()
    lastError = launchFailureMessage()
  }

  function handlePreviewLaunchFailure() {
    if (previewProcess.running || (!_previewItem && !previewing)) return
    previewWatchdog.stop()
    var target = _previewItem
    _previewItem = null
    previewing = false
    _urgentPreviewKey = ""
    _previewOutput = ""
    _previewError = ""
    if (target) markPreviewFailed(Model.itemKey(target))
    lastError = launchFailureMessage()
  }

  function handleCreateLaunchFailure() {
    if (createProcess.running || !creating || _pendingCreateFields !== null) return
    createWatchdog.stop()
    _createStdinPayload = ""
    createProcess.stdinEnabled = false
    creating = false
    _createError = ""
    lastError = launchFailureMessage()
    createFailed(lastError)
  }

  function handleClipboardLaunchFailure() {
    if (clipboardProcess.running || !_clipboardActive) return
    clipboardWatchdog.stop()
    _clipboardActive = false
    _clipboardPayload = ""
    clipboardProcess.stdinEnabled = false
    _clipboardError = ""
    copiedMessage = ""
    lastError = launchFailureMessage()
    copyFailed(lastError)
  }

  function handleGenerateLaunchFailure() {
    if (generateProcess.running || !generatingPassword) return
    generateWatchdog.stop()
    var pendingCreate = _pendingCreateFields !== null
    _pendingCreateFields = null
    generatingPassword = false
    _generateOutput = ""
    _generateError = ""
    lastError = launchFailureMessage()
    if (pendingCreate) {
      creating = false
      createFailed(lastError)
    }
  }

  function applyStatus(kind, message) {
    status = kind
    lastError = String(message || "")
    refreshing = false
    if (kind === "ready") {
      _previewSessionBlocked = false
      _failedPreviewKeys = Model.clearFailedPreviewKeys()
      if (previewsEnabled) previewTimer.restart()
    }
  }

  function statusMessageFor(kind, stderr) {
    if (kind === "missing") return "pass-cli is not installed"
    if (kind === "unauthenticated") return "Sign in with pass-cli login"
    if (kind === "locked") return "Session is locked. Run pass-cli session unlock"
    if (kind === "migration-required")
      return "Run pass-cli login in a terminal, then right-click the bar icon to refresh."
    return elideStatus(stderr) || "Could not load Proton Pass"
  }

  function isStale() {
    return fetchedAt === 0 || (Date.now() - fetchedAt) > cacheMs
  }

  function isPeerRefreshing() {
    if (_peerRefreshingAt <= 0) return false
    return (Date.now() - _peerRefreshingAt) < peerLockMs
  }

  function ensureFresh() {
    if (fetchProcess.running) return
    if (!_cacheHydrated) {
      _openWantsFresh = true
      return
    }
    if (items.length > 0 && !isStale()) return
    refresh(false)
  }

  function refresh(force, silent) {
    if (fetchProcess.running) return
    if (Model.isSessionBlockingStatus(status) && force !== true) return
    if (force !== true && !isStale()) return
    if (force !== true && isPeerRefreshing()) return
    if (force === true)
      _failedPreviewKeys = Model.clearFailedPreviewKeys()
    copiedMessage = ""
    copiedClearTimer.stop()
    resetViewed()
    var visible = silent === true ? items.length === 0 : (force === true || items.length === 0)
    if (visible) {
      if (items.length === 0 && status !== "missing" && status !== "unauthenticated" && status !== "locked" && status !== "migration-required")
        status = "loading"
      refreshing = true
    }
    lastError = ""
    _fetchOutput = ""
    _fetchError = ""
    _peerRefreshingAt = Date.now()
    writeCache(_peerRefreshingAt)
    fetchProcess.command = ["python3", pluginFile("fetch.py"), root.passCli]
    fetchProcess.running = true
  }

  function applyCache(raw) {
    var parsed = Model.parseCache(raw)
    _peerRefreshingAt = parsed.refreshingAt || 0
    _cacheHydrated = true
    if (parsed.ok && parsed.fetchedAt >= fetchedAt) {
      var previousFetchedAt = fetchedAt
      email = parsed.email || email
      items = Model.mergeItemLists(items, parsed.items)
      fetchedAt = parsed.fetchedAt
      if (parsed.warning) {
        fetchWarningMetadata = parsed.warning
        fetchWarning = String(parsed.warning.message || "")
      } else if (parsed.fetchedAt > previousFetchedAt) {
        fetchWarningMetadata = null
        fetchWarning = ""
      }
      if (items.length > 0 || parsed.fetchedAt > 0) {
        installed = true
        if (status === "idle" || status === "loading") applyStatus("ready", "")
      }
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
    if (!fetchProcess.running && (items.length === 0 || isStale()))
      refresh(false)
  }

  function writeCache(refreshingAt) {
    if (!_dirReady) return
    if (!_cacheHydrated && items.length === 0 && fetchedAt === 0 && !(refreshingAt > 0))
      return
    var started = refreshingAt !== undefined && refreshingAt !== null ? Number(refreshingAt) : _pendingRefreshingAt
    if (!isFinite(started)) started = 0
    _pendingRefreshingAt = started
    var doc = Model.serializeCache(email, fetchedAt, items, started, fetchWarningMetadata)
    var text = JSON.stringify(doc) + "\n"
    if (text === _lastCacheText) return
    _lastCacheText = text
    _writingCache = true
    cacheFile.setText(text)
    Qt.callLater(function() { root._writingCache = false })
  }

  function launchApp() {
    Quickshell.execDetached(["proton-pass"])
  }

  function createLogin(fields) {
    if (createProcess.running || generateProcess.running) return
    var data = fields && typeof fields === "object" ? fields : {}
    var title = String(data.title || "").trim()
    if (title === "") {
      lastError = "Title is required"
      createFailed(lastError)
      return
    }
    var password = String(data.password || "")
    lastError = ""
    creating = true
    _createError = ""
    _createStdinPayload = ""
    var request = Model.buildCreateLoginRequest({
      shareId: data.shareId,
      vaultName: data.vaultName,
      title: title,
      username: String(data.username || "").trim(),
      email: String(data.email || "").trim(),
      password: password,
      generatePassword: data.generatePassword === true || password === "",
      url: String(data.url || "").trim()
    })
    if (request.needsPasswordGeneration) {
      _pendingCreateFields = {
        shareId: data.shareId,
        vaultName: data.vaultName,
        title: title,
        username: String(data.username || "").trim(),
        email: String(data.email || "").trim(),
        url: String(data.url || "").trim()
      }
      generatingPassword = true
      _generateOutput = ""
      _generateError = ""
      generateProcess.command = [root.passCli, "password", "generate", "random", "--length", "20", "--uppercase", "true", "--symbols", "true"]
      _generateTimedOut = false
      generateWatchdog.restart()
      generateProcess.running = true
      return
    }
    startCreateProcess(request)
  }

  function startCreateProcess(request) {
    _pendingCreateFields = null
    _createStdinPayload = request.stdin
    createProcess.stdinEnabled = _createStdinPayload !== ""
    createProcess.command = [root.passCli].concat(request.args)
    _createTimedOut = false
    createWatchdog.restart()
    createProcess.running = true
  }

  function generatePassword() {
    if (generateProcess.running || creating) return
    generatingPassword = true
    _generateOutput = ""
    _generateError = ""
    generateProcess.command = [root.passCli, "password", "generate", "random", "--length", "20", "--uppercase", "true", "--symbols", "true"]
    _generateTimedOut = false
    generateWatchdog.restart()
    generateProcess.running = true
  }

  function clearCopied() {
    copiedClearTimer.stop()
    copiedMessage = ""
  }

  function showCopied() {
    copiedMessage = "Copied"
    copiedClearTimer.restart()
    copied()
    scheduleClipboardClear()
  }

  function scheduleClipboardClear() {
    clipboardClearTimer.stop()
    if (clipboardClearMs <= 0) return
    clipboardClearTimer.restart()
  }

  function stopClipboardClearProcess() {
    if (!clipboardClearProcess.running) return
    clipboardClearProcess.signal(15)
    clipboardClearProcess.running = false
  }

  function clearClipboard() {
    if (copyProcess.running || clipboardProcess.running) {
      if (clipboardClearMs > 0) clipboardClearTimer.restart()
      return
    }
    if (clipboardClearProcess.running) return
    clipboardClearProcess.command = ["timeout", "--signal=TERM", "--kill-after=2s", "10s", "wl-copy", "--clear"]
    clipboardClearProcess.running = true
  }

  function copyText(value) {
    var text = String(value || "")
    if (text === "" || clipboardProcess.running) return
    lastError = ""
    copiedMessage = ""
    copiedClearTimer.stop()
    stopClipboardClearProcess()
    _clipboardError = ""
    _clipboardPayload = text
    _clipboardActive = true
    clipboardProcess.stdinEnabled = true
    clipboardProcess.command = ["timeout", "--signal=TERM", "--kill-after=2s", "30s", "wl-copy"]
    _clipboardTimedOut = false
    clipboardWatchdog.restart()
    clipboardProcess.running = true
  }

  function copyField(item, field) {
    var uri = Model.passUri(item, field || "password")
    if (uri === "" || copyProcess.running) return
    touchItem(item)
    viewedField = String(field || "password")
    copiedMessage = ""
    copiedClearTimer.stop()
    stopClipboardClearProcess()
    copying = true
    lastError = ""
    _copyError = ""
    copyProcess.command = ["timeout", "--signal=TERM", "--kill-after=2s", "30s", "bash", "-o", "pipefail", "-c", "\"$0\" item view \"$1\" | wl-copy", root.passCli, uri]
    _copyTimedOut = false
    copyWatchdog.restart()
    copyProcess.running = true
  }

  function viewField(item, field) {
    var uri = Model.passUri(item, field || "password")
    if (uri === "" || viewProcess.running) return
    resetViewed()
    lastError = ""
    viewedField = String(field || "password")
    viewing = true
    _viewOutput = ""
    _viewError = ""
    _viewProcessGeneration = _viewGeneration
    _discardViewResult = false
    viewProcess.command = [root.passCli, "item", "view", uri]
    _viewTimedOut = false
    viewWatchdog.restart()
    viewProcess.running = true
  }

  function inspectItem(item) {
    if (!item) return
    var shareId = String(item.shareId || "")
    var itemId = String(item.id || "")
    if (shareId === "" || itemId === "") return
    resetInspector()
    lastError = ""
    _inspectShareId = shareId
    _inspectItemId = itemId
    inspecting = true
    _inspectOutput = ""
    _inspectError = ""
    inspectProcess.command = [root.passCli, "item", "view", "--share-id=" + shareId, "--item-id=" + itemId, "--output", "json"]
    _inspectTimedOut = false
    inspectWatchdog.restart()
    inspectProcess.running = true
  }

  function refreshTotp() {
    if (_inspectShareId === "" || _inspectItemId === "") return
    if (totpProcess.running) {
      totpProcess.signal(15)
      totpProcess.running = false
    }
    totpLoading = true
    _totpOutput = ""
    _totpError = ""
    totpProcess.command = [root.passCli, "item", "totp", "--share-id=" + _inspectShareId, "--item-id=" + _inspectItemId, "--output", "json"]
    _totpTimedOut = false
    totpWatchdog.restart()
    totpProcess.running = true
  }

  function previewItem(item) {
    if (!item || _previewSessionBlocked) return
    lastError = ""
    _urgentPreviewKey = Model.itemKey(item)
    enqueuePreview(item)
    startNextPreview(true)
  }

  function needsPreview(item) {
    return Model.needsPreview(item)
  }

  function enqueuePreview(item) {
    if (_previewSessionBlocked) return
    var current = findItem(item) || item
    if (!needsPreview(current)) return
    var key = Model.itemKey(current)
    if (key === "/" || key === "") return
    if (Model.hasFailedPreviewKey(_failedPreviewKeys, key)) return
    if (_previewItem && Model.itemKey(_previewItem) === key) return
    var next = []
    for (var i = 0; i < _previewQueue.length; i++) {
      if (Model.itemKey(_previewQueue[i]) !== key) next.push(_previewQueue[i])
    }
    next.unshift(current)
    if (next.length > 16) next = next.slice(0, 16)
    _previewQueue = next
  }

  function requestPreviews(list) {
    if (!previewsEnabled || _previewSessionBlocked) return
    var rows = list || []
    for (var i = rows.length - 1; i >= 0; i--) enqueuePreview(rows[i])
    if (!previewProcess.running) root.startNextPreview(false)
  }

  function clearUrgentPreview() {
    _urgentPreviewKey = ""
    previewing = false
  }

  function stopPreviews() {
    flushPendingPreviews()
    previewsEnabled = false
    _previewQueue = []
    _urgentPreviewKey = ""
    previewing = false
    previewTimer.stop()
    previewMergeTimer.stop()
    _pendingPreviewUpdates = ({})
    _failedPreviewKeys = Model.clearFailedPreviewKeys()
  }

  function markPreviewFailed(key) {
    _failedPreviewKeys = Model.rememberFailedPreviewKey(_failedPreviewKeys, key, 64)
  }

  function latchSessionBlockingFailure(kind, stderr) {
    if (!Model.isSessionBlockingStatus(kind)) return false
    _previewSessionBlocked = true
    previewWatchdog.stop()
    previewTimer.stop()
    previewMergeTimer.stop()
    if (previewProcess.running) {
      previewProcess.signal(15)
      previewProcess.running = false
    }
    _previewItem = null
    _previewQueue = []
    _urgentPreviewKey = ""
    previewing = false
    _previewOutput = ""
    _previewError = ""
    _pendingPreviewUpdates = ({})
    root.resetInspector(true)
    var message = statusMessageFor(kind, stderr)
    applyStatus(kind, message)
    return true
  }

  function queuePreviewUpdate(item, preview, urgent) {
    if (!item || !preview) return
    var key = Model.itemKey(item)
    if (key === "/" || key === "") return
    if (urgent === true) {
      flushPendingPreviews()
      replaceItem(Model.mergeItemPreview(findItem(item) || item, preview))
      return
    }
    var pending = {}
    var current = _pendingPreviewUpdates || {}
    var keys = Object.keys(current)
    for (var i = 0; i < keys.length; i++) pending[keys[i]] = current[keys[i]]
    pending[key] = preview
    _pendingPreviewUpdates = pending
    previewMergeTimer.restart()
  }

  function flushPendingPreviews() {
    previewMergeTimer.stop()
    var pending = _pendingPreviewUpdates || {}
    if (Object.keys(pending).length === 0) return
    _pendingPreviewUpdates = ({})
    var batch = Model.applyPreviewBatch(items, pending)
    if (batch.items === items && batch.updated.length === 0) return
    items = batch.items
    scheduleCacheWrite()
    var updated = batch.updated || []
    for (var i = 0; i < updated.length; i++) itemUpdated(updated[i])
  }

  function startNextPreview(urgent) {
    if (previewProcess.running || _previewSessionBlocked) return
    if (copyProcess.running || fetchProcess.running || viewProcess.running || inspectProcess.running) {
      if (previewsEnabled) previewTimer.restart()
      return
    }
    if (!previewsEnabled && urgent !== true) return
    while (_previewQueue.length > 0) {
      var next = _previewQueue.shift()
      var current = findItem(next) || next
      var key = Model.itemKey(current)
      if (Model.hasFailedPreviewKey(_failedPreviewKeys, key)) continue
      if (!needsPreview(current)) continue
      var uri = Model.passUri(current, "")
      if (uri === "") continue
      _previewItem = current
      previewing = _urgentPreviewKey !== "" && key === _urgentPreviewKey
      _previewOutput = ""
      _previewError = ""
      previewProcess.command = [root.passCli, "item", "view", uri, "--output", "json"]
      _previewTimedOut = false
      previewWatchdog.restart()
      previewProcess.running = true
      return
    }
  }

  function scheduleCacheWrite() {
    cacheWriteTimer.restart()
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
      if (current && current.id === updated.id && current.shareId === updated.shareId) next.push(updated)
      else next.push(current)
    }
    items = next
    itemUpdated(updated)
    scheduleCacheWrite()
  }

  function touchItem(item) {
    if (!item || !item.id) return
    replaceItem(Model.mergeItemPreview(item, { lastUsedAt: Date.now() }))
  }

  Timer {
    id: copiedClearTimer
    interval: 1500
    repeat: false
    onTriggered: root.copiedMessage = ""
  }

  Timer {
    id: clipboardClearTimer
    interval: root.clipboardClearMs
    repeat: false
    onTriggered: root.clearClipboard()
  }

  Timer {
    id: cacheWriteTimer
    interval: 1500
    repeat: false
    onTriggered: root.writeCache(fetchProcess.running ? root._peerRefreshingAt : 0)
  }

  Timer {
    id: previewTimer
    interval: 450
    repeat: false
    onTriggered: root.startNextPreview(false)
  }

  Timer {
    id: previewMergeTimer
    interval: 80
    repeat: false
    onTriggered: root.flushPendingPreviews()
  }

  Timer {
    id: copyWatchdog
    interval: root.directCliTimeoutMs
    repeat: false
    onTriggered: root.handleCopyTimeout()
  }

  Timer {
    id: viewWatchdog
    interval: root.directCliTimeoutMs
    repeat: false
    onTriggered: root.handleViewTimeout()
  }

  Timer {
    id: previewWatchdog
    interval: root.directCliTimeoutMs
    repeat: false
    onTriggered: root.handlePreviewTimeout()
  }

  Timer {
    id: createWatchdog
    interval: root.directCliTimeoutMs
    repeat: false
    onTriggered: root.handleCreateTimeout()
  }

  Timer {
    id: clipboardWatchdog
    interval: root.directCliTimeoutMs
    repeat: false
    onTriggered: root.handleClipboardTimeout()
  }

  Timer {
    id: generateWatchdog
    interval: root.directCliTimeoutMs
    repeat: false
    onTriggered: root.handleGenerateTimeout()
  }

  Timer {
    id: inspectWatchdog
    interval: root.directCliTimeoutMs
    repeat: false
    onTriggered: root.handleInspectTimeout()
  }

  Timer {
    id: totpWatchdog
    interval: root.directCliTimeoutMs
    repeat: false
    onTriggered: root.handleTotpTimeout()
  }

  Timer {
    id: totpTickTimer
    interval: 1000
    repeat: true
    onTriggered: {
      if (!root.inspector || root.inspector.hasTotp !== true) {
        stop()
        return
      }
      var remaining = Model.totpSecondsRemaining(Date.now(), 30)
      if (root._lastTotpRemaining > 0 && remaining > root._lastTotpRemaining)
        root.refreshTotp()
      root._lastTotpRemaining = remaining
      root.totpRemaining = remaining
    }
  }

  Component.onCompleted: ensureCacheDir.running = true

  Process {
    id: ensureCacheDir
    running: false
    command: ["mkdir", "-p", "-m", "0700", root.cacheDir]
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

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      if (!root._cacheHydrated || fetchProcess.running) return
      if (root.status === "missing" || Model.isSessionBlockingStatus(root.status)) return
      if (root.isStale()) root.refresh(false)
    }
  }

  Process {
    id: fetchProcess
    running: false
    command: []
    environment: root.passCliEnvironment
    stdout: StdioCollector { id: fetchStdout; waitForEnd: true; onStreamFinished: root._fetchOutput = text }
    stderr: StdioCollector { id: fetchStderr; waitForEnd: true; onStreamFinished: root._fetchError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      root._peerRefreshingAt = 0
      var stdout = String(fetchStdout.text || root._fetchOutput || "")
      var stderr = String(fetchStderr.text || root._fetchError || "")
      var parsed = Model.parseFetchResult(stdout)
      if (parsed.status === "busy") {
        root.writeCache(0)
        return
      }
      if (exitCode !== 0 && !parsed.ok) {
        var kind = parsed.status && parsed.status !== "error" ? parsed.status : Model.classifyError(stderr || stdout, exitCode)
        var failureMessage = root.statusMessageFor(kind, parsed.message || stderr || stdout)
        var blocked = root.latchSessionBlockingFailure(kind, parsed.message || stderr || stdout)
        if (!blocked) {
          if (root.items.length === 0) root.applyStatus(kind, failureMessage)
          else root.lastError = failureMessage
        }
        root.writeCache(0)
        return
      }
      if (!parsed.ok) {
        var parsedMessage = root.statusMessageFor(parsed.status, parsed.message)
        var parsedBlocked = root.latchSessionBlockingFailure(parsed.status, parsed.message)
        if (!parsedBlocked) {
          if (root.items.length === 0) root.applyStatus(parsed.status, parsedMessage)
          else root.lastError = parsedMessage
        }
        root.writeCache(0)
        return
      }
      root.installed = true
      root.email = parsed.email
      var warning = parsed.warning || null
      root.items = parsed.status === "partial"
        ? Model.mergePartialItemLists(root.items, parsed.items, warning ? warning.failedShareIds : [])
        : Model.mergeItemLists(root.items, parsed.items)
      root.fetchedAt = Date.now()
      if (parsed.status === "partial" && warning) {
        root.fetchWarningMetadata = warning
        root.fetchWarning = warning ? String(warning.message || "") : ""
      } else if (parsed.status !== "partial") {
        root.fetchWarningMetadata = null
        root.fetchWarning = ""
      }
      root.applyStatus("ready", "")
      root.writeCache(0)
    }
  }

  Process {
    id: copyProcess
    running: false
    command: []
    environment: root.passCliEnvironment
    stderr: StdioCollector { id: copyStderr; waitForEnd: true; onStreamFinished: root._copyError = text }
    onRunningChanged: {
      if (!running) Qt.callLater(function() { root.handleCopyLaunchFailure() })
    }
    onExited: function(exitCode) {
      copyWatchdog.stop()
      if (root._copyTimedOut) {
        root._copyTimedOut = false
        root._copyError = ""
        return
      }
      root.copying = false
      if (exitCode === 0) {
        root.showCopied()
        root.lastError = ""
      } else {
        var stderr = String(copyStderr.text || root._copyError || "")
        if (exitCode === 124 || exitCode === 137) {
          var timeoutError = root.timeoutMessage("Copy")
          root.copiedMessage = ""
          root.lastError = timeoutError
          root.copyFailed(timeoutError)
          root._copyError = ""
          return
        }
        var kind = Model.classifyError(stderr, exitCode)
        var message = root.statusMessageFor(kind, stderr)
        root.latchSessionBlockingFailure(kind, stderr)
        root.copiedMessage = ""
        root.lastError = message
        root.copyFailed(message)
      }
      root._copyError = ""
    }
  }

  Process {
    id: viewProcess
    running: false
    command: []
    environment: root.passCliEnvironment
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        if (root._discardViewResult || root._viewProcessGeneration !== root._viewGeneration) return
        root._viewOutput = root.appendBounded(root._viewOutput, data, 8192)
      }
    }
    stderr: StdioCollector {
      id: viewStderr
      waitForEnd: true
      onStreamFinished: {
        if (!root._discardViewResult && root._viewProcessGeneration === root._viewGeneration)
          root._viewError = text
      }
    }
    onRunningChanged: {
      if (!running) Qt.callLater(function() { root.handleViewLaunchFailure() })
    }
    onExited: function(exitCode) {
      viewWatchdog.stop()
      var completedGeneration = root._viewProcessGeneration
      var discard = root._discardViewResult || completedGeneration !== root._viewGeneration
      if (root._viewTimedOut) {
        root._viewTimedOut = false
        root._viewOutput = ""
        root._viewError = ""
        root._discardViewResult = true
        return
      }
      root.viewing = false
      var stdout = String(root._viewOutput || "")
      var stderr = String(viewStderr.text || root._viewError || "")
      root._viewOutput = ""
      root._viewError = ""
      root._discardViewResult = true
      if (discard) return
      if (exitCode === 0) {
        root.lastError = ""
        root.viewedValue = stdout.replace(/\n$/, "")
      } else {
        root.viewedValue = ""
        root.viewedField = ""
        var kind = Model.classifyError(stderr, exitCode)
        if (!root.latchSessionBlockingFailure(kind, stderr))
          root.lastError = root.statusMessageFor(kind, stderr)
      }
    }
  }

  Process {
    id: previewProcess
    running: false
    command: []
    environment: root.passCliEnvironment
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._previewOutput = root.appendBounded(root._previewOutput, data, 1048576) }
    }
    stderr: StdioCollector { id: previewStderr; waitForEnd: true; onStreamFinished: root._previewError = text }
    onRunningChanged: {
      if (!running) Qt.callLater(function() { root.handlePreviewLaunchFailure() })
    }
    onExited: function(exitCode) {
      previewWatchdog.stop()
      if (root._previewTimedOut) {
        root._previewTimedOut = false
        root._previewOutput = ""
        root._previewError = ""
        return
      }
      var target = root._previewItem
      var urgent = target && Model.itemKey(target) === root._urgentPreviewKey
      root._previewItem = null
      root.previewing = false
      if (urgent) root._urgentPreviewKey = ""
      var stdout = String(root._previewOutput || "")
      var stderr = String(previewStderr.text || root._previewError || "")
      root._previewOutput = ""
      root._previewError = ""
      if (exitCode === 0 && target) {
        var preview = Model.parseItemPreview(stdout)
        if (preview) {
          root.lastError = ""
          root.queuePreviewUpdate(root.findItem(target) || target, preview, urgent)
        } else {
          root.markPreviewFailed(Model.itemKey(target))
        }
      } else if (target) {
        var kind = Model.classifyError(stderr || stdout, exitCode)
        if (root.latchSessionBlockingFailure(kind, stderr || stdout)) {
          return
        }
        root.markPreviewFailed(Model.itemKey(target))
      }
      if (root.previewsEnabled) previewTimer.restart()
    }
  }

  Process {
    id: createProcess
    running: false
    command: []
    environment: root.passCliEnvironment
    stdinEnabled: false
    stderr: StdioCollector { id: createStderr; waitForEnd: true; onStreamFinished: root._createError = text }
    onStarted: {
      var payload = root._createStdinPayload
      if (payload !== "") write(payload)
      root._createStdinPayload = ""
      stdinEnabled = false
    }
    onRunningChanged: {
      if (!running) {
        root._createStdinPayload = ""
        stdinEnabled = false
        Qt.callLater(function() { root.handleCreateLaunchFailure() })
      }
    }
    onExited: function(exitCode) {
      createWatchdog.stop()
      root._createStdinPayload = ""
      stdinEnabled = false
      if (root._createTimedOut) {
        root._createTimedOut = false
        root._createError = ""
        return
      }
      root.creating = false
      root._pendingCreateFields = null
      if (exitCode === 0) {
        root.lastError = ""
        root.created()
        root.refresh(true, true)
      } else {
        var stderr = String(createStderr.text || root._createError || "")
        var kind = Model.classifyError(stderr, exitCode)
        var message = root.statusMessageFor(kind, stderr)
        if (!root.latchSessionBlockingFailure(kind, stderr))
          root.lastError = message
        root.createFailed(message)
      }
      root._createError = ""
    }
  }

  Process {
    id: generateProcess
    running: false
    command: []
    environment: root.passCliEnvironment
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._generateOutput = root.appendBounded(root._generateOutput, data, 4096) }
    }
    stderr: StdioCollector { id: generateStderr; waitForEnd: true; onStreamFinished: root._generateError = text }
    onRunningChanged: {
      if (!running) Qt.callLater(function() { root.handleGenerateLaunchFailure() })
    }
    onExited: function(exitCode) {
      generateWatchdog.stop()
      if (root._generateTimedOut) {
        root._generateTimedOut = false
        root._generateOutput = ""
        root._generateError = ""
        return
      }
      root.generatingPassword = false
      var stdout = String(root._generateOutput || "").replace(/\n$/, "")
      var stderr = String(generateStderr.text || root._generateError || "")
      root._generateOutput = ""
      root._generateError = ""
      var pendingCreate = root._pendingCreateFields
      if (pendingCreate) {
        root._pendingCreateFields = null
        if (exitCode === 0 && stdout !== "") {
          var followUp = Model.buildCreateLoginRequest({
            shareId: pendingCreate.shareId,
            vaultName: pendingCreate.vaultName,
            title: pendingCreate.title,
            username: pendingCreate.username,
            email: pendingCreate.email,
            password: stdout,
            generatePassword: false,
            url: pendingCreate.url
          })
          root.startCreateProcess(followUp)
          return
        }
        root.creating = false
        var pendingKind = Model.classifyError(stderr || stdout, exitCode)
        var pendingMessage = exitCode === 0
          ? "Password generation returned no password."
          : root.statusMessageFor(pendingKind, stderr || stdout)
        if (exitCode !== 0)
          root.latchSessionBlockingFailure(pendingKind, stderr || stdout)
        if (root.lastError === "") root.lastError = pendingMessage
        root.createFailed(pendingMessage)
        return
      }
      if (exitCode === 0) {
        if (stdout !== "") {
          root.lastError = ""
          root.passwordGenerated(stdout)
        } else {
          root.lastError = "Password generation returned no password."
        }
      } else {
        var kind = Model.classifyError(stderr || stdout, exitCode)
        if (!root.latchSessionBlockingFailure(kind, stderr || stdout))
          root.lastError = root.statusMessageFor(kind, stderr || stdout)
      }
    }
  }

  Process {
    id: clipboardProcess
    running: false
    command: []
    stdinEnabled: false
    stderr: StdioCollector { id: clipboardStderr; waitForEnd: true; onStreamFinished: root._clipboardError = text }
    onStarted: {
      var payload = root._clipboardPayload
      if (payload !== "") write(payload)
      root._clipboardPayload = ""
      stdinEnabled = false
    }
    onRunningChanged: {
      if (!running) {
        root._clipboardPayload = ""
        stdinEnabled = false
        Qt.callLater(function() { root.handleClipboardLaunchFailure() })
      }
    }
    onExited: function(exitCode) {
      clipboardWatchdog.stop()
      root._clipboardPayload = ""
      stdinEnabled = false
      if (root._clipboardTimedOut) {
        root._clipboardTimedOut = false
        root._clipboardActive = false
        root._clipboardError = ""
        return
      }
      root._clipboardActive = false
      if (exitCode === 0) {
        root.showCopied()
        root.lastError = ""
      } else {
        var stderr = String(clipboardStderr.text || root._clipboardError || "")
        var message = (exitCode === 124 || exitCode === 137)
          ? root.timeoutMessage("Copy")
          : (root.elideStatus(stderr) || root.launchFailureMessage())
        root.copiedMessage = ""
        root.lastError = message
        root.copyFailed(message)
      }
      root._clipboardError = ""
    }
  }

  Process {
    id: inspectProcess
    running: false
    command: []
    environment: root.passCliEnvironment
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._inspectOutput = root.appendBounded(root._inspectOutput, data, 1048576) }
    }
    stderr: StdioCollector { id: inspectStderr; waitForEnd: true; onStreamFinished: root._inspectError = text }
    onRunningChanged: {
      if (!running) Qt.callLater(function() { root.handleInspectLaunchFailure() })
    }
    onExited: function(exitCode) {
      inspectWatchdog.stop()
      if (root._inspectTimedOut) {
        root._inspectTimedOut = false
        root._inspectOutput = ""
        root._inspectError = ""
        root.inspecting = false
        return
      }
      root.inspecting = false
      var stdout = String(root._inspectOutput || "")
      var stderr = String(inspectStderr.text || root._inspectError || "")
      root._inspectOutput = ""
      root._inspectError = ""
      if (exitCode === 0) {
        var parsed = Model.parseItemInspector(stdout)
        if (parsed) {
          root.lastError = ""
          root.inspector = parsed
          if (parsed.hasTotp === true) {
            root.totpRemaining = Model.totpSecondsRemaining(Date.now(), 30)
            root._lastTotpRemaining = root.totpRemaining
            totpTickTimer.restart()
            root.refreshTotp()
          }
        } else {
          root.inspector = null
          root.lastError = "Could not read this item."
        }
      } else {
        root.inspector = null
        var kind = Model.classifyError(stderr || stdout, exitCode)
        if (!root.latchSessionBlockingFailure(kind, stderr || stdout))
          root.lastError = root.statusMessageFor(kind, stderr || stdout)
      }
    }
  }

  Process {
    id: totpProcess
    running: false
    command: []
    environment: root.passCliEnvironment
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._totpOutput = root.appendBounded(root._totpOutput, data, 8192) }
    }
    stderr: StdioCollector { id: totpStderr; waitForEnd: true; onStreamFinished: root._totpError = text }
    onRunningChanged: {
      if (!running) Qt.callLater(function() { root.handleTotpLaunchFailure() })
    }
    onExited: function(exitCode) {
      totpWatchdog.stop()
      if (root._totpTimedOut) {
        root._totpTimedOut = false
        root._totpOutput = ""
        root._totpError = ""
        root.totpLoading = false
        return
      }
      root.totpLoading = false
      var stdout = String(root._totpOutput || "")
      var stderr = String(totpStderr.text || root._totpError || "")
      root._totpOutput = ""
      root._totpError = ""
      if (exitCode === 0) {
        root.totpCodes = Model.parseTotpCodes(stdout)
      } else {
        var kind = Model.classifyError(stderr || stdout, exitCode)
        if (!root.latchSessionBlockingFailure(kind, stderr || stdout))
          root.totpCodes = ({})
      }
    }
  }

  Process {
    id: clipboardClearProcess
    running: false
    command: []
  }
}
