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
  property bool previewing: false
  property bool creating: false
  property bool generatingPassword: false
  property string status: "idle"  // idle | loading | ready | missing | unauthenticated | locked | migration-required | error
  property string lastError: ""
  property string fetchWarning: ""
  property string email: ""
  property var items: []
  property string copiedMessage: ""
  property string viewedValue: ""
  property string viewedField: ""
  property double fetchedAt: 0

  readonly property int cacheMs: {
    var minutes = parseInt(String(setting("cacheMinutes", 15)), 10)
    if (!isFinite(minutes) || minutes < 1) minutes = 15
    if (minutes > 120) minutes = 120
    return minutes * 60 * 1000
  }
  readonly property bool busy: fetchProcess.running || copyProcess.running || viewProcess.running || previewProcess.running || createProcess.running || generateProcess.running
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
  property string _previewOutput: ""
  property string _previewError: ""
  property string _createError: ""
  property string _createStdinPayload: ""
  property string _generateOutput: ""
  property string _generateError: ""
  property bool _copyTimedOut: false
  property bool _viewTimedOut: false
  property bool _previewTimedOut: false
  property bool _createTimedOut: false
  property bool _generateTimedOut: false
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

  function resetViewed() {
    viewedValue = ""
    viewedField = ""
    viewing = false
    _viewOutput = ""
    _viewError = ""
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
    resetViewed()
    var message = timeoutMessage("Secret lookup")
    lastError = message
    viewProcess.signal(9)
    viewProcess.running = false
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
    createProcess.stdinEnabled = false
    creating = false
    _createError = ""
    var message = timeoutMessage("Login creation")
    lastError = message
    createFailed(message)
    createProcess.signal(9)
    createProcess.running = false
  }

  function handleGenerateTimeout() {
    if (!generateProcess.running) return
    _generateTimedOut = true
    generatingPassword = false
    _generateOutput = ""
    _generateError = ""
    lastError = timeoutMessage("Password generation")
    generateProcess.signal(9)
    generateProcess.running = false
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
    if (createProcess.running || !creating) return
    createWatchdog.stop()
    _createStdinPayload = ""
    createProcess.stdinEnabled = false
    creating = false
    _createError = ""
    lastError = launchFailureMessage()
    createFailed(lastError)
  }

  function handleGenerateLaunchFailure() {
    if (generateProcess.running || !generatingPassword) return
    generateWatchdog.stop()
    generatingPassword = false
    _generateOutput = ""
    _generateError = ""
    lastError = launchFailureMessage()
  }

  function applyStatus(kind, message) {
    status = kind
    lastError = String(message || "")
    refreshing = false
    if (kind === "ready") {
      _previewSessionBlocked = false
      _failedPreviewKeys = Model.clearFailedPreviewKeys()
    }
  }

  function statusMessageFor(kind, stderr) {
    if (kind === "missing") return "pass-cli is not installed"
    if (kind === "unauthenticated") return "Sign in with pass-cli login"
    if (kind === "locked") return "Session is locked. Run pass-cli session unlock"
    if (kind === "migration-required")
      return "PROTON_PASS_LINUX_KEYRING=dbus pass-cli logout --force\nPROTON_PASS_LINUX_KEYRING=dbus pass-cli login"
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
    if (status === "migration-required" && force !== true) return
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
      email = parsed.email || email
      items = Model.mergeItemLists(items, parsed.items)
      fetchedAt = parsed.fetchedAt
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
    var doc = Model.serializeCache(email, fetchedAt, items, started)
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
    if (createProcess.running) return
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
    _createStdinPayload = request.stdin
    createProcess.stdinEnabled = _createStdinPayload !== ""
    createProcess.command = [root.passCli].concat(request.args)
    _createTimedOut = false
    createWatchdog.restart()
    createProcess.running = true
  }

  function generatePassword() {
    if (generateProcess.running) return
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
  }

  function copyText(value) {
    var text = String(value || "")
    if (text === "") return
    lastError = ""
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    showCopied()
  }

  function copyField(item, field) {
    var uri = Model.passUri(item, field || "password")
    if (uri === "" || copyProcess.running) return
    touchItem(item)
    viewedField = String(field || "password")
    copiedMessage = ""
    copiedClearTimer.stop()
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
    viewProcess.command = [root.passCli, "item", "view", uri]
    _viewTimedOut = false
    viewWatchdog.restart()
    viewProcess.running = true
  }

  function previewItem(item) {
    if (!item || _previewSessionBlocked) return
    lastError = ""
    _urgentPreviewKey = Model.itemKey(item)
    enqueuePreview(item)
    startNextPreview(true)
  }

  function needsPreview(item) {
    if (!item) return false
    if (String(item.username || "") !== "" || String(item.email || "") !== "") return false
    if (item.urls && item.urls.length > 0) return false
    return Model.passUri(item, "") !== ""
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

  function blockPreviewSession(kind, stderr) {
    _previewSessionBlocked = true
    if (previewProcess.running) previewProcess.running = false
    stopPreviews()
    var message = statusMessageFor(kind, stderr)
    if (lastError === "" || status !== kind)
      applyStatus(kind, message)
    else
      lastError = message
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
    if (copyProcess.running || fetchProcess.running || viewProcess.running) {
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
    id: generateWatchdog
    interval: root.directCliTimeoutMs
    repeat: false
    onTriggered: root.handleGenerateTimeout()
  }

  Component.onCompleted: ensureCacheDir.running = true

  Process {
    id: ensureCacheDir
    running: false
    command: ["mkdir", "-p", root.cacheDir]
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
        if (kind === "migration-required") root.blockPreviewSession(kind, parsed.message || stderr || stdout)
        else if (root.items.length === 0) root.applyStatus(kind, failureMessage)
        else root.lastError = failureMessage
        root.writeCache(0)
        return
      }
      if (!parsed.ok) {
        var parsedMessage = root.statusMessageFor(parsed.status, parsed.message)
        if (parsed.status === "migration-required") root.blockPreviewSession(parsed.status, parsed.message)
        else if (root.items.length === 0) root.applyStatus(parsed.status, parsedMessage)
        else root.lastError = parsedMessage
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
      if (parsed.status === "partial")
        root.fetchWarning = warning ? String(warning.message || "") : ""
      else
        root.fetchWarning = ""
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
        if (Model.isSessionBlockingStatus(kind)) root.blockPreviewSession(kind, stderr)
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
      onRead: function(data) { root._viewOutput = root.appendBounded(root._viewOutput, data, 8192) }
    }
    stderr: StdioCollector { id: viewStderr; waitForEnd: true; onStreamFinished: root._viewError = text }
    onRunningChanged: {
      if (!running) Qt.callLater(function() { root.handleViewLaunchFailure() })
    }
    onExited: function(exitCode) {
      viewWatchdog.stop()
      if (root._viewTimedOut) {
        root._viewTimedOut = false
        root._viewOutput = ""
        root._viewError = ""
        return
      }
      root.viewing = false
      var stdout = String(root._viewOutput || "")
      var stderr = String(viewStderr.text || root._viewError || "")
      root._viewOutput = ""
      root._viewError = ""
      if (exitCode === 0) {
        root.lastError = ""
        root.viewedValue = stdout.replace(/\n$/, "")
      } else {
        root.resetViewed()
        var kind = Model.classifyError(stderr, exitCode)
        if (kind === "migration-required") root.blockPreviewSession(kind, stderr)
        else root.lastError = root.statusMessageFor(kind, stderr)
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
        }
      } else if (target) {
        var kind = Model.classifyError(stderr || stdout, exitCode)
        if (Model.isSessionBlockingStatus(kind)) {
          root.blockPreviewSession(kind, stderr || stdout)
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
      if (exitCode === 0) {
        root.lastError = ""
        root.created()
        root.refresh(true, true)
      } else {
        var stderr = String(createStderr.text || root._createError || "")
        var kind = Model.classifyError(stderr, exitCode)
        var message = root.statusMessageFor(kind, stderr)
        if (kind === "migration-required") root.blockPreviewSession(kind, stderr)
        else root.lastError = message
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
      if (exitCode === 0 && stdout !== "") {
        root.passwordGenerated(stdout)
      } else if (exitCode !== 0) {
        var kind = Model.classifyError(stderr || stdout, exitCode)
        if (kind === "migration-required") root.blockPreviewSession(kind, stderr || stdout)
        else root.lastError = root.statusMessageFor(kind, stderr || stdout)
      }
    }
  }
}
