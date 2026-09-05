#!/usr/bin/env node
"use strict"

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const Model = new Function(
  fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8") +
    "\nreturn { parseItemList, parseVaultList, parseInfo, parseFetchResult, parseItemPreview, parseItemInspector: typeof parseItemInspector === 'function' ? parseItemInspector : null, parseTotpCodes: typeof parseTotpCodes === 'function' ? parseTotpCodes : null, totpSecondsRemaining: typeof totpSecondsRemaining === 'function' ? totpSecondsRemaining : null, itemTypeLabel: typeof itemTypeLabel === 'function' ? itemTypeLabel : null, itemTypeGlyph: typeof itemTypeGlyph === 'function' ? itemTypeGlyph : null, faviconUrl: typeof faviconUrl === 'function' ? faviconUrl : null, faviconUrls: typeof faviconUrls === 'function' ? faviconUrls : null, nextFaviconIndex: typeof nextFaviconIndex === 'function' ? nextFaviconIndex : null, needsPreview: typeof needsPreview === 'function' ? needsPreview : null, primaryCopyField: typeof primaryCopyField === 'function' ? primaryCopyField : null, mergeItemPreview, mergeItemLists, mergePartialItemLists: typeof mergePartialItemLists === 'function' ? mergePartialItemLists : null, applyPreviewUpdates, applyPreviewBatch, parseCache, serializeCache, vaultsFromItems, buildCreateLoginCommand, buildCreateLoginRequest: typeof buildCreateLoginRequest === 'function' ? buildCreateLoginRequest : null, clipboardClearDelayMs: typeof clipboardClearDelayMs === 'function' ? clipboardClearDelayMs : null, accountLabel, itemSubtitle, letterGlyph, passUri, searchItems, suggestedItems, recentlyCreated, recentlyUsed, withoutItems, itemKey, cursorItemCount, cursorItemAt, resolveCursorRow, rememberFailedPreviewKey, hasFailedPreviewKey, clearFailedPreviewKeys, isSessionBlockingStatus, classifyError, cleanCliText, displayError }\n"
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
assert.strictEqual(summaryItems.length, 2, "notes and other types stay in the list")
const summaryLogin = summaryItems.find(function (item) { return item.itemType === "login" })
const summaryNote = summaryItems.find(function (item) { return item.itemType === "note" })
assert.ok(summaryLogin)
assert.strictEqual(summaryLogin.title, "GitHub")
assert.strictEqual(summaryLogin.id, "item-gh")
assert.strictEqual(summaryLogin.shareId, "share-1")
assert.strictEqual(summaryLogin.vaultName, "Personal")
assert.strictEqual(summaryLogin.username, "")
assert.ok(!("password" in summaryLogin))
assert.ok(summaryNote)
assert.strictEqual(summaryNote.title, "Secret note")
assert.ok(!("note" in summaryNote), "list metadata must not keep note bodies")
assert.ok(!JSON.stringify(summaryItems).includes("password"))

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
assert.strictEqual(Model.itemSubtitle(summaryLogin), "Personal")
assert.strictEqual(Model.itemSubtitle(summaryNote), "Note · Personal")
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
assert.strictEqual(Model.searchItems(mixed, "").length, 3)

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
assert.deepStrictEqual(skipped.map(function (item) { return item.title }), ["Secret note", "Discord"])
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
assert.strictEqual(
  Model.classifyError("Error: Local encryption key not found but local data exists. Forcing logout for security.\nRun 'pass-cli login' to authenticate again.", 1),
  "unauthenticated"
)
assert.strictEqual(Model.classifyError("Session is locked", 1), "locked")
assert.strictEqual(Model.classifyError("pass-cli: command not found", 127), "missing")
assert.strictEqual(Model.classifyError("boom", 1), "error")
assert.strictEqual(Model.classifyError("[2m2026-08-14T23:55:02.359500Z[0m [31mERROR[0m [2mpass-cli/src/main.rs[0m[2m:[0m[2m332:[0m Command is not logout there is no session", 1), "unauthenticated")
assert.strictEqual(Model.classifyError("Could not load login item", 1), "error")
assert.strictEqual(Model.classifyError("Network login request failed", 1), "error")
assert.strictEqual(Model.classifyError("Password authentication failed", 1), "error")
assert.strictEqual(Model.classifyError("Unauthorized network response", 1), "error")
assert.strictEqual(Model.classifyError("sqlcipher_page_cipher: hmac check failed for pgno=1", 1), "migration-required")
assert.strictEqual(
  Model.classifyError("Failed to open encrypted database: file is not a database. The encryption key may not match", 1),
  "migration-required"
)
assert.strictEqual(Model.classifyError("sqlite3Codec: error decrypting page 1 data", 1), "migration-required")
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

const fetchPartial = Model.parseFetchResult(JSON.stringify({
  ok: true,
  status: "partial",
  email: "me@example.com",
  warning: {
    kind: "partial-vault-failure",
    failedVaultCount: 1,
    failedVaultNames: ["Work"],
    failedShareIds: ["share-2"],
    message: "Could not refresh 1 vault: Work."
  },
  items: [
    {
      id: "item-gh",
      share_id: "share-1",
      title: "GitHub",
      item_type: "login",
      vault_name: "Personal"
    }
  ]
}))
assert.strictEqual(fetchPartial.ok, true)
assert.strictEqual(fetchPartial.status, "partial")
assert.strictEqual(fetchPartial.warning.failedVaultCount, 1)
assert.deepStrictEqual(fetchPartial.warning.failedVaultNames, ["Work"])
assert.deepStrictEqual(fetchPartial.warning.failedShareIds, ["share-2"])
assert.strictEqual(fetchPartial.warning.message, "Could not refresh 1 vault: Work.")

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
  "--share-id=share-1",
  "--from-template", "-"
])
assert.ok(!createArgs.includes("--password"))
assert.ok(!createArgs.includes("secret"))

