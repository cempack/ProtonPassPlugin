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

function canonicalItemType(value) {
  var type = String(value || "").trim().toLowerCase().replace(/_/g, "-").replace(/\s+/g, "-")
  if (type === "creditcard") return "credit-card"
  if (type === "sshkey" || type === "ssh") return "ssh-key"
  if (type === "credit-card" || type === "ssh-key") return type
  if (type === "login" || type === "note" || type === "alias" || type === "identity" || type === "wifi" || type === "custom")
    return type
  return type
}

function itemTypeFromTag(tag) {
  var key = String(tag || "")
  if (key === "Login" || key === "login") return "login"
  if (key === "Note" || key === "note") return "note"
  if (key === "Alias" || key === "alias") return "alias"
  if (key === "CreditCard" || key === "creditCard") return "credit-card"
  if (key === "Identity" || key === "identity") return "identity"
  if (key === "SshKey" || key === "sshKey") return "ssh-key"
  if (key === "Wifi" || key === "wifi") return "wifi"
  if (key === "Custom" || key === "custom") return "custom"
  return canonicalItemType(key)
}

function taggedContent(content) {
  if (!content || typeof content !== "object") return { tag: "", payload: null }
  var nested = content.content
  if (!nested || typeof nested !== "object" || Array.isArray(nested)) nested = content
  var keys = ["Login", "Note", "Alias", "CreditCard", "Identity", "SshKey", "Wifi", "Custom",
    "login", "note", "alias", "creditCard", "identity", "sshKey", "wifi", "custom"]
  for (var i = 0; i < keys.length; i++) {
    if (Object.prototype.hasOwnProperty.call(nested, keys[i]))
      return { tag: keys[i], payload: nested[keys[i]] }
  }
  return { tag: "", payload: null }
}

function itemTypeFrom(raw) {
  if (!raw || typeof raw !== "object") return "custom"
  var declared = stringField(raw, ["item_type", "itemType", "type"])
  if (declared) return canonicalItemType(declared) || "custom"
  var tagged = taggedContent(raw.content && typeof raw.content === "object" ? raw.content : raw)
  if (tagged.tag) return itemTypeFromTag(tagged.tag)
  if (loginPayload(raw)) return "login"
  if (stringField(raw, ["username"]) || stringField(raw, ["email"])) return "login"
  if (Array.isArray(raw.urls) && raw.urls.length > 0) return "login"
  return "custom"
}

function itemTypeLabel(type) {
  var key = canonicalItemType(type)
  if (key === "note") return "Note"
  if (key === "credit-card") return "Card"
  if (key === "identity") return "Identity"
  if (key === "alias") return "Alias"
  if (key === "ssh-key") return "SSH key"
  if (key === "wifi") return "Wi-Fi"
  if (key === "custom") return "Custom"
  return "Login"
}

function itemTypeGlyph(item) {
  var type = canonicalItemType(item && typeof item === "object" ? item.itemType : item)
  if (type === "note") return "󰎞"
  if (type === "credit-card") return "󰆛"
  if (type === "identity") return "󰀄"
  if (type === "alias") return "󰇮"
  if (type === "ssh-key") return "󰣀"
  if (type === "wifi") return "󰖩"
  if (type === "custom") return "󰘳"
  return "󰌆"
}

