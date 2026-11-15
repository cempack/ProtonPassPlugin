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
    hasTotp: payload ? hasTotpFrom(payload) : (raw.has_totp === true || raw.hasTotp === true),
    state: stringField(raw, ["state"]) || "Active",
    lastUsedAt: Number(raw.lastUsedAt || raw.last_used_at || 0) || 0,
    previewed: raw.previewed === true || raw.complete === true
  }
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

function nextFaviconIndex(count, index, failed) {
  var n = parseInt(count, 10)
  var i = parseInt(index, 10)
  if (!isFinite(n) || n < 1) return 0
  if (!isFinite(i) || i < 0) i = 0
  if (failed !== true) return i
  if (i + 1 < n) return i + 1
  return i
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

// Every whitespace-separated term must match; results are ranked so title hits
// beat host hits, which beat username/vault hits. Ties keep the input order.
function searchItems(items, query) {
  var list = items || []
  var terms = String(query || "").trim().toLowerCase().split(/\s+/).filter(function (t) { return t !== "" })
  if (terms.length === 0) return list.slice()
  var scored = []
  for (var i = 0; i < list.length; i++) {
    var score = searchScore(list[i], terms)
    if (score > 0) scored.push({ item: list[i], score: score, index: i })
  }
  scored.sort(function (a, b) { return b.score - a.score || a.index - b.index })
  return scored.map(function (entry) { return entry.item })
}

function searchScore(item, terms) {
  var title = String(item.title || "").toLowerCase()
  var hosts = (item.urls || []).map(hostnameToken).join(" ")
  var haystack = haystackFor(item)
  var total = 0
  for (var i = 0; i < terms.length; i++) {
    var term = terms[i]
    if (haystack.indexOf(term) < 0) return 0
    if (title.indexOf(term) === 0) total += 40
    else if (new RegExp("\\b" + term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).test(title)) total += 25
    else if (title.indexOf(term) >= 0) total += 15
    else if (hosts.indexOf(term) >= 0) total += 10
    else total += 3
  }
  return total
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
    out.push(cached ? mergeCached(item, cached) : item)
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

function isSessionBlockingStatus(status) {
  var kind = String(status || "")
  return kind === "locked" || kind === "unauthenticated" || kind === "migration-required"
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

// ── Item merging ──────────────────────────────────────────────────────────────

// Shallow copy of an item with some fields replaced.
function withChanges(item, patch) {
  if (!item || typeof item !== "object") return item
  var next = {}
  var keys = Object.keys(item)
  for (var i = 0; i < keys.length; i++) next[keys[i]] = item[keys[i]]
  var changes = patch || {}
  var changed = Object.keys(changes)
  for (var j = 0; j < changed.length; j++) next[changed[j]] = changes[changed[j]]
  return next
}

// A fresh item from pass-cli wins, except for local usage time and, when the
// listing came back without login details, the details we already knew.
function mergeCached(fresh, cached) {
  var patch = {}
  var used = Math.max(Number(fresh.lastUsedAt || 0) || 0, Number(cached.lastUsedAt || 0) || 0)
  if (used > 0) patch.lastUsedAt = used
  if (fresh.previewed !== true && cached.previewed === true) {
    patch.username = fresh.username || cached.username || ""
    patch.email = fresh.email || cached.email || ""
    patch.urls = fresh.urls && fresh.urls.length > 0 ? fresh.urls : (cached.urls || [])
    patch.hasTotp = fresh.hasTotp === true || cached.hasTotp === true
    patch.previewed = true
  }
  return withChanges(fresh, patch)
}

// ── Filters ───────────────────────────────────────────────────────────────────

var FILTER_ORDER = ["all", "totp", "login", "alias", "note", "credit-card", "identity", "ssh-key", "wifi", "custom"]

function filterLabel(key) {
  if (key === "all") return "All"
  if (key === "totp") return "2FA"
  if (key === "login") return "Logins"
  if (key === "alias") return "Aliases"
  if (key === "note") return "Notes"
  if (key === "credit-card") return "Cards"
  if (key === "identity") return "Identities"
  if (key === "ssh-key") return "SSH"
  if (key === "wifi") return "Wi-Fi"
  return "Other"
}

function filterGlyph(key) {
  if (key === "all") return "󰒺"
  if (key === "totp") return "󰦯"
  return itemTypeGlyph(key)
}

function matchesFilter(item, filter) {
  if (!item) return false
  var key = String(filter || "all")
  if (key === "all") return true
  if (key === "totp") return item.hasTotp === true
  return canonicalItemType(item.itemType) === key
}

function matchesVault(item, shareId) {
  return !shareId || String(item && item.shareId || "") === String(shareId)
}

function filterItems(items, filter, shareId) {
  var list = items || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (matchesVault(list[i], shareId) && matchesFilter(list[i], filter)) out.push(list[i])
  }
  return out
}

// Chips for the filter bar: "All" and every filter that has at least one item.
function filterChips(items, shareId) {
  var counts = {}
  var list = items || []
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (!matchesVault(item, shareId)) continue
    counts.all = (counts.all || 0) + 1
    if (item.hasTotp === true) counts.totp = (counts.totp || 0) + 1
    var type = canonicalItemType(item.itemType) || "custom"
    counts[type] = (counts[type] || 0) + 1
  }
  var chips = []
  for (var j = 0; j < FILTER_ORDER.length; j++) {
    var key = FILTER_ORDER[j]
    if (key !== "all" && !counts[key]) continue
    chips.push({ key: key, label: filterLabel(key), glyph: filterGlyph(key), count: counts[key] || 0 })
  }
  return chips
}

function nextFilter(chips, current, step) {
  var list = chips || []
  if (list.length === 0) return "all"
  var index = 0
  for (var i = 0; i < list.length; i++) if (list[i].key === current) index = i
  index = (index + step + list.length) % list.length
  return list[index].key
}

// ── List rows ─────────────────────────────────────────────────────────────────

// Flat rows for the list view: section headers and items. `items` lists the row
// index of every item so the keyboard cursor can skip headers.
function buildListRows(sections) {
  var rows = []
  var itemRows = []
  var seen = {}
  var list = sections || []
  for (var i = 0; i < list.length; i++) {
    var section = list[i]
    var entries = []
    var sectionItems = section.items || []
    for (var j = 0; j < sectionItems.length; j++) {
      var key = itemKey(sectionItems[j])
      if (key === "/" || seen[key]) continue
      seen[key] = true
      entries.push(sectionItems[j])
    }
    if (entries.length === 0) continue
    if (section.title) rows.push({ kind: "header", title: section.title, count: entries.length, key: "h:" + section.title })
    for (var k = 0; k < entries.length; k++) {
      itemRows.push(rows.length)
      rows.push({ kind: "item", item: entries[k], key: itemKey(entries[k]), cursor: itemRows.length - 1 })
    }
  }
  return { rows: rows, items: itemRows }
}

// ── Live 2FA ──────────────────────────────────────────────────────────────────

function totpShareIds(items) {
  var seen = {}
  var out = []
  var list = items || []
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    var shareId = item && item.hasTotp === true ? String(item.shareId || "") : ""
    if (shareId && !seen[shareId]) {
      seen[shareId] = true
      out.push(shareId)
    }
  }
  return out
}