assert.strictEqual(typeof Model.buildCreateLoginRequest, "function")
const distinctivePassword = "argv-leak-regression-4f06d6"
const customRequest = Model.buildCreateLoginRequest({
  shareId: "share-1",
  title: "GitHub",
  username: "elli",
  email: "elli@example.com",
  password: distinctivePassword,
  url: "https://github.com"
})
assert.deepStrictEqual(customRequest.args, [
  "item", "create", "login",
  "--share-id=share-1",
  "--from-template", "-"
])
assert.ok(!customRequest.args.includes("--password"))
assert.ok(!customRequest.args.some(function (arg) { return String(arg).includes(distinctivePassword) }))
assert.strictEqual(customRequest.needsPasswordGeneration, false)
assert.deepStrictEqual(JSON.parse(customRequest.stdin), {
  title: "GitHub",
  username: "elli",
  email: "elli@example.com",
  password: distinctivePassword,
  urls: ["https://github.com"]
})

const generated = Model.buildCreateLoginCommand({
  vaultName: "Personal",
  title: "New",
  generatePassword: true
})
assert.deepStrictEqual(generated, [
  "item", "create", "login",
  "--vault-name", "Personal",
  "--from-template", "-"
])
assert.ok(!generated.includes("--password"))
assert.ok(!generated.includes("--generate-password"))
assert.ok(!generated.includes("--title"))
assert.ok(!generated.includes("New"))
const generatedRequest = Model.buildCreateLoginRequest({
  vaultName: "Personal",
  title: "New",
  username: "alice",
  generatePassword: true
})
assert.deepStrictEqual(generatedRequest.args, generated)
assert.strictEqual(generatedRequest.stdin, "")
assert.strictEqual(generatedRequest.needsPasswordGeneration, true)
assert.ok(!generatedRequest.args.includes("alice"))
assert.ok(!generatedRequest.args.includes("--username"))

