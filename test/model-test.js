#!/usr/bin/env node
"use strict"

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const Model = new Function(
  fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8") +
    "\nreturn { parseItemList, parseVaultList, parseInfo, parseFetchResult, parseItemPreview, mergeItemPreview, mergeItemLists, applyPreviewUpdates, applyPreviewBatch, parseCache, serializeCache, vaultsFromItems, buildCreateLoginCommand, accountLabel, itemSubtitle, letterGlyph, passUri, searchItems, suggestedItems, recentlyCreated, recentlyUsed, withoutItems, itemKey, cursorItemCount, cursorItemAt, resolveCursorRow, rememberFailedPreviewKey, hasFailedPreviewKey, clearFailedPreviewKeys, isSessionBlockingStatus, classifyError, cleanCliText, displayError }\n"
)()

function summaryList() {
  return JSON.stringify({
    items: [
      {
        id: "item-gh",
        share_id: "share-1",
        vault_id: "vault-1",
        state: "Active",
        flags: [],
        create_time: "2026-08-01T12:00:00",
        modify_time: "2026-08-10T12:00:00",
        title: "GitHub",
        item_type: "login"
      },
      {
        id: "item-note",
        share_id: "share-1",
        title: "Secret note",
        item_type: "note",
        create_time: "2026-08-12T00:00:00"
      }
    ]
  })
}

function secretList() {
  return JSON.stringify({
    items: [
      {
        id: "item-dc",
        share_id: "share-2",
        vault_id: "vault-2",
        state: "Active",
        create_time: "2026-08-14T09:00:00",
        modify_time: "2026-08-14T10:00:00",
        content: {
          title: "Discord",
          note: "do not keep",
          content: {
            Login: {
              email: "me@example.com",
              username: "elli",
              password: "super-secret",
              urls: ["https://discord.com", "https://discord.com/login"],
              totp_uri: "otpauth://totp/Discord?secret=ABC",
              passkeys: []
            }
          },
          extra_fields: [{ name: "pin", value: "1234" }]
        }
      }
    ]
  })
}

const summaryItems = Model.parseItemList(summaryList(), "Personal")
assert.strictEqual(summaryItems.length, 1, "non-login items are dropped")
assert.strictEqual(summaryItems[0].title, "GitHub")
assert.strictEqual(summaryItems[0].id, "item-gh")
assert.strictEqual(summaryItems[0].shareId, "share-1")
assert.strictEqual(summaryItems[0].vaultName, "Personal")
assert.strictEqual(summaryItems[0].username, "")
assert.ok(!("password" in summaryItems[0]))
assert.ok(!JSON.stringify(summaryItems[0]).includes("password"))

const secretItems = Model.parseItemList(secretList(), "Work")
assert.strictEqual(secretItems.length, 1)
assert.strictEqual(secretItems[0].title, "Discord")
assert.strictEqual(secretItems[0].username, "elli")
assert.strictEqual(secretItems[0].email, "me@example.com")
assert.deepStrictEqual(secretItems[0].urls, ["https://discord.com", "https://discord.com/login"])
assert.strictEqual(secretItems[0].hasTotp, true)
assert.ok(!("password" in secretItems[0]), "password must be stripped")
assert.ok(!("totpUri" in secretItems[0]) && !("totp_uri" in secretItems[0]))
assert.ok(!("note" in secretItems[0]))
assert.ok(!("extraFields" in secretItems[0]) && !("extra_fields" in secretItems[0]))
const secretJson = JSON.stringify(secretItems[0])
assert.ok(!secretJson.includes("super-secret"))
assert.ok(!secretJson.includes("otpauth"))
assert.ok(!secretJson.includes("1234"))
assert.ok(!secretJson.includes("do not keep"))