function parseTotpFeedLine(line) {
  var parsed = parseJson(line)
  if (!parsed || typeof parsed !== "object") return null
  if (parsed.ok !== true) return { ok: false, status: String(parsed.status || "error"), codes: {} }
  var codes = {}
  var raw = parsed.codes && typeof parsed.codes === "object" ? parsed.codes : {}
  var keys = Object.keys(raw)
  for (var i = 0; i < keys.length; i++) {
    var entry = raw[keys[i]]
    if (!entry || !/^\d{6,8}$/.test(String(entry.code || ""))) continue
    codes[keys[i]] = {
      code: String(entry.code),
      period: Number(entry.period) || 30,
      expires: Number(entry.expires) || 0
    }
  }
  return { ok: true, status: "ready", codes: codes }
}

// The live code for an item at `nowMs`, or null when there is none or it expired.
function liveCode(codes, item, nowMs) {
  var entry = codes ? codes[itemKey(item)] : null
  if (!entry) return null
  var remaining = entry.expires - Math.floor(Number(nowMs) / 1000)
  if (remaining <= 0 || remaining > entry.period) return null
  return { code: entry.code, remaining: remaining, fraction: remaining / entry.period }
}

function formatCode(code) {
  var text = String(code || "")
  if (text.length === 6) return text.slice(0, 3) + " " + text.slice(3)
  if (text.length === 8) return text.slice(0, 4) + " " + text.slice(4)
  return text
}

