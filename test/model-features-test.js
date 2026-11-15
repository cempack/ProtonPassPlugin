#!/usr/bin/env node
"use strict"

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const SOURCE = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const NAMES = Array.from(SOURCE.matchAll(/^function ([A-Za-z0-9_]+)\(/gm), function (m) { return m[1] })
const Model = new Function(SOURCE + "\nreturn { " + NAMES.join(", ") + " }\n")()

const items = [
  { id: "1", shareId: "p", title: "GitHub", itemType: "login", urls: ["https://github.com"], username: "octo", hasTotp: true },
  { id: "2", shareId: "p", title: "Gitea", itemType: "login", urls: [] },
  { id: "3", shareId: "p", title: "My notes about git", itemType: "note" },
  { id: "4", shareId: "w", title: "Company card", itemType: "credit-card" },
  { id: "5", shareId: "w", title: "Forge", itemType: "login", urls: ["https://git.example.com"], hasTotp: true }
]
const titles = function (list) { return list.map(function (item) { return item.title }) }

// Search: every term must match, title prefix ranks first, input order breaks ties.
assert.deepStrictEqual(titles(Model.searchItems(items, "git")), ["GitHub", "Gitea", "My notes about git", "Forge"])
assert.deepStrictEqual(titles(Model.searchItems(items, "git octo")), ["GitHub"])
assert.deepStrictEqual(titles(Model.searchItems(items, "  ")), titles(items))
assert.deepStrictEqual(Model.searchItems(items, "zzz"), [])
assert.doesNotThrow(function () { Model.searchItems(items, "c++ (") }, "regex metacharacters are escaped")

// Filters and chips.
const chips = Model.filterChips(items, "")
assert.deepStrictEqual(chips.map(function (c) { return c.key }), ["all", "totp", "login", "note", "credit-card"])
assert.deepStrictEqual(chips.map(function (c) { return c.count }), [5, 2, 3, 1, 1])
assert.deepStrictEqual(Model.filterChips(items, "w").map(function (c) { return c.key + ":" + c.count }), ["all:2", "totp:1", "login:1", "credit-card:1"])
assert.deepStrictEqual(titles(Model.filterItems(items, "totp", "")), ["GitHub", "Forge"])
assert.deepStrictEqual(titles(Model.filterItems(items, "login", "w")), ["Forge"])
assert.deepStrictEqual(titles(Model.filterItems(items, "all", "")), titles(items))
assert.strictEqual(Model.nextFilter(chips, "all", 1), "totp")
assert.strictEqual(Model.nextFilter(chips, "all", -1), "credit-card", "filter cycling wraps")
assert.strictEqual(Model.nextFilter([], "all", 1), "all")
assert.strictEqual(Model.filterLabel("totp"), "2FA")

// List rows skip duplicates across sections and drop empty sections.
const built = Model.buildListRows([
  { title: "Suggested", items: [items[0]] },
  { title: "Empty", items: [] },
  { title: "Recent", items: [items[0], items[1]] }
])
assert.deepStrictEqual(built.rows.map(function (r) { return r.kind + ":" + (r.title || r.item.title) }), [
  "header:Suggested", "item:GitHub", "header:Recent", "item:Gitea"
])
assert.deepStrictEqual(built.items, [1, 3])
assert.deepStrictEqual(built.rows.filter(function (r) { return r.kind === "item" }).map(function (r) { return r.cursor }), [0, 1])
assert.deepStrictEqual(Model.buildListRows([{ title: "", items: items.slice(0, 2) }]).items, [0, 1], "untitled sections add no header")

// Live 2FA.
assert.deepStrictEqual(Model.totpShareIds(items), ["p", "w"])
const feed = Model.parseTotpFeedLine(JSON.stringify({ ok: true, codes: {
  "p/1": { code: "123456", period: 30, expires: 1000 },
  "p/2": { code: "abc", period: 30, expires: 1000 },
  "w/5": { code: "12345678", period: 60, expires: 1020 }
} }))
assert.deepStrictEqual(Object.keys(feed.codes), ["p/1", "w/5"], "malformed codes are dropped")
assert.deepStrictEqual(Model.parseTotpFeedLine(JSON.stringify({ ok: false, status: "unauthenticated" })), { ok: false, status: "unauthenticated", codes: {} })
assert.strictEqual(Model.parseTotpFeedLine("not json"), null)
assert.deepStrictEqual(Model.liveCode(feed.codes, items[0], 990000), { code: "123456", remaining: 10, fraction: 10 / 30 })
assert.strictEqual(Model.liveCode(feed.codes, items[0], 1000000), null, "expired codes are hidden")
assert.strictEqual(Model.liveCode(feed.codes, items[1], 990000), null)
assert.strictEqual(Model.formatCode("123456"), "123 456")
assert.strictEqual(Model.formatCode("12345678"), "1234 5678")

// Generator.
assert.deepStrictEqual(Model.generatorArgs({ length: 4, symbols: false }), [
  "password", "generate", "random", "--length", "8", "--uppercase", "true", "--numbers", "true", "--symbols", "false", "--output", "json"
], "length is clamped to 8..64")
assert.deepStrictEqual(Model.generatorArgs({ mode: "passphrase", words: 99, separator: "rm -rf" }), [
  "password", "generate", "passphrase", "--count", "10", "--separator", "hyphens", "--capitalise", "true", "--numbers", "true", "--output", "json"
], "unknown separators fall back to hyphens")
assert.strictEqual(Model.parseGeneratedPassword('{"password":"a-b-c"}\n'), "a-b-c")
assert.strictEqual(Model.parseGeneratedPassword("plain\n"), "plain")
assert.strictEqual(Model.parseGeneratedPassword("{broken"), "")
assert.strictEqual(Model.parseGeneratedPassword("two\nlines"), "")
const weak = Model.generatorStrength({ length: 8, uppercase: false, numbers: false, symbols: false })
const strong = Model.generatorStrength({ length: 32 })
assert.ok(weak.level < strong.level)
assert.strictEqual(strong.label, "Excellent")
assert.ok(Model.generatorStrength({ mode: "passphrase", words: 6 }).bits > Model.generatorStrength({ mode: "passphrase", words: 4 }).bits)

// URLs handed to xdg-open must be web addresses.
assert.strictEqual(Model.openableUrl("github.com/login"), "https://github.com/login")
assert.strictEqual(Model.openableUrl("http://intranet"), "http://intranet")
for (const bad of ["", "javascript:alert(1)", "file:///etc/passwd", "ftp://x", "has space.com", "https://"])
  assert.strictEqual(Model.openableUrl(bad), "", bad)
assert.strictEqual(Model.primaryUrl({ urls: ["android://app", "example.org"] }), "https://example.org")
assert.strictEqual(Model.primaryUrl({}), "")

// Merging: fresh listings win, local usage and known login details survive a metadata-only refresh.
const cached = { id: "1", shareId: "p", title: "Old", username: "octo", urls: ["https://github.com"], hasTotp: true, previewed: true, lastUsedAt: 50 }
const freshComplete = { id: "1", shareId: "p", title: "New", username: "", urls: [], hasTotp: false, previewed: true, lastUsedAt: 0 }
const freshBare = { id: "1", shareId: "p", title: "New", username: "", urls: [], hasTotp: false, previewed: false, lastUsedAt: 0 }
assert.deepStrictEqual(Model.mergeCached(freshComplete, cached), Object.assign({}, freshComplete, { lastUsedAt: 50 }))
const keptDetails = Model.mergeCached(freshBare, cached)
assert.strictEqual(keptDetails.title, "New")
assert.strictEqual(keptDetails.username, "octo")
assert.strictEqual(keptDetails.hasTotp, true)
const changed = Model.withChanges(cached, { title: "X" })
assert.strictEqual(changed.title, "X")
assert.strictEqual(cached.title, "Old", "withChanges does not mutate")

// Fetch results built from sanitized items carry the 2FA flag and full details.
const fetched = Model.parseFetchResult(JSON.stringify({ ok: true, items: [
  { id: "x", share_id: "p", title: "T", item_type: "login", username: "u", urls: ["https://t.example"], has_totp: true, complete: true, vault_name: "Personal" }
] }))
assert.strictEqual(fetched.items[0].hasTotp, true)
assert.strictEqual(fetched.items[0].previewed, true)
assert.strictEqual(fetched.items[0].username, "u")

assert.strictEqual(Model.fieldLabel("password"), "Password")
assert.strictEqual(Model.fieldLabel("api_key"), "Api_key")

console.log("ok")
