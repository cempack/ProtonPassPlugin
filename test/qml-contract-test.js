#!/usr/bin/env node
"use strict"

const assert = require("assert")
const fs = require("fs")
const path = require("path")

const ROOT = path.join(__dirname, "..")

const INHERITED_METHODS = {
  Panel: new Set([
    "setting",
    "closeForPopoutSwitch"
  ]),
  BarWidget: new Set([
    "broadcast"
  ]),
  CursorSurface: new Set([]),
  Item: new Set([]),
  PassService: new Set([])
}

function stripComments(source) {
  return source
    .replace(/\/\/[^\n]*/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
}

function extractBaseType(source) {
  var cleaned = stripComments(source).replace(/^[\s\S]*?(?=^[A-Za-z_][A-Za-z0-9_.]*\s*\{)/m, "")
  var match = cleaned.match(/^([A-Za-z_][A-Za-z0-9_.]*)\s*\{/)
  return match ? match[1] : ""
}

function extractRootId(source) {
  var match = source.match(/^\s*id:\s*([A-Za-z_][A-Za-z0-9_]*)\s*$/m)
  return match ? match[1] : "root"
}

function extractRootDeclarations(source) {
  var functions = new Set()
  var properties = new Set()
  var signals = new Set()
  var lines = source.split("\n")

  for (var i = 0; i < lines.length; i++) {
    var line = stripComments(lines[i])
    if (/^\s{2}function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/.test(line)) {
      functions.add(line.match(/function\s+([A-Za-z_][A-Za-z0-9_]*)/)[1])
      continue
    }
    if (/^\s{2}signal\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/.test(line)) {
      signals.add(line.match(/signal\s+([A-Za-z_][A-Za-z0-9_]*)/)[1])
      continue
    }
    var propertyMatch = line.match(/^\s{2}(?:readonly\s+)?property\s+[A-Za-z_<>,\s]+\s+([A-Za-z_][A-Za-z0-9_]*)\b/)
    if (propertyMatch) properties.add(propertyMatch[1])
  }

  return { functions: functions, properties: properties, signals: signals }
}

function analyzeRootCalls(filePath, source) {
  var baseType = extractBaseType(source)
  var rootId = extractRootId(source)
  var decl = extractRootDeclarations(source)
  var inherited = INHERITED_METHODS[baseType] || new Set()
  var callable = new Set([].concat(
    Array.from(decl.functions),
    Array.from(decl.signals),
    Array.from(inherited)
  ))
  var violations = []
  var cleaned = stripComments(source)
  var pattern = new RegExp("\\b" + rootId + "\\.([A-Za-z_][A-Za-z0-9_]*)\\s*\\(", "g")
  var match

  while ((match = pattern.exec(cleaned)) !== null) {
    var name = match[1]
    if (decl.properties.has(name)) {
      violations.push(filePath + ": " + rootId + "." + name + "() calls a property as a function")
      continue
    }
    if (!callable.has(name)) {
      violations.push(filePath + ": undeclared " + rootId + "." + name + "() call")
    }
  }

  return violations
}

function analyzeRepository(rootDir) {
  var files = fs.readdirSync(rootDir).filter(function (name) { return name.endsWith(".qml") })
  var violations = []
  for (var i = 0; i < files.length; i++) {
    var filePath = path.join(rootDir, files[i])
    violations = violations.concat(analyzeRootCalls(filePath, fs.readFileSync(filePath, "utf8")))
  }
  return violations
}

assert.deepStrictEqual(
  analyzeRootCalls("fixture.qml", [
    "Panel {",
    "  id: root",
    "  readonly property string maskedSecret: \"••••\"",
    "  function scrollCursorIntoView() {}",
    "  Text { value: root.maskedSecret() }",
    "}"
  ].join("\n")),
  ["fixture.qml: root.maskedSecret() calls a property as a function"]
)

assert.deepStrictEqual(
  analyzeRootCalls("fixture.qml", [
    "ItemRow {",
    "  id: root",
    "  signal hovered()",
    "  MouseArea { onEntered: root.hovered() }",
    "}"
  ].join("\n")),
  []
)

assert.deepStrictEqual(
  analyzeRootCalls("fixture.qml", [
    "Panel {",
    "  id: root",
    "  function open() {}",
    "  Text { onClicked: root.missingHelper() }",
    "}"
  ].join("\n")),
  ["fixture.qml: undeclared root.missingHelper() call"]
)

assert.deepStrictEqual(
  analyzeRootCalls("fixture.qml", [
    "BarWidget {",
    "  id: root",
    "  IpcHandler { function refresh(): void { root.broadcast(\"refresh\") } }",
    "}"
  ].join("\n")),
  []
)

var repoViolations = analyzeRepository(ROOT)
assert.deepStrictEqual(repoViolations, [], repoViolations.join("\n"))

console.log("ok")
