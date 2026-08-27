#!/usr/bin/env node
"use strict"

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const Model = new Function(
  fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8") +
    "\nreturn { recentlyUsed, withoutItems, listRowCursorIndex, listScrollTargetIndex, visiblePreviewWindow, cursorItemCount, cursorItemAt, resolveCursorRow, clearFailedPreviewKeys, applyPreviewBatch }\n"
)()

const panelSource = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
const passServiceSource = fs.readFileSync(path.join(__dirname, "..", "PassService.qml"), "utf8")
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
const readmeSource = fs.readFileSync(path.join(__dirname, "..", "README.md"), "utf8")

function makeItems(count) {
  var out = []
  for (var i = 0; i < count; i++) {
    out.push({
      id: "item-" + i,
      shareId: "share-1",
      title: "Login " + i,
      lastUsedAt: count - i
    })
  }
  return out
}

assert.strictEqual(Model.listRowCursorIndex(true, 2, 5), 5, "search mode uses delegate index")
assert.strictEqual(Model.listRowCursorIndex(false, 2, 5), 7, "browse mode offsets suggested rows")

assert.strictEqual(Model.listScrollTargetIndex(false, 0, 3), -1, "suggested row scrolls to beginning")
assert.strictEqual(Model.listScrollTargetIndex(false, 2, 3), -1, "last suggested row still scrolls to beginning")
assert.strictEqual(Model.listScrollTargetIndex(false, 3, 3), 0, "first recent row maps to delegate 0")
assert.strictEqual(Model.listScrollTargetIndex(false, 8, 3), 5, "recent row maps after suggested offset")
assert.strictEqual(Model.listScrollTargetIndex(true, 4, 3), 4, "search mode maps directly")

var allItems = makeItems(563)
var suggested = allItems.slice(0, 2)
var ranked = Model.recentlyUsed(allItems)
var recent = Model.withoutItems(ranked, suggested)
assert.strictEqual(recent.length, 561, "full login list stays available after suggested removal")
assert.strictEqual(Model.recentlyUsed(allItems).length, 563, "recentlyUsed without limit keeps every login")

var previewList = makeItems(40)
var preview = Model.visiblePreviewWindow(false, suggested, previewList, {
  contentY: 440,
  height: 220,
  rowHeight: 44,
  indexAtTop: 10,
  indexAtBottom: 14
})
assert.strictEqual(preview.length, 7, "preview window includes suggested plus visible recent rows")
assert.strictEqual(preview[0].title, "Login 0")
assert.strictEqual(preview[preview.length - 1].title, "Login 14")
assert.ok(preview.every(function (item) { return item.title.indexOf("Login ") === 0 }))

var emptySearchPreview = Model.visiblePreviewWindow(true, suggested, [], {})
assert.deepStrictEqual(emptySearchPreview, [], "empty search preview window stays empty")

var capped = Model.visiblePreviewWindow(false, [], makeItems(100), {
  contentY: 0,
  height: 100,
  rowHeight: 44,
  indexAtTop: 0,
  indexAtBottom: 50
})
assert.ok(capped.length <= 12, "preview window stays bounded when many rows are visible")