const dashedShareId = "-XMlw7-WpkQ"
const dashedCreate = Model.buildCreateLoginCommand({
  shareId: dashedShareId,
  title: "GitHub",
  password: "secret"
})
assert.ok(dashedCreate.includes("--share-id=" + dashedShareId), "dash-prefixed share ids must join the flag with =")
assert.ok(!dashedCreate.includes("--share-id"), "create argv must not pass --share-id as its own token")
assert.ok(!dashedCreate.includes(dashedShareId), "dash-prefixed share ids must not be a separate argv token")

assert.strictEqual(typeof Model.clipboardClearDelayMs, "function")
assert.strictEqual(Model.clipboardClearDelayMs(0), 0)
assert.strictEqual(Model.clipboardClearDelayMs("45"), 45000)
assert.strictEqual(Model.clipboardClearDelayMs(-3), 0)
assert.strictEqual(Model.clipboardClearDelayMs("nope"), 0)
assert.strictEqual(Model.clipboardClearDelayMs(9999), 300000)
assert.strictEqual(Model.clipboardClearDelayMs(undefined), 0)

assert.strictEqual(typeof Model.mergePartialItemLists, "function")
const partialMerged = Model.mergePartialItemLists(
  [
    { id: "old-ok", shareId: "share-1", title: "Old Personal" },
    { id: "old-failed", shareId: "share-2", title: "Cached Work" }
  ],
  [{ id: "new-ok", shareId: "share-1", title: "New Personal" }],
  ["share-2"]
)
assert.deepStrictEqual(partialMerged.map(function (item) { return item.title }), [
  "New Personal",
  "Cached Work"
])

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

assert.strictEqual(typeof Model.parseItemInspector, "function")
assert.strictEqual(typeof Model.parseTotpCodes, "function")
assert.strictEqual(typeof Model.totpSecondsRemaining, "function")
assert.strictEqual(typeof Model.itemTypeLabel, "function")
assert.strictEqual(typeof Model.primaryCopyField, "function")

function inspectorField(inspector, id) {
  const sections = inspector && inspector.sections ? inspector.sections : []
  for (let i = 0; i < sections.length; i++) {
    const fields = sections[i].fields || []
    for (let j = 0; j < fields.length; j++) {
      if (fields[j].id === id || fields[j].field === id) return fields[j]
    }
  }
  return null
}