assert.strictEqual(Model.accountLabel(secretItems[0]), "elli")
assert.strictEqual(Model.accountLabel(summaryItems[0]), "")
assert.strictEqual(Model.itemSubtitle(summaryItems[0]), "Personal")
assert.strictEqual(Model.itemSubtitle(secretItems[0]), "elli · me@example.com · discord.com · Work")
assert.strictEqual(Model.itemSubtitle({
  title: "Proton",
  username: "cempack",
  email: "contact@elliotmoreau.fr",
  urls: ["https://account.proton.me/"],
  vaultName: "Personal"
}), "cempack · contact@elliotmoreau.fr · account.proton.me · Personal")
assert.strictEqual(Model.itemSubtitle({
  title: "Proton",
  username: "",
  urls: ["https://account.proton.me/login"],
  vaultName: "Work"
}), "account.proton.me · Work")
assert.ok(!String(Model.itemSubtitle(secretItems[0])).includes("super-secret"))
assert.strictEqual(Model.letterGlyph("Discord"), "D")
assert.strictEqual(Model.letterGlyph("  "), "?")
assert.strictEqual(
  Model.passUri(secretItems[0], "password"),
  "pass://share-2/item-dc/password"
)

const mixed = summaryItems.concat(secretItems)
assert.deepStrictEqual(
  Model.searchItems(mixed, "disc").map(function (item) { return item.title }),
  ["Discord"]
)
assert.deepStrictEqual(
  Model.searchItems(mixed, "github.com").map(function (item) { return item.title }),
  []
)
assert.deepStrictEqual(
  Model.searchItems(mixed, "elli").map(function (item) { return item.title }),
  ["Discord"]
)
assert.strictEqual(Model.searchItems(mixed, "").length, 2)

const suggested = Model.suggestedItems(mixed, "discord", "Discord — #general")
assert.deepStrictEqual(suggested.map(function (item) { return item.title }), ["Discord"])
assert.deepStrictEqual(
  Model.suggestedItems(mixed, "firefox", "GitHub - pull requests").map(function (item) { return item.title }),
  ["GitHub"]
)
assert.deepStrictEqual(Model.suggestedItems(mixed, "", ""), [])

const recent = Model.recentlyCreated(mixed, 1)
assert.deepStrictEqual(recent.map(function (item) { return item.title }), ["Discord"])

const usedFirst = Object.assign({}, summaryItems[0], { lastUsedAt: 9000 })
const usedSecond = Object.assign({}, secretItems[0], { lastUsedAt: 1000, modifyTime: "2026-08-20T00:00:00" })
assert.deepStrictEqual(
  Model.recentlyUsed([usedFirst, usedSecond]).map(function (item) { return item.title }),
  ["GitHub", "Discord"]
)
assert.deepStrictEqual(
  Model.recentlyUsed([
    { title: "OldUse", lastUsedAt: 1, modifyTime: "2026-08-20T00:00:00", createTime: "2026-01-01" },
    { title: "NewEdit", lastUsedAt: 0, modifyTime: "2026-08-21T00:00:00", createTime: "2026-01-01" }
  ]).map(function (item) { return item.title }),
  ["NewEdit", "OldUse"],
  "modifyTime is the fallback when lastUsedAt is missing"
)

const skipped = Model.withoutItems(mixed, [summaryItems[0]])
assert.deepStrictEqual(skipped.map(function (item) { return item.title }), ["Discord"])
assert.strictEqual(Model.itemKey(summaryItems[0]), "share-1/item-gh")

const vaults = Model.parseVaultList(JSON.stringify([
  { share_id: "share-1", name: "Personal" },
  { shareId: "share-2", vault_name: "Work" }
]))
assert.deepStrictEqual(vaults, [
  { shareId: "share-1", name: "Personal" },
  { shareId: "share-2", name: "Work" }
])

const info = Model.parseInfo(JSON.stringify({
  email: "me@example.com",
  username: "elli",
  session_has_lock: true
}))
assert.strictEqual(info.ok, true)
assert.strictEqual(info.email, "me@example.com")
assert.strictEqual(info.sessionHasLock, true)

assert.strictEqual(Model.classifyError("please login first", 1), "unauthenticated")
assert.strictEqual(Model.classifyError("Session is locked", 1), "locked")
assert.strictEqual(Model.classifyError("pass-cli: command not found", 127), "missing")
assert.strictEqual(Model.classifyError("boom", 1), "error")
assert.strictEqual(Model.classifyError("[2m2026-08-14T23:55:02.359500Z[0m [31mERROR[0m [2mpass-cli/src/main.rs[0m[2m:[0m[2m332:[0m Command is not logout there is no session", 1), "unauthenticated")
assert.strictEqual(Model.cleanCliText("[31mERROR[0m boom"), "ERROR boom")
assert.strictEqual(Model.displayError("[2m2026-08-14T23:55:02.359500Z[0m [31mERROR[0m [2mpass-cli/src/main.rs[0m[2m:[0m[2m332:[0m Command is not logout there is no session"), "")
assert.strictEqual(Model.displayError("vault missing"), "vault missing")