function primaryCopyField(item) {
  return canonicalItemType(item && item.itemType) === "login" ? "password" : ""
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
  var id = stringField(raw, ["id", "item_id", "itemId"])
  if (!id) return null
  var type = itemTypeFrom(raw)
  var payload = type === "login" ? loginPayload(raw) : null
  var content = raw.content && typeof raw.content === "object" ? raw.content : null
  var title = stringField(raw, ["title"]) || stringField(content, ["title"])
  var username = type === "login"
    ? (stringField(payload, ["username"]) || stringField(raw, ["username"]))
    : ""
  var email = type === "login"
    ? (stringField(payload, ["email"]) || stringField(raw, ["email"]))
    : ""

  return {
    id: id,
    shareId: stringField(raw, ["share_id", "shareId"]),
    vaultId: stringField(raw, ["vault_id", "vaultId"]),
    vaultName: String(vaultName || ""),
    title: title,
    itemType: type || "custom",
    username: username,
    email: email,
    urls: type === "login" ? urlsFrom(payload, raw) : [],
    createTime: stringField(raw, ["create_time", "createTime"]),
    modifyTime: stringField(raw, ["modify_time", "modifyTime"]),
    hasTotp: payload ? hasTotpFrom(payload) : false,
    state: stringField(raw, ["state"]) || "Active",
    lastUsedAt: Number(raw.lastUsedAt || raw.last_used_at || 0) || 0,
    previewed: raw.previewed === true
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

function isPublicHostname(host) {
  var h = String(host || "").trim().toLowerCase()
  if (h.length < 3 || h.length > 253) return false
  if (!/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/.test(h)) return false
  if (h === "localhost" || h.slice(-10) === ".localhost") return false
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(h)) return false
  return true
}

function hostFromTitle(title) {
  var t = String(title || "").trim().toLowerCase().replace(/^www\./, "")
  if (isPublicHostname(t)) return t
  var compact = t.replace(/[^a-z0-9-]/g, "")
  if (compact !== "" && isPublicHostname(compact + ".com")) return compact + ".com"
  return ""
}

function parentHostname(host) {
  var parts = String(host || "").toLowerCase().split(".")
  if (parts.length < 3) return ""
  return parts.slice(-2).join(".")
}

function faviconHosts(item) {
  var hosts = []
  var seen = {}
  function add(host) {
    var name = String(host || "").toLowerCase()
    if (!isPublicHostname(name) || seen[name]) return
    seen[name] = true
    hosts.push(name)
  }
  var urls = item && item.urls ? item.urls : []
  for (var i = 0; i < urls.length; i++) add(displayHost(urls[i]))
  add(hostFromTitle(item && item.title))
  return hosts
}

function faviconUrlForHost(host) {
  return "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(host) + "&sz=64"
}

function faviconUrls(item) {
  var hosts = faviconHosts(item)
  var out = []
  var seen = {}
  function push(url) {
    if (!url || seen[url]) return
    seen[url] = true
    out.push(url)
  }
  for (var i = 0; i < hosts.length; i++) {
    var host = hosts[i]
    push("https://" + host + "/favicon.ico")
    push(faviconUrlForHost(host))
    var parent = parentHostname(host)
    if (parent && isPublicHostname(parent)) push(faviconUrlForHost(parent))
  }
  return out
}

function faviconUrl(item) {
  var urls = faviconUrls(item)
  return urls.length > 0 ? urls[0] : ""
}

function nextFaviconIndex(count, index, failed) {
  var n = parseInt(count, 10)
  var i = parseInt(index, 10)
  if (!isFinite(n) || n < 1) return 0
  if (!isFinite(i) || i < 0) i = 0
  if (failed !== true) return i
  if (i + 1 < n) return i + 1
  return i
}

function needsPreview(item) {
  if (!item) return false
  if (canonicalItemType(item.itemType || "login") !== "login") return false
  if (item.previewed === true) return false
  if (item.urls && item.urls.length > 0) return false
  return passUri(item, "") !== ""
}

function itemSubtitle(item) {
  if (!item) return ""
  var type = canonicalItemType(item.itemType)
  if (type && type !== "login") {
    var label = itemTypeLabel(type)
    var vault = String(item.vaultName || "").trim()
    var title = String(item.title || "").trim().toLowerCase()
    if (vault && vault.toLowerCase() !== title) return label + " · " + vault
    return label
  }
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
  var parts = [item.title, item.username, item.email, item.vaultName, itemTypeLabel(item.itemType), canonicalItemType(item.itemType)]
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

function suggestedItems(items, appId, title, limit) {
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
  var cap = parseInt(limit, 10)
  if (!isFinite(cap) || cap < 0) return out
  return out.slice(0, cap)
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
    || text.indexOf("pass-cli login") >= 0
    || text.indexOf("local encryption key not found") >= 0
    || text.indexOf("forcing logout") >= 0
  )
    return "unauthenticated"
  return "error"
}

function fetchWarningMessage(count, names) {
  var failedCount = Number(count)
  if (!isFinite(failedCount) || failedCount < 0) failedCount = 0
  failedCount = Math.floor(failedCount)
  var noun = failedCount === 1 ? "vault" : "vaults"
  var suffix = names && names.length > 0 ? ": " + names.join(", ") : ""
  return "Could not refresh " + failedCount + " " + noun + suffix + "."
}

function parseFetchWarning(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  if (String(value.kind || "") !== "partial-vault-failure") return null
  var names = Array.isArray(value.failedVaultNames) ? value.failedVaultNames : []
  var shareIds = Array.isArray(value.failedShareIds) ? value.failedShareIds : []
  var safeNames = []
  var safeShareIds = []
  for (var i = 0; i < names.length && safeNames.length < 32; i++) {
    var name = cleanCliText(names[i]).substring(0, 64)
    if (name !== "") safeNames.push(name)
  }
  for (var j = 0; j < shareIds.length && safeShareIds.length < 32; j++) {
    var shareId = cleanCliText(shareIds[j]).substring(0, 128)
    if (shareId !== "") safeShareIds.push(shareId)
  }
  var count = Number(value.failedVaultCount)
  if (!isFinite(count) || count < 0) count = safeNames.length
  count = Math.floor(count)
  return {
    kind: "partial-vault-failure",
    failedVaultCount: count,
    failedVaultNames: safeNames,
    failedShareIds: safeShareIds,
    message: fetchWarningMessage(count, safeNames)
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
  if (!item || item.itemType !== "login") return null
  return {
    username: item.username,
    email: item.email,
    urls: item.urls,
    hasTotp: item.hasTotp === true,
    previewed: true
  }
}

function scalarText(value) {
  if (value === undefined || value === null) return ""
  if (typeof value === "boolean" || typeof value === "number") return String(value)
  if (typeof value === "string") return value
  if (Array.isArray(value)) return ""
  if (typeof value === "object") {
    var keys = Object.keys(value)
    if (keys.length === 1) {
      var inner = value[keys[0]]
      if (inner === null || inner === undefined || Array.isArray(inner) || inner === "") return keys[0]
    }
  }
  return ""
}

function makeInspectorField(id, label, kind, value, field) {
  var text = value === undefined || value === null ? "" : String(value)
  var fieldKind = kind || "text"
  return {
    id: String(id || ""),
    label: String(label || id || ""),
    kind: fieldKind,
    value: fieldKind === "totp" ? "" : text,
    field: String(field || ""),
    revealable: fieldKind === "secret"
  }
}

function pushInspectorField(fields, id, label, kind, value, field) {
  var text = value === undefined || value === null ? "" : String(value)
  if (kind !== "totp" && String(text).trim() === "") return
  fields.push(makeInspectorField(id, label, kind, text, field))
}

function extraFieldName(entry) {
  return stringField(entry, ["name", "field_name", "fieldName"])
}

function extraFieldValue(entry) {
  if (!entry || typeof entry !== "object") return ""
  if (entry.value !== undefined && entry.value !== null && typeof entry.value !== "object")
    return String(entry.value)
  var content = entry.content
  if (!content || typeof content !== "object") return ""
  if (content.Text !== undefined && content.Text !== null) return String(content.Text)
  if (content.Hidden !== undefined && content.Hidden !== null) return String(content.Hidden)
  if (content.Totp !== undefined && content.Totp !== null) return String(content.Totp)
  if (content.Timestamp !== undefined && content.Timestamp !== null) return String(content.Timestamp)
  if (content.text !== undefined && content.text !== null) return String(content.text)
  if (content.hidden !== undefined && content.hidden !== null) return String(content.hidden)
  return ""
}

function extraFieldKind(name, content) {
  if (content && typeof content === "object") {
    if (Object.prototype.hasOwnProperty.call(content, "Totp") || Object.prototype.hasOwnProperty.call(content, "totp"))
      return "totp"
    if (Object.prototype.hasOwnProperty.call(content, "Hidden") || Object.prototype.hasOwnProperty.call(content, "hidden"))
      return "secret"
  }
  var key = String(name || "").toLowerCase()
  if (key.indexOf("pass") >= 0 || key.indexOf("pin") >= 0 || key.indexOf("secret") >= 0 || key.indexOf("token") >= 0 || key.indexOf("cvv") >= 0)
    return "secret"
  return "text"
}

function extraFieldsToInspector(entries, fieldPrefix) {
  var fields = []
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    var name = extraFieldName(entry)
    if (!name) continue
    var qualified = fieldPrefix ? fieldPrefix + "." + name : name
    var kind = extraFieldKind(name, entry.content)
    if (kind === "totp") pushInspectorField(fields, qualified, name, "totp", "", qualified)
    else pushInspectorField(fields, qualified, name, kind, extraFieldValue(entry), qualified)
  }
  return fields
}

function customSectionBlocks(sections) {
  var out = []
  var list = Array.isArray(sections) ? sections : []
  for (var i = 0; i < list.length; i++) {
    var section = list[i]
    if (!section || typeof section !== "object") continue
    var title = stringField(section, ["section_name", "sectionName", "title"]) || "Section"
    var fields = extraFieldsToInspector(section.section_fields || section.fields || [], title)
    if (fields.length) out.push({ title: title, fields: fields })
  }
  return out
}

function fieldsFromSpec(payload, spec) {
  var fields = []
  if (!payload || typeof payload !== "object") return fields
  for (var i = 0; i < spec.length; i++) {
    var row = spec[i]
    var key = row[0]
    var label = row[1]
    var kind = row[2] || "text"
    var copyField = row.length > 3 ? row[3] : key
    pushInspectorField(fields, key, label, kind, scalarText(payload[key]), copyField)
  }
  return fields
}

function addInspectorSection(sections, title, fields) {
  if (fields && fields.length) sections.push({ title: title, fields: fields })
}

function attachmentFields(source) {
  var list = []
  if (source && Array.isArray(source.attachments)) list = source.attachments
  var fields = []
  for (var i = 0; i < list.length; i++) {
    var name = stringField(list[i], ["name", "filename", "file_name", "title"])
    if (!name) continue
    fields.push(makeInspectorField("attachment-" + i, "File", "text", name, ""))
  }
  return fields
}

function inspectorHasTotp(sections) {
  for (var i = 0; i < sections.length; i++) {
    var fields = sections[i].fields || []
    for (var j = 0; j < fields.length; j++) {
      if (fields[j].kind === "totp") return true
    }
  }
  return false
}

function parseItemInspector(raw) {
  var parsed = parseJson(raw)
  if (!parsed || typeof parsed !== "object") return null
  var item = parsed.item && typeof parsed.item === "object" ? parsed.item : parsed
  var content = item.content && typeof item.content === "object" ? item.content : {}
  var tagged = taggedContent(content)
  var type = itemTypeFrom(item)
  if (tagged.tag) type = itemTypeFromTag(tagged.tag)
  var payload = tagged.payload && typeof tagged.payload === "object" ? tagged.payload : {}
  var title = stringField(item, ["title"]) || stringField(content, ["title"])
  var sections = []

  if (type === "login") {
    var loginFields = []
    pushInspectorField(loginFields, "username", "Username", "text", stringField(payload, ["username"]), "username")
    pushInspectorField(loginFields, "email", "Email", "text", stringField(payload, ["email"]), "email")
    pushInspectorField(loginFields, "password", "Password", "secret", stringField(payload, ["password"]), "password")
    var urls = urlsFrom(payload, item)
    for (var u = 0; u < urls.length; u++)
      pushInspectorField(loginFields, "url-" + u, u === 0 ? "Website" : "Website " + (u + 1), "text", urls[u], "")
    if (hasTotpFrom(payload))
      pushInspectorField(loginFields, "totp", "Code", "totp", "", "totp")
    addInspectorSection(sections, "Login", loginFields)
  } else if (type === "note") {
    addInspectorSection(sections, "Note", fieldsFromSpec({ note: stringField(content, ["note"]) }, [["note", "Note", "note", "note"]]))
  } else if (type === "credit-card") {
    addInspectorSection(sections, "Card", fieldsFromSpec(payload, [
      ["cardholder_name", "Cardholder", "text"],
      ["number", "Number", "secret"],
      ["expiration_date", "Expiration", "text"],
      ["verification_number", "CVC", "secret"],
      ["pin", "PIN", "secret"]
    ]))
  } else if (type === "wifi") {
    addInspectorSection(sections, "Wi-Fi", fieldsFromSpec(payload, [
      ["ssid", "SSID", "text"],
      ["security", "Security", "text"],
      ["password", "Password", "secret"]
    ]))
    sections = sections.concat(customSectionBlocks(payload.sections))
  } else if (type === "ssh-key") {
    addInspectorSection(sections, "SSH key", fieldsFromSpec(payload, [
      ["public_key", "Public key", "note", "public_key"],
      ["private_key", "Private key", "secret", "private_key"]
    ]))
    sections = sections.concat(customSectionBlocks(payload.sections))
  } else if (type === "identity") {
    var personal = fieldsFromSpec(payload, [
      ["full_name", "Full name", "text"],
      ["first_name", "First name", "text"],
      ["middle_name", "Middle name", "text"],
      ["last_name", "Last name", "text"],
      ["email", "Email", "text"],
      ["phone_number", "Phone", "text"],
      ["birthdate", "Birthdate", "text"],
      ["gender", "Gender", "text"]
    ]).concat(extraFieldsToInspector(payload.extra_personal_details || []))
    var address = fieldsFromSpec(payload, [
      ["organization", "Organization", "text"],
      ["street_address", "Street", "text"],
      ["zip_or_postal_code", "Postal code", "text"],
      ["city", "City", "text"],
      ["state_or_province", "State", "text"],
      ["country_or_region", "Country", "text"],
      ["floor", "Floor", "text"],
      ["county", "County", "text"]
    ]).concat(extraFieldsToInspector(payload.extra_address_details || []))
    var contact = fieldsFromSpec(payload, [
      ["social_security_number", "SSN", "secret"],
      ["passport_number", "Passport", "secret"],
      ["license_number", "License", "secret"],
      ["website", "Website", "text"],
      ["x_handle", "X", "text"],
      ["second_phone_number", "Second phone", "text"],
      ["linkedin", "LinkedIn", "text"],
      ["reddit", "Reddit", "text"],
      ["facebook", "Facebook", "text"],
      ["yahoo", "Yahoo", "text"],
      ["instagram", "Instagram", "text"]
    ]).concat(extraFieldsToInspector(payload.extra_contact_details || []))
    var work = fieldsFromSpec(payload, [
      ["company", "Company", "text"],
      ["job_title", "Job title", "text"],
      ["personal_website", "Website", "text"],
      ["work_phone_number", "Work phone", "text"],
      ["work_email", "Work email", "text"]
    ]).concat(extraFieldsToInspector(payload.extra_work_details || []))
    addInspectorSection(sections, "Personal", personal)
    addInspectorSection(sections, "Address", address)
    addInspectorSection(sections, "Contact", contact)
    addInspectorSection(sections, "Work", work)
    sections = sections.concat(customSectionBlocks(payload.extra_sections))
  } else if (type === "alias") {
    var aliasEmail = stringField(payload, ["email", "alias_email"]) || stringField(item, ["alias_email", "email"])
    addInspectorSection(sections, "Alias", fieldsFromSpec({ email: aliasEmail }, [["email", "Email", "text", "email"]]))
  } else if (type === "custom") {
    sections = sections.concat(customSectionBlocks(payload.sections))
  }

  var note = stringField(content, ["note"])
  if (note && type !== "note")
    addInspectorSection(sections, "Note", [makeInspectorField("note", "Note", "note", note, "note")])
  var extras = extraFieldsToInspector(content.extra_fields || item.extra_fields || [])
  addInspectorSection(sections, "Extra fields", extras)
  addInspectorSection(sections, "Attachments", attachmentFields(parsed).length ? attachmentFields(parsed) : attachmentFields(item))

  return {
    title: title,
    itemType: type || "custom",
    hasTotp: inspectorHasTotp(sections),
    sections: sections
  }
}

function parseTotpCodes(raw) {
  var parsed = parseJson(raw)
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {}
  var out = {}
  var keys = Object.keys(parsed)
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    var value = parsed[key]
    if (value === undefined || value === null || String(value) === "") continue
    out[key] = String(value)
  }
  return out
}