assert.strictEqual(Model.itemTypeLabel("credit-card"), "Card")
assert.strictEqual(Model.itemTypeLabel("ssh-key"), "SSH key")
assert.strictEqual(Model.itemTypeLabel("wifi"), "Wi-Fi")
assert.strictEqual(Model.primaryCopyField({ itemType: "login" }), "password")
assert.strictEqual(Model.primaryCopyField({ itemType: "note" }), "")
assert.strictEqual(Model.primaryCopyField({ itemType: "credit-card" }), "")
assert.ok(Model.itemTypeGlyph({ itemType: "note" }))
assert.notStrictEqual(Model.itemTypeGlyph({ itemType: "note" }), Model.itemTypeGlyph({ itemType: "login" }))
assert.strictEqual(typeof Model.faviconUrl, "function")
function gicon(host) {
  return "https://www.google.com/s2/favicons?domain=" + host + "&sz=64"
}
function originIcon(host) {
  return "https://" + host + "/favicon.ico"
}
assert.strictEqual(Model.faviconUrl({ urls: ["https://github.com/login"] }), originIcon("github.com"))
assert.deepStrictEqual(Model.faviconUrls({ urls: ["https://github.com/login"] }), [
  originIcon("github.com"),
  gicon("github.com")
])
assert.deepStrictEqual(Model.faviconUrls({ urls: ["https://www.discord.com/channels/1"] }), [
  originIcon("discord.com"),
  gicon("discord.com")
])
assert.deepStrictEqual(Model.faviconUrls({ urls: ["", "https://account.proton.me/"] }), [
  originIcon("account.proton.me"),
  gicon("account.proton.me"),
  gicon("proton.me")
])
assert.deepStrictEqual(Model.faviconUrls({ title: "id.sinch.com", urls: [] }), [
  originIcon("id.sinch.com"),
  gicon("id.sinch.com"),
  gicon("sinch.com")
])
assert.strictEqual(Model.faviconUrl({ title: "git.elliotmoreau.fr", username: "git" }), originIcon("git.elliotmoreau.fr"))
assert.strictEqual(Model.faviconUrl({ title: "Stripe", urls: [] }), originIcon("stripe.com"))
assert.strictEqual(Model.faviconUrl({ title: "nvidia" }), originIcon("nvidia.com"))
assert.strictEqual(Model.faviconUrl({ title: "RandomApp", email: "me@gmail.com" }), originIcon("randomapp.com"))
assert.ok(!String(Model.faviconUrl({ title: "RandomApp", email: "me@gmail.com" })).includes("gmail.com"), "consumer mail hosts are not icons")
assert.strictEqual(Model.faviconUrl({ urls: [] }), "")
assert.strictEqual(Model.faviconUrl(null), "")
assert.strictEqual(Model.faviconUrl({ urls: ["javascript:alert(1)"] }), "")
assert.strictEqual(Model.faviconUrl({ urls: ["https://127.0.0.1/login"] }), "")
assert.strictEqual(Model.faviconUrl({ urls: ["https://192.168.0.10/"] }), "")
assert.strictEqual(Model.faviconUrl({ urls: ["https://localhost/"] }), "")
assert.ok(!String(Model.faviconUrls({ urls: ["https://evil.com/x"] }).join(" ")).includes("evil.com/x"))
assert.ok(Model.faviconUrls({ urls: ["https://stripe.com"] }).some(function (url) {
  return url.indexOf("google.com/s2/favicons") >= 0 && url.indexOf(".ico") < 0
}), "each host still has a PNG fallback Qt can decode")
assert.deepStrictEqual(
  Model.faviconUrls({
    urls: ["https://konsoleh.hetzner.com/", "https://cloud.elliotmoreau.fr/"]
  }),
  [
    originIcon("konsoleh.hetzner.com"),
    gicon("konsoleh.hetzner.com"),
    gicon("hetzner.com"),
    originIcon("cloud.elliotmoreau.fr"),
    gicon("cloud.elliotmoreau.fr"),
    gicon("elliotmoreau.fr")
  ]
)
assert.deepStrictEqual(
  Model.faviconUrls({ urls: ["https://www.github.com/", "https://github.com/login"] }),
  [originIcon("github.com"), gicon("github.com")]
)
assert.deepStrictEqual(
  Model.faviconUrls({ urls: ["https://127.0.0.1/", "https://stripe.com"] }),
  [originIcon("stripe.com"), gicon("stripe.com")]
)
assert.deepStrictEqual(
  Model.faviconUrls({ title: "Stripe", urls: ["https://konsoleh.hetzner.com/"] }),
  [
    originIcon("konsoleh.hetzner.com"),
    gicon("konsoleh.hetzner.com"),
    gicon("hetzner.com"),
    originIcon("stripe.com"),
    gicon("stripe.com")
  ]
)
assert.strictEqual(Model.nextFaviconIndex(2, 0, true), 1)
assert.strictEqual(Model.nextFaviconIndex(2, 1, true), 1)
assert.strictEqual(Model.nextFaviconIndex(2, 0, false), 0)
assert.strictEqual(Model.nextFaviconIndex(0, 0, true), 0)

assert.strictEqual(typeof Model.needsPreview, "function")
assert.strictEqual(Model.needsPreview({
  id: "a", shareId: "s", itemType: "login", username: "ada", urls: []
}), true, "cached usernames must not skip website preview")
assert.strictEqual(Model.needsPreview({
  id: "a", shareId: "s", itemType: "login", username: "ada", urls: ["https://stripe.com"]
}), false)
assert.strictEqual(Model.needsPreview({
  id: "a", shareId: "s", itemType: "login", username: "ada", urls: [], previewed: true
}), false)
assert.strictEqual(Model.needsPreview({
  id: "a", shareId: "s", itemType: "note", urls: []
}), false)

