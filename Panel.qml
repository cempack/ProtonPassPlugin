import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.cempack.proton-pass"
  ipcTarget: "io.github.cempack.proton-pass"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string filterText: ""
  property string viewMode: "list"  // list | detail | create
  property var selectedItem: null
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool passwordVisible: false
  property bool closeAfterCopy: false
  property string draftTitle: ""
  property string draftUsername: ""
  property string draftPassword: ""
  property string draftUrl: ""
  property string draftShareId: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int maxRecent: {
    var n = parseInt(String(setting("maxRecent", 8)), 10)
    if (!isFinite(n) || n < 1) n = 8
    if (n > 30) n = 30
    return n
  }

  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property string activeAppId: toplevel ? String(toplevel.appId || "") : ""
  readonly property string activeTitle: toplevel ? String(toplevel.title || "") : ""

  readonly property var vaultOptions: {
    var vaults = Model.vaultsFromItems(pass.items)
    var out = []
    for (var i = 0; i < vaults.length; i++)
      out.push({ value: vaults[i].shareId, label: vaults[i].name })
    return out
  }
  readonly property bool searching: String(filterText).trim() !== ""
  readonly property var suggested: Model.suggestedItems(pass.items, activeAppId, activeTitle)
  readonly property var recent: Model.withoutItems(Model.recentlyUsed(pass.items), suggested)
  readonly property var filtered: Model.searchItems(Model.recentlyUsed(pass.items), filterText)
  readonly property var cursorItems: searching ? filtered : combineItems(suggested, recent)
  readonly property bool listReady: pass.status === "ready" || pass.items.length > 0
  readonly property bool showList: listReady && viewMode === "list"
  readonly property bool showDetail: viewMode === "detail" && selectedItem !== null
  readonly property bool showCreate: viewMode === "create"
  readonly property bool showLoading: pass.refreshing && pass.items.length === 0 && pass.status !== "missing" && pass.status !== "unauthenticated" && pass.status !== "locked" && pass.status !== "error"
  readonly property bool detailUsernameLoading: {
    if (!showDetail || !selectedItem || !pass.previewing || !pass._previewItem) return false
    if (selectedItem.id !== pass._previewItem.id || selectedItem.shareId !== pass._previewItem.shareId) return false
    return Model.accountLabel(selectedItem) === ""
  }
  readonly property string statusHint: {
    if (pass.status === "missing") return "Install pass-cli, then sign in with pass-cli login."
    if (pass.status === "unauthenticated") return "Run pass-cli login in a terminal."
    if (pass.status === "locked") return "Unlock the session, then reopen this panel."
    if (pass.status === "error") return pass.lastError || "Could not load Proton Pass."
    if (listReady && pass.items.length === 0 && !pass.refreshing) return "No login items in your vaults."
    return ""
  }

  function open() {
    resetSession(false)
    root.controller.show()
    pass.ensureFresh()
  }

  function openFromHotkey() {
    resetSession(false)
    root.controller.show()
    pass.ensureFresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    pass.stopPreviews()
    pass.clearCopied()
    root.controller.hide()
    setCenterHoverRevealSuppressed(false)
    closeAfterCopy = false
    passwordVisible = false
    pass.resetViewed()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    pass.refresh(true)
  }

  function resetSession(keepFilter) {
    viewMode = "list"
    selectedItem = null
    selectedIndex = 0
    cursorActive = false
    passwordVisible = false
    pass.resetViewed()
    resetDraft()
    if (!keepFilter) filterText = ""
  }

  function resetDraft() {
    draftTitle = ""
    draftUsername = ""
    draftPassword = ""
    draftUrl = ""
    draftShareId = ""
  }

  function focusSearch() {
    Qt.callLater(function() {
      if (searchField) searchField.forceActiveFocus()
    })
  }

  function clampSelection() {
    if (cursorItems.length === 0) {
      selectedIndex = 0
      return
    }
    if (selectedIndex >= cursorItems.length) selectedIndex = cursorItems.length - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  function combineItems(left, right) {
    var out = []
    var a = left || []
    var b = right || []
    for (var i = 0; i < a.length; i++) out.push(a[i])
    for (var j = 0; j < b.length; j++) out.push(b[j])
    return out
  }

  function moveCursor(dx, dy) {
    if (viewMode === "detail" || viewMode === "create") return
    if (cursorItems.length === 0) return
    if (searchField && searchField.activeFocus) searchField.focus = false
    if (!cursorActive) {
      cursorActive = true
      return
    }
    selectedIndex = selectedIndex + dy
    clampSelection()
    scrollCursorIntoView()
  }

  function currentRow() {
    if (selectedIndex < 0 || selectedIndex >= cursorItems.length) return null
    return cursorItems[selectedIndex]
  }

  function openDetail(item) {
    if (!item) return
    selectedItem = item
    viewMode = "detail"
    passwordVisible = false
    pass.lastError = ""
    pass.resetViewed()
    pass.previewItem(item)
    pass.touchItem(item)
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function closeDetail() {
    viewMode = "list"
    passwordVisible = false
    pass.clearUrgentPreview()
    pass.resetViewed()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function openCreate() {
    var vaults = Model.vaultsFromItems(pass.items)
    draftTitle = String(filterText).trim()
    draftUsername = ""
    draftPassword = ""
    draftUrl = ""
    draftShareId = vaults.length > 0 ? vaults[0].shareId : ""
    selectedItem = null
    passwordVisible = false
    pass.resetViewed()
    viewMode = "create"
    pass.lastError = ""
    Qt.callLater(function() {
      if (titleField) titleField.text = root.draftTitle
      if (usernameField) usernameField.text = ""
      if (passwordField) passwordField.text = ""
      if (urlField) urlField.text = ""
      if (titleField) titleField.forceActiveFocus()
    })
  }

  function closeCreate() {
    viewMode = "list"
    resetDraft()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function saveCreate() {
    if (pass.creating) return
    var title = String(draftTitle || "").trim()
    if (title === "") return
    pass.createLogin({
      shareId: draftShareId,
      title: title,
      username: draftUsername,
      password: draftPassword,
      generatePassword: String(draftPassword || "").trim() === "",
      url: draftUrl
    })
  }

  function copyPasswordAndClose(item) {
    if (!item) return
    closeAfterCopy = true
    pass.copyField(item, "password")
  }

  function activateCursor() {
    var item = currentRow()
    if (!item) return
    copyPasswordAndClose(item)
  }

  function handleCloseRequest() {
    if (viewMode === "detail") closeDetail()
    else if (viewMode === "create") closeCreate()
    else root.close()
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (!listColumn) return
    var target = null
    for (var i = 0; i < listColumn.children.length; i++) {
      var child = listColumn.children[i]
      if (child && child.cursorIndex === selectedIndex) {
        target = child
        break
      }
    }
    if (target) scrollItemIntoView(target)
  }

  function primaryUrl(item) {
    if (!item || !item.urls || item.urls.length === 0) return ""
    return String(item.urls[0] || "")
  }

  function requestVisiblePreviews() {
    if (!root.opened || !root.showList) return
    pass.requestPreviews(visiblePreviewWindow())
  }

  function visiblePreviewWindow() {
    var list = cursorItems || []
    if (list.length === 0) return []
    var row = Math.max(1, Style.space(44))
    var start = 0
    var count = 10
    if (panelFlick && panelFlick.height > 0) {
      start = Math.floor(panelFlick.contentY / row)
      count = Math.ceil(panelFlick.height / row) + 2
    }
    if (start < 0) start = 0
    if (start > list.length) start = Math.max(0, list.length - 1)
    if (count < 8) count = 8
    if (count > 12) count = 12
    return list.slice(start, start + count)
  }

  function previewHovered(item) {
    if (!root.opened || !item) return
    pass.requestPreviews([item])
  }

  onOpenedChanged: {
    if (opened) {
      resetSession(false)
      if (panelFlick) panelFlick.contentY = 0
      focusSearch()
      pass.previewsEnabled = true
      Qt.callLater(function() { if (root.opened) root.requestVisiblePreviews() })
    } else {
      pass.stopPreviews()
    }
  }

  onCursorItemsChanged: {
    clampSelection()
    if (opened) previewScrollTimer.restart()
  }

  PassService {
    id: pass
    settings: root.settings
  }

  Timer {
    id: previewScrollTimer
    interval: 180
    repeat: false
    onTriggered: root.requestVisiblePreviews()
  }

  Connections {
    target: pass
    function onCopied() {
      if (!root.closeAfterCopy) return
      root.closeAfterCopy = false
      root.close()
    }
    function onCopyFailed(message) {
      root.closeAfterCopy = false
    }
    function onItemUpdated(item) {
      if (!root.selectedItem || !item) return
      if (root.selectedItem.id === item.id && root.selectedItem.shareId === item.shareId)
        root.selectedItem = item
    }
    function onCreated() {
      root.closeCreate()
    }
    function onPasswordGenerated(value) {
      root.draftPassword = String(value || "")
      if (passwordField) passwordField.text = root.draftPassword
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.cappedContentHeight(Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || titleField.activeFocus || usernameField.activeFocus || passwordField.activeFocus || urlField.activeFocus || vaultDropdown.popupOpen
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: {
        if (root.viewMode === "detail" || root.viewMode === "create") return
        if (root.cursorActive) root.activateCursor()
      }
      onCloseRequested: root.handleCloseRequest()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/") {
          if (root.viewMode === "list") root.focusSearch()
        }
        else if (t === "r" || t === "R") root.refresh()
        else if (t === "c" || t === "C") {
          if (root.viewMode === "detail" && root.selectedItem) pass.copyField(root.selectedItem, "password")
        }
      }

      Column {
        id: chrome
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

          Item {
            width: parent.width
            height: headerRow.implicitHeight

            RowLayout {
              id: headerRow
              anchors.left: parent.left
              anchors.right: parent.right
              spacing: Style.space(8)

              PanelActionButton {
                visible: root.showDetail || root.showCreate
                iconText: "󰅁"
                tooltipText: "Back"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.showCreate ? root.closeCreate() : root.closeDetail()
              }

              Text {
                Layout.fillWidth: true
                text: root.showCreate ? "New Password" : (root.showDetail && root.selectedItem ? String(root.selectedItem.title || "Password") : "Passwords")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                visible: pass.copying || pass.viewing || pass.creating || pass.generatingPassword || pass.refreshing
                text: pass.copying ? "Copying…" : (pass.viewing ? "Loading…" : (pass.creating ? "Saving…" : (pass.generatingPassword ? "Generating…" : "Refreshing…")))
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              PanelActionButton {
                visible: root.showCreate
                iconText: "󰄬"
                tooltipText: "Save"
                enabled: String(root.draftTitle).trim() !== "" && !pass.creating
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.saveCreate()
              }

              PanelActionButton {
                visible: root.showList
                iconText: "󰐕"
                tooltipText: "New password"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.openCreate()
              }

              PanelActionButton {
                iconText: "󰖯"
                tooltipText: "Open Proton Pass"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: pass.launchApp()
              }
            }
          }

          TextField {
            id: searchField
            visible: root.viewMode === "list" && pass.status !== "missing" && pass.status !== "unauthenticated" && pass.status !== "locked" && pass.status !== "error"
            width: parent.width
            placeholderText: "Search"
            text: root.filterText
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: {
              root.filterText = text
              root.selectedIndex = 0
              root.cursorActive = true
            }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.filterText !== "") {
                  root.filterText = ""
                  text = ""
                } else {
                  root.close()
                }
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.cursorActive = true
                root.selectedIndex = 0
                focus = false
                if (keyCatcher) keyCatcher.forceActiveFocus()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.cursorItems.length > 0) root.copyPasswordAndClose(root.cursorItems[0])
                event.accepted = true
              }
            }
          }

          Text {
            visible: pass.copiedMessage === "Copied" && root.showList
            width: parent.width
            text: pass.copiedMessage
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: root.showLoading
            width: parent.width
            text: "Loading logins…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body

            SequentialAnimation on opacity {
              running: root.showLoading
              loops: Animation.Infinite
              NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutQuad }
              NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
            }
          }

          Text {
            visible: !root.showDetail && !root.showCreate && root.statusHint !== ""
            width: parent.width
            text: root.statusHint
            color: pass.status === "error" || pass.status === "missing" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }

        Flickable {
          id: panelFlick
          anchors.top: chrome.bottom
          anchors.topMargin: chrome.height > 0 ? Style.space(8) : 0
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          contentWidth: width
          contentHeight: column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          onContentYChanged: previewScrollTimer.restart()

          Column {
            id: column
            width: panelFlick.width
            spacing: Style.space(10)

          Column {
            id: listColumn
            visible: root.showList && root.statusHint === ""
            width: parent.width
            spacing: Style.space(8)

            Column {
              visible: !root.searching && root.suggested.length > 0
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: "SUGGESTED"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: root.suggested
                ItemRow {
                  required property var modelData
                  required property int index
                  property int cursorIndex: index
                  width: listColumn.width
                  item: modelData
                  rowIndex: index
                  hasCursor: root.cursorActive && root.selectedIndex === cursorIndex
                  foreground: root.foreground
                  dim: root.dim
                  fontFamily: root.fontFamily
                  onHovered: {
                    root.cursorActive = true
                    root.selectedIndex = cursorIndex
                    root.previewHovered(modelData)
                  }
                  onActivated: root.openDetail(modelData)
                  onHasCursorChanged: if (hasCursor && root.cursorActive) root.scrollItemIntoView(this)
                }
              }
            }

            Column {
              visible: !root.searching && root.recent.length > 0
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: "MOST RECENT"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: root.recent
                ItemRow {
                  required property var modelData
                  required property int index
                  property int cursorIndex: root.suggested.length + index
                  width: listColumn.width
                  item: modelData
                  rowIndex: index
                  hasCursor: root.cursorActive && root.selectedIndex === cursorIndex
                  foreground: root.foreground
                  dim: root.dim
                  fontFamily: root.fontFamily
                  onHovered: {
                    root.cursorActive = true
                    root.selectedIndex = cursorIndex
                    root.previewHovered(modelData)
                  }
                  onActivated: root.openDetail(modelData)
                  onHasCursorChanged: if (hasCursor && root.cursorActive) root.scrollItemIntoView(this)
                }
              }
            }

            Column {
              visible: root.searching
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.filtered
                ItemRow {
                  required property var modelData
                  required property int index
                  property int cursorIndex: index
                  width: listColumn.width
                  item: modelData
                  rowIndex: index
                  hasCursor: root.cursorActive && root.selectedIndex === cursorIndex
                  foreground: root.foreground
                  dim: root.dim
                  fontFamily: root.fontFamily
                  onHovered: {
                    root.cursorActive = true
                    root.selectedIndex = cursorIndex
                    root.previewHovered(modelData)
                  }
                  onActivated: root.openDetail(modelData)
                  onHasCursorChanged: if (hasCursor && root.cursorActive) root.scrollItemIntoView(this)
                }
              }

              Text {
                visible: root.filtered.length === 0
                width: parent.width
                text: "No matching logins."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Column {
            visible: root.showDetail
            width: parent.width
            spacing: Style.space(8)

            FieldRow {
              label: "Username"
              value: root.detailUsernameLoading ? "Loading…" : (root.selectedItem && Model.accountLabel(root.selectedItem) ? Model.accountLabel(root.selectedItem) : "—")
              onCopyRequested: if (root.selectedItem && Model.accountLabel(root.selectedItem)) pass.copyText(Model.accountLabel(root.selectedItem))
            }

            FieldRow {
              label: "Password"
              value: {
                if (pass.copying && pass.viewedField === "password") return "Copying…"
                if (pass.viewing && pass.viewedField === "password") return "Loading…"
                if (root.passwordVisible && pass.viewedField === "password" && pass.viewedValue !== "")
                  return pass.viewedValue
                return root.maskedSecret()
              }
              onCopyRequested: if (root.selectedItem) pass.copyField(root.selectedItem, "password")
              onRevealRequested: {
                if (root.passwordVisible) {
                  root.passwordVisible = false
                  pass.resetViewed()
                } else if (root.selectedItem) {
                  root.passwordVisible = true
                  pass.viewField(root.selectedItem, "password")
                }
              }
            }

            FieldRow {
              visible: root.selectedItem && root.selectedItem.hasTotp === true
              label: "Code"
              value: {
                if (pass.copying && pass.viewedField === "totp") return "Copying…"
                if (pass.viewing && pass.viewedField === "totp") return "Loading…"
                if (pass.viewedField === "totp" && pass.viewedValue !== "") return pass.viewedValue
                return "Tap to show"
              }
              onCopyRequested: if (root.selectedItem) pass.copyField(root.selectedItem, "totp")
              onRevealRequested: if (root.selectedItem) pass.viewField(root.selectedItem, "totp")
            }

            FieldRow {
              visible: root.primaryUrl(root.selectedItem) !== ""
              label: "Website"
              value: root.primaryUrl(root.selectedItem)
              onCopyRequested: pass.copyText(root.primaryUrl(root.selectedItem))
            }

            Text {
              visible: pass.lastError !== ""
              width: parent.width
              text: pass.lastError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            visible: root.showCreate
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: titleField
              width: parent.width
              placeholderText: "Title"
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: root.draftTitle = text
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.closeCreate()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  usernameField.forceActiveFocus()
                  event.accepted = true
                }
              }
            }

            TextField {
              id: usernameField
              width: parent.width
              placeholderText: "Username"
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: root.draftUsername = text
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.closeCreate()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  passwordField.forceActiveFocus()
                  event.accepted = true
                }
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: passwordField
                Layout.fillWidth: true
                placeholderText: "Password"
                password: true
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: root.draftPassword = text
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.closeCreate()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    urlField.forceActiveFocus()
                    event.accepted = true
                  }
                }
              }

              PanelActionButton {
                iconText: "󰝨"
                tooltipText: "Generate password"
                enabled: !pass.generatingPassword
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: pass.generatePassword()
              }
            }

            TextField {
              id: urlField
              width: parent.width
              placeholderText: "Website"
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: root.draftUrl = text
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.closeCreate()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.saveCreate()
                  event.accepted = true
                }
              }
            }

            Dropdown {
              id: vaultDropdown
              visible: root.vaultOptions.length > 1
              width: parent.width
              label: "Vault"
              value: root.draftShareId
              options: root.vaultOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) { root.draftShareId = value }
            }

            Text {
              visible: String(root.draftPassword).trim() === ""
              width: parent.width
              text: "Leave password empty to generate one on save."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: pass.lastError !== ""
              width: parent.width
              text: pass.lastError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }

  component FieldRow: CursorSurface {
    id: fieldRow
    property string label: ""
    property string value: ""
    property bool revealable: label === "Password" || label === "Code"

    signal copyRequested()
    signal revealRequested()

    width: parent ? parent.width : implicitWidth
    foreground: root.foreground
    implicitHeight: fieldContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: fieldRow.copyRequested()
    }

    RowLayout {
      id: fieldContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          text: fieldRow.label.toUpperCase()
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1
        }

        Text {
          Layout.fillWidth: true
          text: fieldRow.value !== "" ? fieldRow.value : "—"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        visible: fieldRow.revealable
        iconText: fieldRow.label === "Password" && root.passwordVisible ? "󰈉" : "󰈈"
        tooltipText: fieldRow.label === "Password" && root.passwordVisible ? "Hide" : "Show"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: fieldRow.revealRequested()
      }

      PanelActionButton {
        iconText: "󰆏"
        tooltipText: "Copy"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: fieldRow.copyRequested()
      }
    }
  }
}