function totpSecondsRemaining(nowMs, period) {
  var p = Number(period)
  if (!isFinite(p) || p <= 0) p = 30
  var sec = Math.floor(Number(nowMs) / 1000)
  if (!isFinite(sec)) sec = 0
  var rem = p - (sec % p)
  return rem === 0 ? p : rem
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
    lastUsedAt: Number(item.lastUsedAt || 0) || 0,
    previewed: item.previewed === true
  }
  if (!preview || typeof preview !== "object") return next
  if (preview.username) next.username = String(preview.username)
  if (preview.email) next.email = String(preview.email)
  if (Array.isArray(preview.urls)) next.urls = preview.urls
  if (preview.hasTotp === true) next.hasTotp = true
  if (preview.previewed === true) next.previewed = true
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
    itemType: canonicalItemType(item.itemType || "login") || "login",
    username: String(item.username || ""),
    email: String(item.email || ""),
    urls: Array.isArray(item.urls) ? item.urls.slice() : [],
    createTime: String(item.createTime || ""),
    modifyTime: String(item.modifyTime || ""),
    hasTotp: item.hasTotp === true,
    state: String(item.state || "Active"),
    lastUsedAt: Number(item.lastUsedAt || 0) || 0,
    previewed: item.previewed === true
  }
}

function serializeCache(email, fetchedAt, items, refreshingAt, warning) {
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
  return {
    email: String(email || ""),
    fetchedAt: at,
    refreshingAt: refreshing,
    warning: parseFetchWarning(warning),
    items: out
  }
}

