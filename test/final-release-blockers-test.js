#!/usr/bin/env node
"use strict"

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const ROOT = path.join(__dirname, "..")
const modelSource = fs.readFileSync(path.join(ROOT, "Model.js"), "utf8")
const panelSource = fs.readFileSync(path.join(ROOT, "Panel.qml"), "utf8")
const serviceSource = fs.readFileSync(path.join(ROOT, "PassService.qml"), "utf8")

const Model = new Function(
  modelSource +
    "\nreturn { suggestedItems, recentlyUsed, withoutItems, serializeCache, parseCache }\n"
)()

const failures = []

function test(name, fn) {
  try {
    fn()
    process.stdout.write("ok - " + name + "\n")
  } catch (error) {
    failures.push({ name: name, error: error })
    process.stderr.write("not ok - " + name + "\n")
    process.stderr.write(String(error && error.stack ? error.stack : error) + "\n")
  }
}

function processSection(id, nextId) {
  const start = serviceSource.indexOf("id: " + id)
  assert.ok(start >= 0, "missing process " + id)
  const end = nextId ? serviceSource.indexOf("id: " + nextId, start) : serviceSource.length
  return serviceSource.slice(start, end >= 0 ? end : serviceSource.length)
}

function makeMatchingItems(count) {
  const out = []
  for (let i = 0; i < count; i++) {
    out.push({
      id: "item-" + i,
      shareId: "share-" + (i % 8),
      title: "Login " + i,
      urls: ["https://common.example/account/" + i],
      lastUsedAt: count - i
    })
  }
  return out
}

test("caps many suggestions while preserving all 563 logins", function () {
  const all = makeMatchingItems(563)
  const suggested = Model.suggestedItems(all, "common", "common.example", 6)
  const recent = Model.withoutItems(Model.recentlyUsed(all), suggested)
  assert.strictEqual(suggested.length, 6)
  assert.strictEqual(recent.length, 557)
  assert.strictEqual(suggested.length + recent.length, 563)
  assert.match(panelSource, /suggestedItems\([^)]*,\s*(?:root\.)?suggestedLimit\)/)
  assert.match(panelSource, /readonly property int suggestedLimit:\s*6/)
  assert.doesNotMatch(panelSource, /recentlyUsed\([^)]*,\s*(?:root\.)?suggestedLimit\)/)
})

test("round-trips only sanitized partial warning metadata", function () {
  const warning = {
    kind: "partial-vault-failure",
    failedVaultCount: 2,
    failedVaultNames: ["Work\u001b[31m", "Private\nVault"],
    failedShareIds: ["share-work", "share-private"],
    message: "secret-token backtrace pass-cli/src/main.rs:99"
  }
  const doc = Model.serializeCache("me@example.com", 1234, [], 0, warning)
  const serialized = JSON.stringify(doc)
  assert.ok(!serialized.includes("secret-token"))
  assert.ok(!serialized.includes("main.rs"))

  const loaded = Model.parseCache(serialized)
  assert.deepStrictEqual(loaded.warning.failedVaultNames, ["Work", "Private Vault"])
  assert.deepStrictEqual(loaded.warning.failedShareIds, ["share-work", "share-private"])
  assert.strictEqual(loaded.warning.message, "Could not refresh 2 vaults: Work, Private Vault.")
})

test("hydrates and clears durable partial warning state", function () {
  assert.match(
    serviceSource,
    /function applyCache[\s\S]*parsed\.warning[\s\S]*fetchWarning/,
    "cache hydration restores the warning"
  )
  assert.match(
    serviceSource,
    /serializeCache\([^)]*(?:fetchWarningMetadata|_fetchWarningMetadata)/,
    "atomic cache serialization includes safe warning metadata"
  )
  assert.match(
    serviceSource,
    /parsed\.status === "partial"[\s\S]*(?:fetchWarningMetadata|_fetchWarningMetadata)\s*=[\s\S]*else[\s\S]*(?:fetchWarningMetadata|_fetchWarningMetadata)\s*=\s*null/,
    "only a full successful refresh clears the durable warning"
  )
  assert.match(
    serviceSource,
    /function applyCache[\s\S]*previousFetchedAt[\s\S]*parsed\.warning[\s\S]*parsed\.fetchedAt\s*>\s*previousFetchedAt[\s\S]*fetchWarningMetadata\s*=\s*null/,
    "an equal-generation peer cache write cannot erase a durable warning"
  )
})

