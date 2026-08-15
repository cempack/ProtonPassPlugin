// Pure helpers for the Proton Pass panel. Qt-free so node can unit-test it.

function parseJson(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  try {
    return JSON.parse(text)
  } catch (e) {
    return null
  }
}

function asArray(value) {
  if (Array.isArray(value)) return value
  if (value && Array.isArray(value.items)) return value.items
  if (value && Array.isArray(value.vaults)) return value.vaults
  return []
}

function stringField(obj, keys) {
  if (!obj || typeof obj !== "object") return ""
  for (var i = 0; i < keys.length; i++) {
    var value = obj[keys[i]]
    if (value !== undefined && value !== null && String(value) !== "") return String(value)
  }
  return ""
}

function loginPayload(raw) {
  if (!raw || typeof raw !== "object") return null
  var content = raw.content
  if (content && typeof content === "object") {
    if (content.Login && typeof content.Login === "object") return content.Login
    if (content.login && typeof content.login === "object") return content.login
    var nested = content.content
    if (nested && typeof nested === "object") {
      if (nested.Login && typeof nested.Login === "object") return nested.Login
      if (nested.login && typeof nested.login === "object") return nested.login
    }
  }
  if (raw.Login && typeof raw.Login === "object") return raw.Login
  return null
}

function isLogin(raw, payload) {
  var type = stringField(raw, ["item_type", "itemType", "type"]).toLowerCase().replace(/_/g, "")
  if (type === "login") return true
  if (payload) return true
  return false
}

function urlsFrom(payload, raw) {
  var source = payload && Array.isArray(payload.urls) ? payload.urls
    : (raw && Array.isArray(raw.urls) ? raw.urls : [])
  var out = []
  for (var i = 0; i < source.length; i++) {
    var url = String(source[i] || "").trim()
    if (url) out.push(url)
  }
  return out
}

function hasTotpFrom(payload) {
  if (!payload) return false
  var uri = stringField(payload, ["totp_uri", "totpUri", "totp"])
  return uri !== ""
}

function normalizeItem(raw, vaultName) {
  if (!raw || typeof raw !== "object") return null
  var payload = loginPayload(raw)
  if (!isLogin(raw, payload)) return null

  var content = raw.content && typeof raw.content === "object" ? raw.content : null
  var title = stringField(raw, ["title"]) || stringField(content, ["title"])
  var username = stringField(payload, ["username"]) || stringField(raw, ["username"])
  var email = stringField(payload, ["email"]) || stringField(raw, ["email"])

  return {
    id: stringField(raw, ["id", "item_id", "itemId"]),
    shareId: stringField(raw, ["share_id", "shareId"]),
    vaultId: stringField(raw, ["vault_id", "vaultId"]),
    vaultName: String(vaultName || ""),
    title: title,
    itemType: "login",
    username: username,
    email: email,
    urls: urlsFrom(payload, raw),
    createTime: stringField(raw, ["create_time", "createTime"]),
    modifyTime: stringField(raw, ["modify_time", "modifyTime"]),
    hasTotp: hasTotpFrom(payload),
    state: stringField(raw, ["state"]) || "Active",
    lastUsedAt: Number(raw.lastUsedAt || raw.last_used_at || 0) || 0
  }
}

function parseItemList(raw, vaultName) {
  var parsed = parseJson(raw)
  if (parsed === null) return []
  var rows = asArray(parsed)
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var item = normalizeItem(rows[i], vaultName)
    if (item) out.push(item)
  }
  return out
}

function parseVaultList(raw) {
  var parsed = parseJson(raw)
  if (parsed === null) return []
  var rows = asArray(parsed)
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row || typeof row !== "object") continue
    var shareId = stringField(row, ["share_id", "shareId", "id"])
    if (!shareId) continue
    out.push({
      shareId: shareId,
      name: stringField(row, ["name", "vault_name", "vaultName", "display_name"]) || shareId
    })
  }
  return out
}