function parseCache(raw) {
  var parsed = parseJson(raw)
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    return { ok: false, email: "", fetchedAt: 0, refreshingAt: 0, warning: null, items: [] }
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
    warning: parseFetchWarning(parsed.warning),
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

function clampListScrollY(y, contentHeight, viewportHeight) {
  var view = Number(viewportHeight)
  var height = Number(contentHeight)
  if (!isFinite(view) || view < 0) view = 0
  if (!isFinite(height) || height < 0) height = 0
  var maxY = Math.max(0, height - view)
  var v = Number(y)
  if (!isFinite(v) || v < 0) v = 0
  if (v > maxY) v = maxY
  return v
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

function createLoginUrls(data) {
  var urls = []
  if (!data || typeof data !== "object") return urls
  if (Array.isArray(data.urls)) {
    for (var i = 0; i < data.urls.length; i++) {
      var candidate = String(data.urls[i] || "").trim()
      if (candidate !== "") urls.push(candidate)
    }
  } else if (data.url) {
    var url = String(data.url || "").trim()
    if (url !== "") urls.push(url)
  }
  return urls
}

function clipboardClearDelayMs(seconds) {
  var value = parseInt(String(seconds), 10)
  if (!isFinite(value) || value < 0) value = 0
  if (value > 300) value = 300
  return value * 1000
}

function buildCreateLoginCommand(fields) {
  return buildCreateLoginRequest(fields).args
}

function buildCreateLoginRequest(fields) {
  var args = ["item", "create", "login"]
  var data = fields && typeof fields === "object" ? fields : {}
  if (data.shareId) {
    args.push("--share-id=" + String(data.shareId))
  } else if (data.vaultName) {
    args.push("--vault-name", String(data.vaultName))
  }
  args.push("--from-template", "-")
  var password = data.password === undefined || data.password === null ? "" : String(data.password)
  var needsPasswordGeneration = data.generatePassword === true || password === ""
  if (needsPasswordGeneration) {
    return {
      args: args,
      stdin: "",
      needsPasswordGeneration: true
    }
  }
  return {
    args: args,
    stdin: JSON.stringify({
      title: String(data.title || ""),
      username: String(data.username || ""),
      email: String(data.email || ""),
      password: password,
      urls: createLoginUrls(data)
    }) + "\n",
    needsPasswordGeneration: false
  }
}