assert.deepStrictEqual(Model.parseItemList("not-json", ""), [])
assert.deepStrictEqual(Model.parseVaultList(""), [])

const fetchMissing = Model.parseFetchResult(JSON.stringify({
  ok: false,
  status: "missing",
  message: "pass-cli is not installed",
  items: []
}))
assert.strictEqual(fetchMissing.ok, false)
assert.strictEqual(fetchMissing.status, "missing")
assert.deepStrictEqual(fetchMissing.items, [])

const fetchBusy = Model.parseFetchResult(JSON.stringify({
  ok: false,
  status: "busy",
  message: "",
  items: []
}))
assert.strictEqual(fetchBusy.ok, false)
assert.strictEqual(fetchBusy.status, "busy")
assert.deepStrictEqual(fetchBusy.items, [])
assert.strictEqual(fetchBusy.message, "")
assert.ok(!JSON.stringify(fetchBusy).includes("password"))

const fetchOk = Model.parseFetchResult(JSON.stringify({
  ok: true,
  email: "me@example.com",
  items: [
    {
      id: "item-gh",
      share_id: "share-1",
      title: "GitHub",
      item_type: "login",
      vault_name: "Personal",
      create_time: "2026-08-01T12:00:00"
    }
  ]
}))
assert.strictEqual(fetchOk.ok, true)
assert.strictEqual(fetchOk.email, "me@example.com")
assert.strictEqual(fetchOk.items.length, 1)
assert.strictEqual(fetchOk.items[0].vaultName, "Personal")
assert.ok(!("password" in fetchOk.items[0]))

const preview = Model.parseItemPreview(JSON.stringify({
  id: "item-dc",
  share_id: "share-2",
  content: {
    title: "Discord",
    note: "secret-note",
    content: {
      Login: {
        username: "elli",
        email: "me@example.com",
        password: "super-secret",
        urls: ["https://discord.com"],
        totp_uri: "otpauth://totp/Discord?secret=ABC"
      }
    }
  }
}))
assert.strictEqual(preview.username, "elli")
assert.strictEqual(preview.email, "me@example.com")
assert.deepStrictEqual(preview.urls, ["https://discord.com"])
assert.strictEqual(preview.hasTotp, true)
assert.ok(!("password" in preview))
assert.ok(!JSON.stringify(preview).includes("super-secret"))
assert.ok(!JSON.stringify(preview).includes("otpauth"))

const merged = Model.mergeItemPreview(summaryItems[0], preview)
assert.strictEqual(merged.title, "GitHub")
assert.strictEqual(merged.username, "elli")
assert.strictEqual(merged.hasTotp, true)
assert.ok(!("password" in merged))

const incoming = Model.parseItemList(JSON.stringify({
  items: [
    { id: "item-gh", share_id: "share-1", title: "GitHub", item_type: "login", create_time: "2026-08-01T12:00:00" },
    { id: "item-new", share_id: "share-1", title: "New", item_type: "login", create_time: "2026-08-20T00:00:00" }
  ]
}), "Personal")
const kept = Model.mergeItemLists([Object.assign({}, merged, { lastUsedAt: 555 })], incoming)
assert.strictEqual(kept.length, 2)
assert.strictEqual(kept[0].title, "GitHub")
assert.strictEqual(kept[0].username, "elli", "list refresh must keep previewed username")
assert.strictEqual(kept[0].lastUsedAt, 555, "list refresh must keep last used")
assert.strictEqual(kept[1].title, "New")
assert.strictEqual(kept[1].username, "")

const cacheDoc = Model.serializeCache("me@example.com", 1700000000000, kept, 42)
assert.ok(!JSON.stringify(cacheDoc).includes("password"))
assert.strictEqual(cacheDoc.email, "me@example.com")
assert.strictEqual(cacheDoc.fetchedAt, 1700000000000)
assert.strictEqual(cacheDoc.refreshingAt, 42)
assert.strictEqual(cacheDoc.items[0].username, "elli")