function parseInfo(raw) {
  var parsed = parseJson(raw)
  if (!parsed || typeof parsed !== "object") return { ok: false }
  return {
    ok: true,
    email: stringField(parsed, ["email"]),
    username: stringField(parsed, ["username"]),
    sessionHasLock: parsed.session_has_lock === true || parsed.sessionHasLock === true
  }
}

function accountLabel(item) {
  if (!item) return ""
  return String(item.username || item.email || "")
}

function displayHost(url) {
  var s = String(url || "").trim()
  if (s === "") return ""
  s = s.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").replace(/^www\./i, "")
  var cut = s.search(/[/:?#]/)
  if (cut >= 0) s = s.slice(0, cut)
  return s
}

function itemSubtitle(item) {
  if (!item) return ""
  var urls = item.urls || []
  var parts = [item.username, item.email, displayHost(urls.length > 0 ? urls[0] : ""), item.vaultName]
  var seen = {}
  var out = []
  var title = String(item.title || "").trim().toLowerCase()
  for (var i = 0; i < parts.length; i++) {
    var part = String(parts[i] || "").trim()
    if (part === "") continue
    var key = part.toLowerCase()
    if (seen[key] || key === title) continue
    seen[key] = true
    out.push(part)
  }
  if (out.length === 0) return String(item.vaultName || "")
  return out.join(" · ")
}

function letterGlyph(title) {
  var text = String(title || "")
  var match = text.match(/[A-Za-z0-9]/)
  return match ? match[0].toUpperCase() : "?"
}

function passUri(item, field) {
  if (!item) return ""
  var shareId = String(item.shareId || "")
  var id = String(item.id || "")
  if (!shareId || !id) return ""
  var suffix = field ? "/" + String(field) : ""
  return "pass://" + shareId + "/" + id + suffix
}

function haystackFor(item) {
  var parts = [item.title, item.username, item.email, item.vaultName]
  var urls = item.urls || []
  for (var i = 0; i < urls.length; i++) parts.push(urls[i], hostnameToken(urls[i]))
  return parts.join(" ").toLowerCase()
}

function hostnameToken(url) {
  var s = String(url || "").toLowerCase()
  s = s.replace(/^https?:\/\//, "").replace(/^www\./, "")
  var cut = s.search(/[/:?#]/)
  if (cut >= 0) s = s.slice(0, cut)
  var parts = s.split(".")
  if (parts.length >= 2) return parts[parts.length - 2]
  return s
}

function searchItems(items, query) {
  var list = items || []
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return list.slice()
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (haystackFor(list[i]).indexOf(needle) >= 0) out.push(list[i])
  }
  return out
}

function suggestedItems(items, appId, title) {
  var hint = (String(appId || "") + " " + String(title || "")).trim().toLowerCase()
  if (!hint) return []
  var list = items || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    var titleText = String(item.title || "").toLowerCase()
    if (titleText && hint.indexOf(titleText) >= 0) {
      out.push(item)
      continue
    }
    var urls = item.urls || []
    var matched = false
    for (var u = 0; u < urls.length && !matched; u++) {
      var host = hostnameToken(urls[u])
      if (host && hint.indexOf(host) >= 0) matched = true
    }
    if (matched) out.push(item)
  }
  return out
}

function recentlyCreated(items, limit) {
  var list = (items || []).slice()
  list.sort(function (a, b) {
    return String(b.createTime || "").localeCompare(String(a.createTime || ""))
  })
  var cap = parseInt(limit, 10)
  if (!isFinite(cap) || cap < 0) cap = list.length
  return list.slice(0, cap)
}

function usageTime(item) {
  if (!item) return 0
  var used = Number(item.lastUsedAt || 0)
  if (isFinite(used) && used > 0) return used
  var modified = Date.parse(String(item.modifyTime || ""))
  if (isFinite(modified)) return modified
  var created = Date.parse(String(item.createTime || ""))
  if (isFinite(created)) return created
  return 0
}

function recentlyUsed(items, limit) {
  var list = (items || []).slice()
  list.sort(function (a, b) {
    var diff = usageTime(b) - usageTime(a)
    if (diff !== 0) return diff
    return String(a.title || "").localeCompare(String(b.title || ""))
  })
  var cap = parseInt(limit, 10)
  if (!isFinite(cap) || cap < 1) return list
  return list.slice(0, cap)
}

function withoutItems(items, skip) {
  var seen = {}
  var ignored = skip || []
  for (var i = 0; i < ignored.length; i++) {
    var key = itemKey(ignored[i])
    if (key !== "/") seen[key] = true
  }
  var list = items || []
  var out = []
  for (var j = 0; j < list.length; j++) {
    var key = itemKey(list[j])
    if (key === "/" || seen[key]) continue
    out.push(list[j])
  }
  return out
}

function cleanCliText(text) {
  return String(text || "")
    .replace(/\u001b\[[0-9;]*[A-Za-z]/g, "")
    .replace(/\[(?:\d{1,3};)*\d{1,3}m/g, "")
    .replace(/\s+/g, " ")
    .trim()
}

function displayError(stderr) {
  var value = cleanCliText(stderr)
  if (value === "") return ""
  if (value.indexOf(".rs:") >= 0 || value.indexOf("pass-cli/src/") >= 0)
    return ""
  return value.length > 140 ? value.substring(0, 137) + "…" : value
}

function classifyError(stderr, exitCode) {
  var text = cleanCliText(stderr).toLowerCase()
  if (Number(exitCode) === 127 || text.indexOf("command not found") >= 0 || text.indexOf("no such file") >= 0)
    return "missing"
  if (
    text.indexOf("sqlcipher_page_cipher") >= 0
    || text.indexOf("hmac check failed") >= 0
    || text.indexOf("sqlite3codec: error decrypting") >= 0
    || text.indexOf("failed to open encrypted database") >= 0
    || text.indexOf("file is not a database") >= 0
    || text.indexOf("encryption key may not match") >= 0
    || text.indexOf("encryption key mismatch") >= 0
    || (
      text.indexOf("database") >= 0
      && (text.indexOf("decrypt") >= 0 || text.indexOf("decryption") >= 0)
      && (text.indexOf("key") >= 0 || text.indexOf("sqlite") >= 0 || text.indexOf("codec") >= 0)
    )
    || (
      text.indexOf("database key") >= 0
      && (
        text.indexOf("incorrect") >= 0
        || text.indexOf("invalid") >= 0
        || text.indexOf("mismatch") >= 0
        || text.indexOf("wrong") >= 0
      )
    )
  )
    return "migration-required"
  if (
    text.indexOf("session is locked") >= 0
    || text.indexOf("session lock") >= 0
    || text.indexOf("unlock the session") >= 0
    || text.indexOf("pass-cli session unlock") >= 0
  )
    return "locked"
  if (
    text.indexOf("no session") >= 0
    || text.indexOf("not logged in") >= 0
    || text.indexOf("unauthenticated") >= 0
    || text.indexOf("please login") >= 0
    || text.indexOf("login first") >= 0
    || text.indexOf("login required") >= 0
    || text.indexOf("must login") >= 0
    || text.indexOf("run pass-cli login") >= 0
  )
    return "unauthenticated"
  return "error"
}

function parseFetchWarning(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  if (String(value.kind || "") !== "partial-vault-failure") return null
  var names = Array.isArray(value.failedVaultNames) ? value.failedVaultNames : []
  var shareIds = Array.isArray(value.failedShareIds) ? value.failedShareIds : []
  var safeNames = []
  var safeShareIds = []
  for (var i = 0; i < names.length; i++) {
    var name = cleanCliText(names[i]).substring(0, 64)
    if (name !== "") safeNames.push(name)
  }
  for (var j = 0; j < shareIds.length; j++) {
    var shareId = String(shareIds[j] || "")
    if (shareId !== "") safeShareIds.push(shareId)
  }
  var count = Number(value.failedVaultCount)
  if (!isFinite(count) || count < 0) count = safeNames.length
  return {
    kind: "partial-vault-failure",
    failedVaultCount: Math.floor(count),
    failedVaultNames: safeNames,
    failedShareIds: safeShareIds,
    message: displayError(value.message || "")
  }
}

function emptyFetchResult(status, message, warning) {
  return {
    ok: false,
    status: String(status || "error"),
    message: String(message || ""),
    email: "",
    items: [],
    warning: warning || null
  }
}

function parseFetchResult(raw) {
  var parsed = parseJson(raw)
  if (!parsed || typeof parsed !== "object") return emptyFetchResult("error", "Could not load Proton Pass")
  if (parsed.ok === false) {
    var status = String(parsed.status || classifyError(parsed.stderr || parsed.message || "", parsed.exitCode))
    return emptyFetchResult(status, parsed.message || parsed.stderr || "", parseFetchWarning(parsed.warning))
  }
  var rows = asArray(parsed)
  var items = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var vaultName = stringField(row, ["vault_name", "vaultName"]) 
    var item = normalizeItem(row, vaultName)
    if (item) items.push(item)
  }
  return {
    ok: true,
    status: String(parsed.status || "ready") === "partial" ? "partial" : "ready",
    message: String(parsed.message || ""),
    email: stringField(parsed, ["email", "username"]),
    items: items,
    warning: parseFetchWarning(parsed.warning)
  }
}

function parseItemPreview(raw) {
  var parsed = parseJson(raw)
  if (!parsed || typeof parsed !== "object") return null
  var wrapped = parsed.item && typeof parsed.item === "object" ? parsed.item : parsed
  var item = normalizeItem(wrapped, "")
  if (!item) return null
  return {
    username: item.username,
    email: item.email,
    urls: item.urls,
    hasTotp: item.hasTotp === true
  }
}

function mergeItemPreview(item, preview) {
  if (!item || typeof item !== "object") return item
  var next = {
    id: item.id,
    shareId: item.shareId,
    vaultId: item.vaultId,
    vaultName: item.vaultName,
    title: item.title,
    itemType: item.itemType,
    username: item.username,
    email: item.email,
    urls: item.urls,
    createTime: item.createTime,
    modifyTime: item.modifyTime,
    hasTotp: item.hasTotp,
    state: item.state,
    lastUsedAt: Number(item.lastUsedAt || 0) || 0
  }
  if (!preview || typeof preview !== "object") return next
  if (preview.username) next.username = String(preview.username)
  if (preview.email) next.email = String(preview.email)
  if (Array.isArray(preview.urls)) next.urls = preview.urls
  if (preview.hasTotp === true) next.hasTotp = true
  var used = Number(preview.lastUsedAt || 0)
  if (isFinite(used) && used > next.lastUsedAt) next.lastUsedAt = used
  return next
}

function itemKey(item) {
  if (!item) return ""
  return String(item.shareId || "") + "/" + String(item.id || "")
}

function mergeItemLists(previous, incoming) {
  var prev = {}
  var old = previous || []
  for (var i = 0; i < old.length; i++) {
    var key = itemKey(old[i])
    if (key !== "/") prev[key] = old[i]
  }
  var list = incoming || []
  var out = []
  for (var j = 0; j < list.length; j++) {
    var item = list[j]
    var cached = prev[itemKey(item)]
    out.push(cached ? mergeItemPreview(item, cached) : item)
  }
  return out
}

function mergePartialItemLists(previous, incoming, failedShareIds) {
  var refreshed = mergeItemLists(previous, incoming)
  var failed = {}
  var ids = failedShareIds || []
  for (var i = 0; i < ids.length; i++) {
    var shareId = String(ids[i] || "")
    if (shareId !== "") failed[shareId] = true
  }
  if (Object.keys(failed).length === 0) return refreshed
  var seen = {}
  for (var j = 0; j < refreshed.length; j++) seen[itemKey(refreshed[j])] = true
  var old = previous || []
  for (var k = 0; k < old.length; k++) {
    var item = old[k]
    var key = itemKey(item)
    if (item && failed[String(item.shareId || "")] && !seen[key]) {
      refreshed.push(item)
      seen[key] = true
    }
  }
  return refreshed
}

function serializeItem(item) {
  if (!item || typeof item !== "object") return null
  return {
    id: String(item.id || ""),
    shareId: String(item.shareId || ""),
    vaultId: String(item.vaultId || ""),
    vaultName: String(item.vaultName || ""),
    title: String(item.title || ""),
    itemType: "login",
    username: String(item.username || ""),
    email: String(item.email || ""),
    urls: Array.isArray(item.urls) ? item.urls.slice() : [],
    createTime: String(item.createTime || ""),
    modifyTime: String(item.modifyTime || ""),
    hasTotp: item.hasTotp === true,
    state: String(item.state || "Active"),
    lastUsedAt: Number(item.lastUsedAt || 0) || 0
  }
}

function serializeCache(email, fetchedAt, items, refreshingAt) {
  var out = []
  var list = items || []
  for (var i = 0; i < list.length; i++) {
    var row = serializeItem(list[i])
    if (row && row.id) out.push(row)
  }
  var at = Number(fetchedAt)
  if (!isFinite(at)) at = 0
  var refreshing = Number(refreshingAt)
  if (!isFinite(refreshing)) refreshing = 0
  return { email: String(email || ""), fetchedAt: at, refreshingAt: refreshing, items: out }
}

function parseCache(raw) {
  var parsed = parseJson(raw)
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    return { ok: false, email: "", fetchedAt: 0, items: [] }
  var rows = asArray(parsed)
  var items = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var item = normalizeItem(row, stringField(row, ["vaultName", "vault_name"]))
    if (item) items.push(item)
  }
  var fetchedAt = Number(parsed.fetchedAt || 0)
  if (!isFinite(fetchedAt)) fetchedAt = 0
  var refreshingAt = Number(parsed.refreshingAt || 0)
  if (!isFinite(refreshingAt)) refreshingAt = 0
  return {
    ok: fetchedAt > 0 || items.length > 0,
    email: stringField(parsed, ["email"]),
    fetchedAt: fetchedAt,
    refreshingAt: refreshingAt,
    items: items
  }
}

function vaultsFromItems(items) {
  var seen = {}
  var out = []
  var list = items || []
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (!item) continue
    var shareId = String(item.shareId || "")
    if (!shareId || seen[shareId]) continue
    seen[shareId] = true
    out.push({ shareId: shareId, name: String(item.vaultName || shareId) })
  }
  return out
}

function listRowCursorIndex(searching, suggestedLength, delegateIndex) {
  return searching ? delegateIndex : Number(suggestedLength || 0) + delegateIndex
}

function listScrollTargetIndex(searching, selectedIndex, suggestedLength) {
  if (!searching && selectedIndex < suggestedLength) return -1
  var idx = searching ? selectedIndex : selectedIndex - suggestedLength
  return idx >= 0 ? idx : -1
}

function cursorItemCount(searching, suggested, recent, filtered) {
  if (searching) return (filtered || []).length
  return (suggested || []).length + (recent || []).length
}

function cursorItemAt(searching, suggested, recent, filtered, index) {
  var idx = Number(index)
  if (!isFinite(idx) || idx < 0) return null
  if (searching) {
    var rows = filtered || []
    return idx < rows.length ? rows[idx] : null
  }
  var left = suggested || []
  if (idx < left.length) return left[idx]
  var right = recent || []
  var offset = idx - left.length
  return offset < right.length ? right[offset] : null
}

function resolveCursorRow(filterText, suggested, recent, rankedItems, selectedIndex) {
  var needle = String(filterText || "").trim()
  var searching = needle !== ""
  var filtered = searching ? searchItems(rankedItems || [], needle) : []
  return cursorItemAt(searching, suggested, recent, filtered, selectedIndex)
}

function applyPreviewBatch(items, updates) {
  var list = items || []
  var map = updates && typeof updates === "object" && !Array.isArray(updates) ? updates : null
  if (!map) return { items: list, updated: [] }
  var keys = Object.keys(map)
  if (keys.length === 0) return { items: list, updated: [] }
  var out = []
  var updated = []
  var changed = false
  for (var i = 0; i < list.length; i++) {
    var current = list[i]
    var key = itemKey(current)
    if (key !== "/" && Object.prototype.hasOwnProperty.call(map, key)) {
      var merged = mergeItemPreview(current, map[key])
      out.push(merged)
      updated.push(merged)
      changed = true
    } else {
      out.push(current)
    }
  }
  return { items: changed ? out : list, updated: updated }
}

function applyPreviewUpdates(items, updates) {
  return applyPreviewBatch(items, updates).items
}

function rememberFailedPreviewKey(store, key, maxSize) {
  var value = String(key || "")
  var cap = parseInt(maxSize, 10)
  if (!isFinite(cap) || cap < 1) cap = 64
  var current = store && typeof store === "object" ? store : { map: {}, order: [] }
  var map = {}
  var order = []
  var prevMap = current.map && typeof current.map === "object" ? current.map : {}
  var prevOrder = Array.isArray(current.order) ? current.order : []
  for (var i = 0; i < prevOrder.length; i++) {
    var existing = String(prevOrder[i] || "")
    if (!existing || existing === value || !prevMap[existing]) continue
    map[existing] = true
    order.push(existing)
  }
  if (value !== "") {
    map[value] = true
    order.push(value)
  }
  while (order.length > cap) {
    var dropped = order.shift()
    delete map[dropped]
  }
  return { map: map, order: order }
}

function hasFailedPreviewKey(store, key) {
  if (!store || typeof store !== "object" || !store.map) return false
  var value = String(key || "")
  if (value === "") return false
  return store.map[value] === true
}

function clearFailedPreviewKeys() {
  return { map: {}, order: [] }
}

function isSessionBlockingStatus(status) {
  var kind = String(status || "")
  return kind === "locked" || kind === "unauthenticated" || kind === "migration-required"
}

function visiblePreviewWindow(searching, suggested, list, viewport) {
  var out = []
  if (!searching) {
    var suggestedItems = suggested || []
    for (var i = 0; i < suggestedItems.length; i++) out.push(suggestedItems[i])
  }
  var rows = list || []
  if (rows.length === 0) return out
  var vp = viewport && typeof viewport === "object" ? viewport : {}
  var start = 0
  var last = Math.min(rows.length - 1, 11)
  if (Number(vp.height) > 0) {
    var top = Number(vp.indexAtTop)
    var bottom = Number(vp.indexAtBottom)
    if (!isFinite(top) || top < 0) {
      top = Math.floor(Math.max(0, Number(vp.contentY) || 0) / Math.max(1, Number(vp.rowHeight) || 44))
    }
    if (!isFinite(bottom) || bottom < top) bottom = top + 11
    start = Math.max(0, top)
    last = Math.min(rows.length - 1, bottom)
    if (last - start > 11) last = start + 11
  }
  for (var j = start; j <= last; j++) out.push(rows[j])
  return out
}

function buildCreateLoginCommand(fields) {
  return buildCreateLoginRequest(fields).args
}

function buildCreateLoginRequest(fields) {
  var args = ["item", "create", "login"]
  var data = fields && typeof fields === "object" ? fields : {}
  if (data.shareId) {
    args.push("--share-id", String(data.shareId))
  } else if (data.vaultName) {
    args.push("--vault-name", String(data.vaultName))
  }
  var password = data.password === undefined || data.password === null ? "" : String(data.password)
  if (data.generatePassword !== true && password !== "") {
    var urls = []
    if (Array.isArray(data.urls)) {
      for (var i = 0; i < data.urls.length; i++) {
        var candidate = String(data.urls[i] || "").trim()
        if (candidate !== "") urls.push(candidate)
      }
    } else if (data.url) {
      urls.push(String(data.url))
    }
    args.push("--from-template", "-")
    return {
      args: args,
      stdin: JSON.stringify({
        title: String(data.title || ""),
        username: String(data.username || ""),
        email: String(data.email || ""),
        password: password,
        urls: urls
      }) + "\n"
    }
  }
  if (data.title) args.push("--title", String(data.title))
  if (data.username) args.push("--username", String(data.username))
  if (data.email) args.push("--email", String(data.email))
  if (data.generatePassword === true) args.push("--generate-password")
  if (data.url) args.push("--url", String(data.url))
  return { args: args, stdin: "" }
}