// ── Generator ─────────────────────────────────────────────────────────────────

var PASSPHRASE_SEPARATORS = ["hyphens", "spaces", "periods", "commas", "underscores", "numbers", "numbers-and-symbols"]

function clampInt(value, min, max, fallback) {
  var n = parseInt(value, 10)
  if (!isFinite(n)) n = fallback
  return Math.max(min, Math.min(max, n))
}

function generatorOptions(options) {
  var o = options || {}
  var mode = o.mode === "passphrase" ? "passphrase" : "random"
  return {
    mode: mode,
    length: clampInt(o.length, 8, 64, 20),
    uppercase: o.uppercase !== false,
    numbers: o.numbers !== false,
    symbols: o.symbols !== false,
    words: clampInt(o.words, 3, 10, 5),
    separator: PASSPHRASE_SEPARATORS.indexOf(o.separator) >= 0 ? o.separator : "hyphens",
    capitalise: o.capitalise !== false
  }
}

function generatorArgs(options) {
  var o = generatorOptions(options)
  if (o.mode === "passphrase") {
    return ["password", "generate", "passphrase",
      "--count", String(o.words),
      "--separator", o.separator,
      "--capitalise", String(o.capitalise),
      "--numbers", String(o.numbers),
      "--output", "json"]
  }
  return ["password", "generate", "random",
    "--length", String(o.length),
    "--uppercase", String(o.uppercase),
    "--numbers", String(o.numbers),
    "--symbols", String(o.symbols),
    "--output", "json"]
}

function parseGeneratedPassword(raw) {
  var parsed = parseJson(raw)
  if (parsed && typeof parsed === "object" && typeof parsed.password === "string") return parsed.password
  var text = String(raw || "").replace(/\r?\n$/, "")
  return text.indexOf("\n") < 0 && text.charAt(0) !== "{" ? text : ""
}

// Entropy of the generator settings (not of a specific password), in bits.
function generatorStrength(options) {
  var o = generatorOptions(options)
  var bits
  if (o.mode === "passphrase") {
    bits = o.words * Math.log(7776) / Math.LN2
    if (o.numbers) bits += o.words * Math.log(10) / Math.LN2 * 0.5
    if (o.capitalise) bits += 1
  } else {
    var pool = 26 + (o.uppercase ? 26 : 0) + (o.numbers ? 10 : 0) + (o.symbols ? 30 : 0)
    bits = o.length * Math.log(pool) / Math.LN2
  }
  bits = Math.round(bits)
  var level = bits >= 100 ? 4 : bits >= 75 ? 3 : bits >= 55 ? 2 : bits >= 40 ? 1 : 0
  var labels = ["Weak", "Fair", "Good", "Strong", "Excellent"]
  return { bits: bits, level: level, label: labels[level], fraction: Math.min(1, bits / 120) }
}

// ── Misc ──────────────────────────────────────────────────────────────────────

function fieldLabel(field) {
  var key = String(field || "")
  if (key === "password") return "Password"
  if (key === "username") return "Username"
  if (key === "email") return "Email"
  if (key === "totp") return "2FA code"
  if (key === "") return "Value"
  return key.charAt(0).toUpperCase() + key.slice(1)
}

// http(s) URL to hand to xdg-open, or "" when the value is not a web address.
function openableUrl(value) {
  var text = String(value || "").trim()
  if (text === "" || /\s/.test(text)) return ""
  if (!/^[a-z][a-z0-9+.-]*:/i.test(text)) text = "https://" + text
  return /^https?:\/\/[^\/\s]+/i.test(text) ? text : ""
}

function primaryUrl(item) {
  var urls = item && item.urls ? item.urls : []
  for (var i = 0; i < urls.length; i++) {
    var url = openableUrl(urls[i])
    if (url !== "") return url
  }
  return ""
}