assert.strictEqual(
  Model.searchItems([{ title: "Home", itemType: "wifi", vaultName: "Personal" }], "wifi").length,
  1,
  "type labels are searchable"
)

const notePreview = Model.parseItemPreview(JSON.stringify({
  id: "item-note",
  share_id: "share-1",
  item_type: "note",
  content: { title: "Secret note", note: "body stays in inspector", content: { Note: {} } }
}))
assert.strictEqual(notePreview, null, "item view previews stay login-only")

const cachedNote = Model.serializeCache("me@example.com", 1, [summaryNote], 0)
assert.strictEqual(cachedNote.items[0].itemType, "note")
assert.ok(!("note" in cachedNote.items[0]))
assert.ok(!JSON.stringify(cachedNote).includes("body stays"))

const loginInspector = Model.parseItemInspector(JSON.stringify({
  id: "item-dc",
  share_id: "share-2",
  content: {
    title: "Discord",
    note: "recovery codes live here",
    content: {
      Login: {
        email: "me@example.com",
        username: "elli",
        password: "super-secret",
        urls: ["https://discord.com"],
        totp_uri: "otpauth://totp/Discord?secret=ABC"
      }
    },
    extra_fields: [
      { name: "pin", content: { Hidden: "1234" } },
      { name: "Backup", content: { Totp: "otpauth://totp/Backup?secret=DEF" } }
    ]
  }
}))
assert.ok(loginInspector)
assert.strictEqual(loginInspector.itemType, "login")
assert.strictEqual(loginInspector.title, "Discord")
assert.strictEqual(loginInspector.hasTotp, true)
assert.strictEqual(inspectorField(loginInspector, "username").value, "elli")
assert.strictEqual(inspectorField(loginInspector, "password").kind, "secret")
assert.strictEqual(inspectorField(loginInspector, "password").value, "super-secret")
assert.strictEqual(inspectorField(loginInspector, "totp").kind, "totp")
assert.ok(!String(inspectorField(loginInspector, "totp").value).includes("otpauth"))
assert.strictEqual(inspectorField(loginInspector, "pin").kind, "secret")
assert.strictEqual(inspectorField(loginInspector, "pin").value, "1234")
assert.strictEqual(inspectorField(loginInspector, "Backup").kind, "totp")
assert.strictEqual(inspectorField(loginInspector, "note").kind, "note")
assert.strictEqual(inspectorField(loginInspector, "note").value, "recovery codes live here")
assert.ok(!JSON.stringify(loginInspector).includes("otpauth"))

const noteInspector = Model.parseItemInspector(JSON.stringify({
  item: {
    id: "item-note",
    share_id: "share-1",
    content: { title: "Secret note", note: "hello from the vault", content: { Note: {} } }
  }
}))
assert.strictEqual(noteInspector.itemType, "note")
assert.strictEqual(inspectorField(noteInspector, "note").value, "hello from the vault")
assert.strictEqual(inspectorField(noteInspector, "note").kind, "note")

const cardInspector = Model.parseItemInspector(JSON.stringify({
  content: {
    title: "Visa",
    content: {
      CreditCard: {
        cardholder_name: "Ada Lovelace",
        number: "4111111111111111",
        verification_number: "123",
        expiration_date: "2030-12",
        pin: "9999"
      }
    }
  }
}))
assert.strictEqual(cardInspector.itemType, "credit-card")
assert.strictEqual(inspectorField(cardInspector, "number").kind, "secret")
assert.strictEqual(inspectorField(cardInspector, "pin").kind, "secret")
assert.strictEqual(inspectorField(cardInspector, "cardholder_name").value, "Ada Lovelace")