assert.match(panelSource, /reuseItems:\s*true/, "ListView delegate reuse stays enabled")
assert.doesNotMatch(
  panelSource,
  /onHasCursorChanged:.*scrollCursorIntoView/,
  "hover and delegate reuse must not trigger list scroll"
)
assert.match(
  panelSource,
  /function moveCursor[\s\S]*?scrollCursorIntoView\(\)/,
  "keyboard navigation keeps a single centralized scroll call"
)
assert.match(
  panelSource,
  /footer:[\s\S]*visible:\s*root\.searching && root\.filtered\.length === 0/,
  "empty search state keeps a footer message"
)
assert.doesNotMatch(panelSource, /recentlyUsed\([^)]*,\s*maxRecent/, "list must not cap recent rows with maxRecent")
assert.doesNotMatch(panelSource, /recentlyUsed\([^)]*,\s*root\.maxRecent/, "list must not cap recent rows with maxRecent")
assert.ok(!("maxRecent" in manifest.barWidget.defaults), "manifest defaults must not expose maxRecent")
assert.ok(
  !manifest.barWidget.schema.some(function (entry) { return entry.key === "maxRecent" }),
  "manifest schema must not expose maxRecent"
)
assert.strictEqual(
  manifest.barWidget.defaults.clipboardClearSeconds,
  0,
  "clipboard clear stays off by default"
)
var clipboardClearSchema = manifest.barWidget.schema.find(function (entry) { return entry.key === "clipboardClearSeconds" })
assert.ok(clipboardClearSchema, "clipboard clear is a widget setting")
assert.strictEqual(clipboardClearSchema.type, "integer")
assert.strictEqual(clipboardClearSchema.min, 0)
assert.strictEqual(clipboardClearSchema.max, 300)
assert.strictEqual(clipboardClearSchema.defaultValue, 0)
assert.match(
  passServiceSource,
  /clipboardClearDelayMs\(setting\("clipboardClearSeconds",\s*0\)\)/,
  "PassService reads clipboardClearSeconds with a 0 fallback"
)
assert.doesNotMatch(readmeSource, /maxRecent/, "README must not document maxRecent")