const loaded = Model.parseCache(JSON.stringify(cacheDoc))
assert.strictEqual(loaded.ok, true)
assert.strictEqual(loaded.email, "me@example.com")
assert.strictEqual(loaded.fetchedAt, 1700000000000)
assert.strictEqual(loaded.refreshingAt, 42)
assert.strictEqual(loaded.items[0].username, "elli")
assert.ok(!("password" in loaded.items[0]))

const poisoned = Model.parseCache(JSON.stringify({
  email: "me@example.com",
  fetchedAt: 1,
  items: [{
    id: "item-gh",
    shareId: "share-1",
    itemType: "login",
    title: "GitHub",
    username: "elli",
    password: "should-not-survive"
  }]
}))
assert.ok(poisoned.ok)
assert.strictEqual(poisoned.items[0].username, "elli")
assert.ok(!("password" in poisoned.items[0]))
assert.ok(!JSON.stringify(poisoned).includes("should-not-survive"))

assert.strictEqual(Model.parseCache("").ok, false)
assert.strictEqual(Model.parseCache("not-json").ok, false)

const vaultsFromItems = Model.vaultsFromItems([
  { shareId: "share-1", vaultName: "Personal", title: "A" },
  { shareId: "share-1", vaultName: "Personal", title: "B" },
  { shareId: "share-2", vaultName: "Work", title: "C" },
  { shareId: "", vaultName: "Nope", title: "D" }
])
assert.deepStrictEqual(vaultsFromItems, [
  { shareId: "share-1", name: "Personal" },
  { shareId: "share-2", name: "Work" }
])
assert.deepStrictEqual(Model.vaultsFromItems([]), [])

const createArgs = Model.buildCreateLoginCommand({
  shareId: "share-1",
  title: "GitHub",
  username: "elli",
  password: "secret",
  url: "https://github.com"
})
assert.deepStrictEqual(createArgs, [
  "item", "create", "login",
  "--share-id", "share-1",
  "--title", "GitHub",
  "--username", "elli",
  "--password", "secret",
  "--url", "https://github.com"
])

const generated = Model.buildCreateLoginCommand({
  vaultName: "Personal",
  title: "New",
  generatePassword: true
})
assert.deepStrictEqual(generated, [
  "item", "create", "login",
  "--vault-name", "Personal",
  "--title", "New",
  "--generate-password"
])
assert.ok(!generated.includes("--password"))

const suggestedRows = [
  { id: "s1", shareId: "share", title: "Suggested" },
  { id: "s2", shareId: "share", title: "Also" }
]
const recentRows = [
  { id: "r1", shareId: "share", title: "Recent One" },
  { id: "r2", shareId: "share", title: "Recent Two" },
  { id: "r3", shareId: "share", title: "Recent Three" }
]
const filteredRows = [
  { id: "f1", shareId: "share", title: "Filtered" }
]
assert.strictEqual(Model.cursorItemCount(false, suggestedRows, recentRows, filteredRows), 5)
assert.strictEqual(Model.cursorItemCount(true, suggestedRows, recentRows, filteredRows), 1)
assert.strictEqual(Model.cursorItemAt(false, suggestedRows, recentRows, filteredRows, 0).title, "Suggested")
assert.strictEqual(Model.cursorItemAt(false, suggestedRows, recentRows, filteredRows, 2).title, "Recent One")
assert.strictEqual(Model.cursorItemAt(true, suggestedRows, recentRows, filteredRows, 0).title, "Filtered")
assert.strictEqual(Model.cursorItemAt(false, suggestedRows, recentRows, filteredRows, 99), null)

const baseItems = [
  { id: "a", shareId: "s", title: "A", username: "", email: "", urls: [], hasTotp: false, lastUsedAt: 0 },
  { id: "b", shareId: "s", title: "B", username: "", email: "", urls: [], hasTotp: false, lastUsedAt: 0 },
  { id: "c", shareId: "s", title: "C", username: "keep", email: "", urls: [], hasTotp: false, lastUsedAt: 1 }
]
const batched = Model.applyPreviewUpdates(baseItems, {
  "s/a": { username: "alice", email: "a@example.com", urls: ["https://a.example"], hasTotp: true, password: "nope", totp_uri: "otpauth://secret" },
  "s/b": { username: "bob", password: "also-nope", totpUri: "otpauth://other" }
})
assert.strictEqual(batched.length, 3)
assert.strictEqual(batched[0].username, "alice")
assert.strictEqual(batched[0].email, "a@example.com")
assert.deepStrictEqual(batched[0].urls, ["https://a.example"])
assert.strictEqual(batched[0].hasTotp, true)
assert.strictEqual(batched[1].username, "bob")
assert.strictEqual(batched[2].username, "keep")
assert.ok(!("password" in batched[0]) && !("password" in batched[1]))
assert.ok(!("totp_uri" in batched[0]) && !("totpUri" in batched[1]))
assert.ok(!JSON.stringify(batched).includes("nope"))
assert.ok(!JSON.stringify(batched).includes("otpauth"))
assert.ok(!JSON.stringify(batched).includes("also-nope"))