const wifiInspector = Model.parseItemInspector(JSON.stringify({
  content: {
    title: "Office",
    content: { Wifi: { ssid: "Office-5G", password: "airgap", security: "WPA2", sections: [] } }
  }
}))
assert.strictEqual(wifiInspector.itemType, "wifi")
assert.strictEqual(inspectorField(wifiInspector, "ssid").value, "Office-5G")
assert.strictEqual(inspectorField(wifiInspector, "password").kind, "secret")

const sshInspector = Model.parseItemInspector(JSON.stringify({
  content: {
    title: "Deploy",
    extra_fields: [{ name: "Passphrase", content: { Hidden: "phrase" } }],
    content: { SshKey: { private_key: "-----BEGIN OPENSSH PRIVATE KEY-----", public_key: "ssh-ed25519 AAAA", sections: [] } }
  }
}))
assert.strictEqual(sshInspector.itemType, "ssh-key")
assert.strictEqual(inspectorField(sshInspector, "private_key").kind, "secret")
assert.strictEqual(inspectorField(sshInspector, "Passphrase").kind, "secret")

const identityInspector = Model.parseItemInspector(JSON.stringify({
  content: {
    title: "Ada",
    content: {
      Identity: {
        full_name: "Ada Lovelace",
        email: "ada@example.com",
        phone_number: "+1",
        social_security_number: "000-00-0000",
        street_address: "1 Park",
        city: "London",
        company: "Analytical",
        extra_personal_details: [],
        extra_address_details: [],
        extra_contact_details: [],
        extra_work_details: [],
        extra_sections: []
      }
    }
  }
}))
assert.strictEqual(identityInspector.itemType, "identity")
assert.strictEqual(inspectorField(identityInspector, "full_name").value, "Ada Lovelace")
assert.strictEqual(inspectorField(identityInspector, "social_security_number").kind, "secret")
assert.ok(identityInspector.sections.some(function (section) { return section.title === "Address" }))
assert.ok(identityInspector.sections.some(function (section) { return section.title === "Work" }))

const aliasInspector = Model.parseItemInspector(JSON.stringify({
  alias_email: "hide@proton.me",
  content: { title: "Hide my email", content: { Alias: {} } }
}))
assert.strictEqual(aliasInspector.itemType, "alias")
assert.strictEqual(inspectorField(aliasInspector, "email").value, "hide@proton.me")

const customInspector = Model.parseItemInspector(JSON.stringify({
  content: {
    title: "API",
    content: {
      Custom: {
        sections: [{
          section_name: "Production",
          section_fields: [
            { field_name: "token", content: { Hidden: "tok_live" } },
            { field_name: "endpoint", content: { Text: "https://api.example" } }
          ]
        }]
      }
    }
  }
}))
assert.strictEqual(customInspector.itemType, "custom")
assert.strictEqual(inspectorField(customInspector, "Production.token").kind, "secret")
assert.strictEqual(inspectorField(customInspector, "Production.token").field, "Production.token")
assert.strictEqual(inspectorField(customInspector, "Production.endpoint").value, "https://api.example")

const attachmentInspector = Model.parseItemInspector(JSON.stringify({
  attachments: [{ name: "passport.pdf", size: 12 }],
  content: { title: "Files", note: "", content: { Note: {} } }
}))
assert.strictEqual(inspectorField(attachmentInspector, "attachment-0").value, "passport.pdf")
assert.notStrictEqual(inspectorField(attachmentInspector, "attachment-0").kind, "secret")

assert.deepStrictEqual(Model.parseTotpCodes(JSON.stringify({ totp: "123456", Backup: "654321" })), {
  totp: "123456",
  Backup: "654321"
})
assert.deepStrictEqual(Model.parseTotpCodes("not-json"), {})
assert.strictEqual(Model.totpSecondsRemaining(Date.UTC(2026, 0, 1, 0, 0, 0), 30), 30)
assert.strictEqual(Model.totpSecondsRemaining(Date.UTC(2026, 0, 1, 0, 0, 1), 30), 29)
assert.strictEqual(Model.totpSecondsRemaining(Date.UTC(2026, 0, 1, 0, 0, 29), 30), 1)

console.log("ok")
