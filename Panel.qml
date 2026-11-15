import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Panel controller: navigation state, the derived list model, actions and the
// keyboard map. Pages (ListPage, DetailPage, GeneratorPage, CreatePage,
// StatusPage) render this state and call back into it.
Panel {
  id: root
  moduleName: "io.github.cempack.proton-pass"
  ipcTarget: "io.github.cempack.proton-pass"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ── Theme ───────────────────────────────────────────────────────────────────
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ── Navigation ──────────────────────────────────────────────────────────────
  property string page: "list"  // list | detail | generator | create
  property string query: ""
  property string debouncedQuery: ""
  property string filter: "all"
  property string vault: ""
  property int cursor: 0
  property var selectedItem: null
  property bool closeAfterCopy: true
  property string snapshotAppId: ""
  property string snapshotTitle: ""
  property string createPassword: ""

  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property bool blocked: pass.needsSignIn || pass.status === "missing"
    || (pass.items.length === 0 && (pass.status === "error" || pass.status === "loading" || pass.status === "idle"))

  // ── Derived list ────────────────────────────────────────────────────────────
  readonly property var vaults: Model.vaultsFromItems(pass.items)
  readonly property var chips: Model.filterChips(pass.items, vault)
  readonly property var scoped: Model.filterItems(pass.items, filter, vault)
  readonly property var ranked: Model.recentlyUsed(scoped)
  readonly property bool searching: debouncedQuery.trim() !== ""
  readonly property var suggested: searching || filter !== "all"
    ? [] : Model.suggestedItems(scoped, snapshotAppId, snapshotTitle, 4)
  readonly property var listModel: searching
    ? Model.buildListRows([{ title: "", items: Model.searchItems(ranked, debouncedQuery) }])
    : Model.buildListRows([
        { title: "Suggested", items: suggested },
        { title: filter === "all" ? "Recent" : Model.filterLabel(filter), items: ranked }
      ])
  readonly property int itemCount: listModel.items.length
  readonly property var cursorItem: {
    if (itemCount === 0) return null
    var row = listModel.rows[listModel.items[Math.max(0, Math.min(cursor, itemCount - 1))]]
    return row ? row.item : null
  }

  // ── Opening & closing ───────────────────────────────────────────────────────

  function open() {
    snapshotActiveContext()
    resetList(true)
    root.controller.show()
    pass.ensureFresh()
  }

  function openFromHotkey() {
    open()
    Qt.callLater(function() { if (root.opened) root.setHoverRevealSuppressed(true) })
  }

  function close() {
    root.controller.hide()
    setHoverRevealSuppressed(false)
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  function refresh() {
    pass.refresh(true)
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  function snapshotActiveContext() {
    snapshotAppId = toplevel ? String(toplevel.appId || "") : ""
    snapshotTitle = toplevel ? String(toplevel.title || "") : ""
  }

  function resetList(clearQuery) {
    page = "list"
    selectedItem = null
    cursor = 0
    pass.closeInspector()
    if (clearQuery) {
      searchDebounce.stop()
      query = ""
      debouncedQuery = ""
      filter = "all"
    }
    if (listPage) listPage.resetScroll()
  }

  onOpenedChanged: {
    if (opened) {
      focusPage()
    } else {
      pass.stopLiveTotp()
      pass.closeInspector()
      pass.clearNotice()
      resetList(true)
      createPassword = ""
      pass.generated = ""
      createPage.prepare("", "", "")
    }
  }

  // ── List navigation ─────────────────────────────────────────────────────────

  function setQuery(value) {
    query = String(value || "")
    cursor = 0
    if (query.trim() === "") {
      searchDebounce.stop()
      debouncedQuery = ""
    } else {
      searchDebounce.restart()
    }
  }

  function commitQuery() {
    searchDebounce.stop()
    debouncedQuery = query
  }

  function setFilter(key) {
    filter = String(key || "all")
    cursor = 0
    if (listPage) listPage.resetScroll()
  }

  function cycleFilter(step) {
    setFilter(Model.nextFilter(chips, filter, step))
  }

  function setVault(shareId) {
    vault = String(shareId || "")
    if (!Model.filterChips(pass.items, vault).some(function(c) { return c.key === filter })) filter = "all"
    cursor = 0
  }

  function moveCursor(step) {
    if (itemCount === 0) return
    cursor = Math.max(0, Math.min(itemCount - 1, cursor + step))
    if (listPage) listPage.revealCursor()
  }

  function pointAt(item) {
    for (var i = 0; i < itemCount; i++) {
      var row = listModel.rows[listModel.items[i]]
      if (row && row.item === item) {
        cursor = i
        return
      }
    }
  }

  onListModelChanged: {
    if (cursor >= itemCount) cursor = Math.max(0, itemCount - 1)
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  // Enter: copy the password for logins, open everything else.
  function activate(item) {
    var target = item || cursorItem
    if (!target) return
    if (Model.primaryCopyField(target)) copy(target, "password")
    else openDetail(target)
  }

  function copy(item, field) {
    if (!item) return
    if (field === "username") {
      var value = String(item.username || item.email || "")
      if (value === "") return pass.notify("No username on this item", "error")
      pass.touchItem(item)
      pass.copyText(value, item.username ? "Username" : "Email")
      return
    }
    pass.copyField(item, field, Model.fieldLabel(field))
  }

  function copyCode(item) {
    var target = item || cursorItem
    if (!target) return
    if (target.hasTotp !== true) return pass.notify("No 2FA on this item", "error")
    if (!pass.copyLiveCode(target)) pass.notify("2FA code is still loading", "info")
  }

  function openWebsite(item) {
    var target = item || cursorItem
    var url = Model.primaryUrl(target)
    if (url === "") return pass.notify("No website on this item", "error")
    pass.touchItem(target)
    pass.openUrl(url)
    close()
  }

  function openDetail(item) {
    var target = item || cursorItem
    if (!target) return
    selectedItem = target
    page = "detail"
    pass.touchItem(target)
    pass.inspect(target)
    focusPage()
  }

  function openGenerator() {
    page = "generator"
    if (pass.generated === "") generatorPage.regenerate()
    focusPage()
  }

  function openCreate(password) {
    createPassword = String(password || "")
    page = "create"
    createPage.prepare(query.trim(), createPassword, vault || (vaults.length > 0 ? vaults[0].shareId : ""))
    focusPage()
  }

  function back() {
    if (page === "list") {
      if (query !== "") {
        setQuery("")
        listPage.clearSearch()
      } else {
        close()
      }
      return
    }
    if (page === "create" && createPassword !== "") {
      page = "generator"
    } else {
      pass.closeInspector()
      selectedItem = null
      page = "list"
    }
    focusPage()
  }

  function focusPage() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.blocked) statusPage.forceActiveFocus()
      else if (root.page === "list") listPage.focusSearch()
      else if (root.page === "detail") detailPage.forceActiveFocus()
      else if (root.page === "generator") generatorPage.forceActiveFocus()
      else createPage.focusFirst()
    })
  }

  onBlockedChanged: focusPage()

  // Shared shortcuts for every page except text entry in the create form.
  function handleGlobalKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
      return true
    }
    if (!ctrl) return false
    if (event.key === Qt.Key_R) { refresh(); return true }
    if (blocked) return false
    if (event.key === Qt.Key_G) { openGenerator(); return true }
    if (event.key === Qt.Key_N) { openCreate(""); return true }
    return false
  }

  Connections {
    target: pass
    function onCopied(label) {
      if (root.closeAfterCopy && root.page === "list") root.close()
    }
    function onCreated() {
      root.createPassword = ""
      root.resetList(true)
      root.focusPage()
    }
    function onItemUpdated(item) {
      if (root.selectedItem && item && root.selectedItem.id === item.id && root.selectedItem.shareId === item.shareId)
        root.selectedItem = item
    }
  }

  PassService {
    id: pass
    settings: root.settings
  }

  // Live codes start once a 2FA row is on screen and run until the panel closes.
  readonly property bool wantsLiveTotp: root.opened && root.page === "list" && !root.blocked && listPage.showsTotp
  onWantsLiveTotpChanged: if (wantsLiveTotp) pass.startLiveTotp()

  Timer {
    id: searchDebounce
    interval: 90
    onTriggered: {
      root.debouncedQuery = root.query
      root.cursor = 0
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: listPage
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.cappedContentHeight(Style.space(580))

    Item {
      anchors.fill: parent

      Header {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        panel: root
        pass: pass
      }

      Item {
        id: body
        anchors.top: header.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(6)

        StatusPage {
          id: statusPage
          anchors.fill: parent
          visible: root.blocked
          panel: root
          pass: pass
        }

        ListPage {
          id: listPage
          anchors.fill: parent
          visible: !root.blocked && root.page === "list"
          panel: root
          pass: pass
        }

        DetailPage {
          id: detailPage
          anchors.fill: parent
          visible: !root.blocked && root.page === "detail"
          panel: root
          pass: pass
        }

        GeneratorPage {
          id: generatorPage
          anchors.fill: parent
          visible: !root.blocked && root.page === "generator"
          panel: root
          pass: pass
        }

        CreatePage {
          id: createPage
          anchors.fill: parent
          visible: !root.blocked && root.page === "create"
          panel: root
          pass: pass
        }
      }

      HintBar {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        panel: root
        pass: pass
      }
    }
  }
}