const unchanged = Model.applyPreviewUpdates(baseItems, {})
assert.strictEqual(unchanged, baseItems, "empty batch should keep the same array reference")

var failedStore = { map: {}, order: [] }
failedStore = Model.rememberFailedPreviewKey(failedStore, "s/a", 3)
assert.strictEqual(Model.hasFailedPreviewKey(failedStore, "s/a"), true)
assert.strictEqual(Model.hasFailedPreviewKey(failedStore, "s/b"), false)
failedStore = Model.rememberFailedPreviewKey(failedStore, "s/b", 3)
failedStore = Model.rememberFailedPreviewKey(failedStore, "s/c", 3)
failedStore = Model.rememberFailedPreviewKey(failedStore, "s/d", 3)
assert.strictEqual(Model.hasFailedPreviewKey(failedStore, "s/a"), false, "oldest failed key is evicted at cap")
assert.strictEqual(Model.hasFailedPreviewKey(failedStore, "s/d"), true)
assert.strictEqual(failedStore.order.length, 3)

assert.strictEqual(Model.isSessionBlockingStatus("locked"), true)
assert.strictEqual(Model.isSessionBlockingStatus("unauthenticated"), true)
assert.strictEqual(Model.isSessionBlockingStatus("migration-required"), true, "classify hook ready for Task 4")
assert.strictEqual(Model.isSessionBlockingStatus("error"), false)
assert.strictEqual(Model.isSessionBlockingStatus("missing"), false)

const browseFirst = { id: "browse", shareId: "share", title: "Always First" }
const searchHit = { id: "hit", shareId: "share", title: "GitHub Token" }
const rankedForActivation = [browseFirst, searchHit]
const liveActivation = Model.resolveCursorRow(
  "git",
  [],
  rankedForActivation,
  rankedForActivation,
  0
)
assert.strictEqual(liveActivation.title, "GitHub Token", "activation must use live query, not stale browse row")
assert.strictEqual(
  Model.resolveCursorRow("", [], rankedForActivation, rankedForActivation, 0).title,
  "Always First",
  "empty live query stays on browse selection"
)
assert.strictEqual(
  Model.resolveCursorRow("missing-query", [], rankedForActivation, rankedForActivation, 0),
  null,
  "live query with no matches yields no activation target"
)

failedStore = Model.rememberFailedPreviewKey({ map: {}, order: [] }, "s/a", 8)
failedStore = Model.rememberFailedPreviewKey(failedStore, "s/b", 8)
assert.strictEqual(Model.hasFailedPreviewKey(failedStore, "s/a"), true)
failedStore = Model.clearFailedPreviewKeys()
assert.strictEqual(Model.hasFailedPreviewKey(failedStore, "s/a"), false)
assert.strictEqual(Model.hasFailedPreviewKey(failedStore, "s/b"), false)
assert.deepStrictEqual(failedStore.order, [])

const batchResult = Model.applyPreviewBatch(baseItems, {
  "s/a": { username: "alice", password: "secret-batch" },
  "s/b": { username: "bob", totp_uri: "otpauth://batch" }
})
assert.strictEqual(batchResult.items[0].username, "alice")
assert.strictEqual(batchResult.updated.length, 2, "batch returns touched rows without rescanning")
assert.strictEqual(batchResult.updated[0].username, "alice")
assert.strictEqual(batchResult.updated[1].username, "bob")
assert.ok(!JSON.stringify(batchResult).includes("secret-batch"))
assert.ok(!JSON.stringify(batchResult).includes("otpauth"))
assert.deepStrictEqual(Model.applyPreviewBatch(baseItems, {}).updated, [])

console.log("ok")
