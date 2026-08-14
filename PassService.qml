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
  property string status: "idle"  // idle | loading | ready | missing | unauthenticated | locked | error
  property string lastError: ""
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
  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/omarchy"
  readonly property string cachePath: cacheDir + "/proton-pass.json"
  readonly property int peerLockMs: 90000

  property var _previewItem: null
  property var _previewQueue: []
  property string _urgentPreviewKey: ""
  property bool previewsEnabled: false
  property string _fetchOutput: ""
  property string _fetchError: ""
  property string _copyError: ""
  property string _viewOutput: ""
  property string _viewError: ""
  property string _previewOutput: ""
  property string _previewError: ""
  property string _createError: ""
  property string _generateOutput: ""
  property bool _writingCache: false
  property bool _cacheHydrated: false
  property bool _dirReady: false
  property bool _startupRefreshDone: false
  property bool _openWantsFresh: false
  property double _peerRefreshingAt: 0
  property double _pendingRefreshingAt: 0

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
  }

  function applyStatus(kind, message) {
    status = kind
    lastError = String(message || "")
    refreshing = false
  }

  function statusMessageFor(kind, stderr) {
    if (kind === "missing") return "pass-cli is not installed"
    if (kind === "unauthenticated") return "Sign in with pass-cli login"
    if (kind === "locked") return "Session is locked. Run pass-cli session unlock"
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
    if (force !== true && !isStale()) return
    if (force !== true && isPeerRefreshing()) return
    copiedMessage = ""
    copiedClearTimer.stop()
    resetViewed()
    var visible = silent === true ? items.length === 0 : (force === true || items.length === 0)
    if (visible) {
      if (items.length === 0 && status !== "missing" && status !== "unauthenticated" && status !== "locked")
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
    _writingCache = true
    cacheFile.setText(JSON.stringify(doc) + "\n")
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
    var password = String(data.password || "").trim()
    lastError = ""
    creating = true
    _createError = ""
    var args = Model.buildCreateLoginCommand({
      shareId: data.shareId,
      vaultName: data.vaultName,
      title: title,
      username: String(data.username || "").trim(),
      email: String(data.email || "").trim(),
      password: password,
      generatePassword: data.generatePassword === true || password === "",
      url: String(data.url || "").trim()
    })
    createProcess.command = [root.passCli].concat(args)
    createProcess.running = true
  }

  function generatePassword() {
    if (generateProcess.running) return
    generatingPassword = true
    _generateOutput = ""
    generateProcess.command = [root.passCli, "password", "generate", "random", "--length", "20", "--uppercase", "true", "--symbols", "true"]
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
    copyProcess.command = ["bash", "-c", Util.shellQuote(root.passCli) + " item view " + Util.shellQuote(uri) + " | wl-copy"]
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
    viewProcess.running = true
  }

  function previewItem(item) {
    if (!item) return
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
    var current = findItem(item) || item
    if (!needsPreview(current)) return
    var key = Model.itemKey(current)
    if (key === "/" || key === "") return
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
    if (!previewsEnabled) return
    var rows = list || []
    for (var i = rows.length - 1; i >= 0; i--) enqueuePreview(rows[i])
    if (!previewProcess.running) root.startNextPreview(false)
  }

  function clearUrgentPreview() {
    _urgentPreviewKey = ""
    previewing = false
  }

  function stopPreviews() {
    previewsEnabled = false
    _previewQueue = []
    _urgentPreviewKey = ""
    previewing = false
    previewTimer.stop()
  }

  function startNextPreview(urgent) {
    if (previewProcess.running) return
    if (copyProcess.running || fetchProcess.running || viewProcess.running) {
      if (previewsEnabled) previewTimer.restart()
      return
    }
    if (!previewsEnabled && urgent !== true) return
    while (_previewQueue.length > 0) {
      var next = _previewQueue.shift()
      var current = findItem(next) || next
      if (!needsPreview(current)) continue
      var uri = Model.passUri(current, "")
      if (uri === "") continue
      _previewItem = current
      previewing = _urgentPreviewKey !== "" && Model.itemKey(current) === _urgentPreviewKey
      _previewOutput = ""
      _previewError = ""
      previewProcess.command = [root.passCli, "item", "view", uri, "--output", "json"]
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
    interval: 800
    repeat: false
    onTriggered: root.writeCache(fetchProcess.running ? root._peerRefreshingAt : 0)
  }

  Timer {
    id: previewTimer
    interval: 450
    repeat: false
    onTriggered: root.startNextPreview(false)
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
      root.applyCache(text())
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
      if (root.status === "missing" || root.status === "unauthenticated") return
      if (root.isStale()) root.refresh(false)
    }
  }

  Process {
    id: fetchProcess
    running: false
    command: []
    stdout: StdioCollector { id: fetchStdout; waitForEnd: true; onStreamFinished: root._fetchOutput = text }
    stderr: StdioCollector { id: fetchStderr; waitForEnd: true; onStreamFinished: root._fetchError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      root._peerRefreshingAt = 0
      var stdout = String(fetchStdout.text || root._fetchOutput || "")
      var stderr = String(fetchStderr.text || root._fetchError || "")
      var parsed = Model.parseFetchResult(stdout)
      if (exitCode !== 0 && !parsed.ok) {
        var kind = parsed.status && parsed.status !== "error" ? parsed.status : Model.classifyError(stderr || stdout, exitCode)
        if (root.items.length === 0) root.applyStatus(kind, root.statusMessageFor(kind, parsed.message || stderr || stdout))
        else root.lastError = root.statusMessageFor(kind, parsed.message || stderr || stdout)
        root.writeCache(0)
        return
      }
      if (!parsed.ok) {
        if (root.items.length === 0) root.applyStatus(parsed.status, root.statusMessageFor(parsed.status, parsed.message))
        else root.lastError = root.statusMessageFor(parsed.status, parsed.message)
        root.writeCache(0)
        return
      }
      root.installed = true
      root.email = parsed.email
      root.items = Model.mergeItemLists(root.items, parsed.items)
      root.fetchedAt = Date.now()
      root.applyStatus("ready", "")
      root.writeCache(0)
    }
  }

  Process {
    id: copyProcess
    running: false
    command: []
    stderr: StdioCollector { id: copyStderr; waitForEnd: true; onStreamFinished: root._copyError = text }
    onExited: function(exitCode) {
      root.copying = false
      if (exitCode === 0) {
        root.showCopied()
        root.lastError = ""
      } else {
        var stderr = String(copyStderr.text || root._copyError || "")
        var kind = Model.classifyError(stderr, exitCode)
        var message = root.statusMessageFor(kind, stderr)
        root.copiedMessage = ""
        root.lastError = message
        root.copyFailed(message)
      }
    }
  }

  Process {
    id: viewProcess
    running: false
    command: []
    stdout: StdioCollector { id: viewStdout; waitForEnd: true; onStreamFinished: root._viewOutput = text }
    stderr: StdioCollector { id: viewStderr; waitForEnd: true; onStreamFinished: root._viewError = text }
    onExited: function(exitCode) {
      root.viewing = false
      var stdout = String(viewStdout.text || root._viewOutput || "")
      var stderr = String(viewStderr.text || root._viewError || "")
      if (exitCode === 0) {
        root.lastError = ""
        root.viewedValue = stdout.replace(/\n$/, "")
      } else {
        root.resetViewed()
        var kind = Model.classifyError(stderr, exitCode)
        root.lastError = root.statusMessageFor(kind, stderr)
      }
    }
  }

  Process {
    id: previewProcess
    running: false
    command: []
    stdout: StdioCollector { id: previewStdout; waitForEnd: true; onStreamFinished: root._previewOutput = text }
    stderr: StdioCollector { id: previewStderr; waitForEnd: true; onStreamFinished: root._previewError = text }
    onExited: function(exitCode) {
      var target = root._previewItem
      root._previewItem = null
      root.previewing = false
      if (target && Model.itemKey(target) === root._urgentPreviewKey)
        root._urgentPreviewKey = ""
      var stdout = String(previewStdout.text || root._previewOutput || "")
      if (exitCode === 0 && target) {
        var preview = Model.parseItemPreview(stdout)
        if (preview) {
          root.lastError = ""
          root.replaceItem(Model.mergeItemPreview(root.findItem(target) || target, preview))
        }
      }
      if (root.previewsEnabled) previewTimer.restart()
    }
  }

  Process {
    id: createProcess
    running: false
    command: []
    stderr: StdioCollector { id: createStderr; waitForEnd: true; onStreamFinished: root._createError = text }
    onExited: function(exitCode) {
      root.creating = false
      if (exitCode === 0) {
        root.lastError = ""
        root.created()
        root.refresh(true, true)
      } else {
        var stderr = String(createStderr.text || root._createError || "")
        var kind = Model.classifyError(stderr, exitCode)
        var message = root.statusMessageFor(kind, stderr)
        root.lastError = message
        root.createFailed(message)
      }
    }
  }

  Process {
    id: generateProcess
    running: false
    command: []
    stdout: StdioCollector { id: generateStdout; waitForEnd: true; onStreamFinished: root._generateOutput = text }
    onExited: function(exitCode) {
      root.generatingPassword = false
      var stdout = String(generateStdout.text || root._generateOutput || "").replace(/\n$/, "")
      root._generateOutput = ""
      if (exitCode === 0 && stdout !== "") root.passwordGenerated(stdout)
    }
  }
}