test("view reset invalidates and terminates stale secret work", function () {
  assert.match(serviceSource, /property int _viewGeneration:\s*0/)
  assert.match(serviceSource, /property bool _discardViewResult:\s*(?:true|false)/)
  assert.match(
    serviceSource,
    /function resetViewed[\s\S]*_viewGeneration\s*(?:\+\+|=\s*_viewGeneration\s*\+\s*1)[\s\S]*_discardViewResult\s*=\s*true[\s\S]*viewProcess\.(?:signal|running)/,
    "reset invalidates output and terminates an active process"
  )
  const view = processSection("viewProcess", "previewProcess")
  assert.match(view, /onRead:[\s\S]*_discardViewResult|onRead:[\s\S]*_viewGeneration/)
  assert.match(
    view,
    /onExited:[\s\S]*(?:_discardViewResult|_viewProcessGeneration\s*!==\s*root\._viewGeneration)[\s\S]*return/,
    "late exit is discarded before viewedValue can be assigned"
  )
  assert.match(panelSource, /function close\(\)[\s\S]*pass\.resetViewed\(\)/)
  assert.match(panelSource, /function closeDetail\(\)[\s\S]*pass\.resetViewed\(\)/)
})

test("all process paths latch session-blocking failures centrally", function () {
  assert.match(
    serviceSource,
    /function latchSessionBlockingFailure\([^)]*\)[\s\S]*isSessionBlockingStatus[\s\S]*applyStatus/,
    "one helper owns the session latch"
  )
  const sections = [
    ["fetch", processSection("fetchProcess", "copyProcess")],
    ["copy", processSection("copyProcess", "viewProcess")],
    ["view", processSection("viewProcess", "previewProcess")],
    ["preview", processSection("previewProcess", "createProcess")],
    ["create", processSection("createProcess", "generateProcess")],
    ["generate", processSection("generateProcess", null)]
  ]
  for (const entry of sections) {
    assert.match(
      entry[1],
      /latchSessionBlockingFailure/,
      entry[0] + " failures use the centralized latch"
    )
  }
  assert.match(
    serviceSource,
    /function refresh\([^)]*\)[\s\S]*isSessionBlockingStatus\(status\)[\s\S]*force\s*!==\s*true[\s\S]*return/,
    "automatic refreshes stop while session-blocked"
  )
})

test("successful malformed preview JSON backs off and advances", function () {
  const preview = processSection("previewProcess", "createProcess")
  assert.match(
    preview,
    /parseItemPreview[\s\S]{0,120}if \(preview\) \{[\s\S]{0,300}\}\s*else\s*\{[\s\S]{0,160}markPreviewFailed/,
    "successful malformed JSON marks its key failed"
  )
  assert.match(preview, /if \(root\.previewsEnabled\) previewTimer\.restart\(\)/)
})

test("empty successful generation surfaces a sanitized error and clears state", function () {
  const generate = processSection("generateProcess", null)
  assert.match(generate, /root\.generatingPassword\s*=\s*false/)
  assert.match(generate, /root\._generateOutput\s*=\s*""/)
  assert.match(generate, /root\._generateError\s*=\s*""/)
  assert.match(
    generate,
    /if \(exitCode === 0\) \{[\s\S]{0,240}if \(stdout !== ""\)[\s\S]{0,240}else \{[\s\S]{0,120}lastError\s*=\s*"Password generation returned no password\."/
  )
})

if (failures.length > 0) {
  process.stderr.write("\n" + failures.length + " blocker regression test(s) failed\n")
  process.exitCode = 1
} else {
  console.log("ok")
}