assert.match(panelSource, /snapshotAppId|snapshottedAppId|contextAppId/, "panel snapshots active app id on open")
assert.match(panelSource, /snapshotTitle|snapshottedTitle|contextTitle/, "panel snapshots active title on open")
assert.match(
  panelSource,
  /suggestedItems\(pass\.items,\s*(root\.)?(snapshotAppId|snapshottedAppId|contextAppId)/,
  "suggested uses snapped window context, not live focus"
)
assert.match(panelSource, /debounc|filterDebounc|debouncedFilter/, "search filtering is debounced")
assert.match(panelSource, /interval:\s*100/, "search debounce stays near 100ms")
assert.doesNotMatch(
  panelSource,
  /readonly property var filtered:\s*Model\.searchItems\(rankedItems,\s*filterText\)/,
  "filtered must not recompute from live filterText while empty/searching"
)
assert.doesNotMatch(
  panelSource,
  /readonly property var cursorItems:\s*searching\s*\?\s*filtered\s*:\s*combineItems/,
  "keyboard selection must not build a combined suggested+recent array"
)
assert.match(
  panelSource,
  /cursorItemCount|cursorItemAt/,
  "keyboard selection derives count/row from suggested/recent/filtered helpers"
)
assert.match(
  passServiceSource,
  /applyPreviewUpdates|_pendingPreview|previewMerge|flushPendingPreview/,
  "non-urgent preview merges are batched"
)
assert.match(
  passServiceSource,
  /rememberFailedPreviewKey|hasFailedPreviewKey|_failedPreview/,
  "failed preview keys are tracked with backoff"
)
assert.match(
  passServiceSource,
  /isSessionBlockingStatus/,
  "locked/unauthenticated preview errors stop preview work via shared classifier"
)

assert.match(
  panelSource,
  /function commitPendingFilter|commitPendingSearch|syncDebouncedFilter/,
  "pending filterText can be committed synchronously before activation"
)
assert.match(
  panelSource,
  /function currentRow[\s\S]*commitPending|resolveCursorRow/,
  "currentRow commits or resolves from live filterText"
)
assert.match(
  panelSource,
  /Key_Return[\s\S]*commitPending|Key_Enter[\s\S]*commitPending|Key_Return[\s\S]*resolveCursorRow|Key_Enter[\s\S]*resolveCursorRow/,
  "Enter activates from committed/live query, not stale debounce"
)
assert.match(
  panelSource,
  /function activateCursor[\s\S]*currentRow|function activateCursor[\s\S]*resolveCursorRow/,
  "activateCursor uses the same live-query resolution path"
)
assert.match(
  passServiceSource,
  /clearFailedPreviewKeys/,
  "failed preview keys are cleared at recoverable boundaries"
)
assert.match(
  passServiceSource,
  /applyStatus\([\s\S]*clearFailedPreviewKeys|kind === "ready"[\s\S]*clearFailedPreviewKeys/,
  "successful ready status clears failed preview backoff"
)
assert.match(
  passServiceSource,
  /function refresh[\s\S]*force === true[\s\S]*clearFailedPreviewKeys|force !== true[\s\S]*clearFailedPreviewKeys/,
  "forced refresh clears failed preview backoff"
)
assert.match(
  passServiceSource,
  /function stopPreviews[\s\S]*clearFailedPreviewKeys/,
  "panel-session stop clears failed preview backoff"
)
assert.match(
  passServiceSource,
  /applyPreviewBatch/,
  "preview batch flush emits updates from batch result, not N findItem scans"
)
assert.doesNotMatch(
  passServiceSource,
  /flushPendingPreviews[\s\S]*updatedKeys[\s\S]*findItem/,
  "flushPendingPreviews must not rescan findItem per updated key"
)
assert.match(
  passServiceSource,
  /id:\s*cacheWriteTimer[\s\S]*interval:\s*1500/,
  "metadata cache writes debounce near 1500ms"
)
assert.match(
  passServiceSource,
  /_lastCacheText/,
  "identical cache payloads are tracked to skip no-op writes"
)
assert.match(
  passServiceSource,
  /text === _lastCacheText|_lastCacheText === text/,
  "writeCache skips when serialized content is unchanged"
)
assert.match(
  passServiceSource,
  /onLoaded:[\s\S]*_lastCacheText\s*=/,
  "FileView loads seed last-cache text to avoid self-reload rewrite loops"
)
assert.match(
  passServiceSource,
  /atomicWrites:\s*true/,
  "cache FileView keeps atomicWrites enabled"
)
assert.match(
  passServiceSource,
  /parsed\.status === "busy"[\s\S]{0,160}?writeCache\(0\)/,
  "busy fetch clears this instance refreshingAt via writeCache(0)"
)
assert.doesNotMatch(
  passServiceSource,
  /parsed\.status === "busy"[\s\S]{0,200}?lastError\s*=/,
  "busy fetch results must not set an error banner"
)
assert.doesNotMatch(
  passServiceSource,
  /parsed\.status === "busy"[\s\S]{0,200}?applyStatus\(/,
  "busy fetch must preserve existing items/status without applyStatus"
)
assert.match(
  passServiceSource,
  /mkdir",\s*"-p",\s*"-m",\s*"0700"/,
  "cache directory is created owner-only"
)
assert.match(
  passServiceSource,
  /cacheDir:[\s\S]*HOME[\s\S]*\/\.cache\/omarchy/,
  "PassService metadata cache lives under $HOME/.cache/omarchy"
)
assert.doesNotMatch(
  passServiceSource,
  /--show-secrets/,
  "PassService must never request full-list secrets"
)

var suggested = [{ id: "s", shareId: "v", title: "S" }]
var recent = [{ id: "r", shareId: "v", title: "R" }]
var filtered = [{ id: "f", shareId: "v", title: "F" }]
assert.strictEqual(Model.cursorItemCount(false, suggested, recent, filtered), 2)
assert.strictEqual(Model.cursorItemAt(false, suggested, recent, filtered, 1).title, "R")
assert.strictEqual(Model.cursorItemAt(true, suggested, recent, filtered, 0).title, "F")
assert.strictEqual(
  Model.resolveCursorRow("f", suggested, recent, [{ id: "r", shareId: "v", title: "R" }, { id: "f", shareId: "v", title: "F" }], 0).title,
  "F"
)
assert.deepStrictEqual(Model.clearFailedPreviewKeys(), { map: {}, order: [] })
assert.strictEqual(Model.applyPreviewBatch([{ id: "x", shareId: "v", title: "X", username: "" }], { "v/x": { username: "u" } }).updated[0].username, "u")

console.log("ok")
