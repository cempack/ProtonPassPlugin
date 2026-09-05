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
  property string debouncedFilter: ""
  property string snapshotAppId: ""
  property string snapshotTitle: ""
  property string viewMode: "list"  // list | detail | create
  property var selectedItem: null
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool passwordVisible: false
  property var revealedFields: ({})
  property bool closeAfterCopy: false
  property string draftTitle: ""
  property string draftUsername: ""
  property string draftPassword: ""
  property string draftUrl: ""
  property string draftShareId: ""
  property bool createSubmitAttempted: false
  property real listScrollY: 0
  property bool restoringListScroll: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
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
  readonly property var emptyItems: []
  readonly property int suggestedLimit: 6
  readonly property bool searching: String(debouncedFilter).trim() !== ""
  readonly property var suggested: Model.suggestedItems(pass.items, snapshotAppId, snapshotTitle, suggestedLimit)
  readonly property var rankedItems: Model.recentlyUsed(pass.items)
  readonly property var recent: Model.withoutItems(rankedItems, suggested)
  readonly property var filtered: searching ? Model.searchItems(rankedItems, debouncedFilter) : emptyItems
  readonly property int cursorCount: Model.cursorItemCount(searching, suggested, recent, filtered)
  readonly property bool listReady: pass.status === "ready" || pass.items.length > 0
  readonly property bool showList: listReady && viewMode === "list"
  readonly property bool showDetail: viewMode === "detail" && selectedItem !== null
  readonly property bool showCreate: viewMode === "create"
  readonly property bool showLoading: pass.refreshing && pass.items.length === 0 && pass.status !== "missing" && pass.status !== "unauthenticated" && pass.status !== "locked" && pass.status !== "migration-required" && pass.status !== "error"
  readonly property string statusHint: {
    if (pass.status === "missing") return "Install pass-cli, then sign in with pass-cli login."
    if (pass.status === "unauthenticated") return "Run pass-cli login in a terminal."
    if (pass.status === "locked") return "Unlock the session, then reopen this panel."
    if (pass.status === "migration-required") return "Run pass-cli login in a terminal, then right-click the bar icon to refresh."
    if (pass.status === "error") return pass.lastError || "Could not load Proton Pass."
    if (listReady && pass.items.length === 0 && pass.fetchWarning !== "") return pass.fetchWarning
    if (listReady && pass.items.length === 0 && pass.lastError !== "") return pass.lastError
    if (listReady && pass.items.length === 0 && !pass.refreshing) return "No items in your vaults."
    return ""
  }

  function open() {
    snapshotActiveContext()
    resetSession(false)
    root.controller.show()
    pass.ensureFresh()
  }

  function openFromHotkey() {
    snapshotActiveContext()
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
    resetDraft()
    root.controller.hide()
    setCenterHoverRevealSuppressed(false)
    closeAfterCopy = false
    passwordVisible = false
    revealedFields = ({})
    pass.resetViewed()
    pass.resetInspector()
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

  function snapshotActiveContext() {
    snapshotAppId = activeAppId
    snapshotTitle = activeTitle
  }

  function setFilterText(value) {
    filterText = String(value || "")
    selectedIndex = 0
    cursorActive = true
    if (String(filterText).trim() === "") {
      searchDebounceTimer.stop()
      listScrollY = 0
      debouncedFilter = ""
      return
    }
    searchDebounceTimer.restart()
  }

  function commitPendingFilter() {
    searchDebounceTimer.stop()
    if (debouncedFilter !== filterText) {
      listScrollY = 0
      debouncedFilter = filterText
    }
  }

  function resetSession(keepFilter) {
    viewMode = "list"
    selectedItem = null
    selectedIndex = 0
    cursorActive = false
    passwordVisible = false
    revealedFields = ({})
    pass.resetViewed()
    pass.resetInspector()
    resetDraft()
    if (!keepFilter) {
      searchDebounceTimer.stop()
      filterText = ""
      debouncedFilter = ""
      listScrollY = 0
    }
  }

  function resetDraft() {
    draftTitle = ""
    draftUsername = ""
    draftPassword = ""
    draftUrl = ""
    draftShareId = ""
    createSubmitAttempted = false
    if (titleField) titleField.text = ""
    if (usernameField) usernameField.text = ""
    if (passwordField) passwordField.text = ""
    if (urlField) urlField.text = ""
  }

  function focusSearch() {
    Qt.callLater(function() {
      if (searchField) searchField.forceActiveFocus()
    })
  }

  function clampSelection() {
    if (cursorCount === 0) {
      selectedIndex = 0
      return
    }
    if (selectedIndex >= cursorCount) selectedIndex = cursorCount - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  function moveCursor(dx, dy) {
    if (viewMode === "detail" || viewMode === "create") return
    if (cursorCount === 0) return
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
    commitPendingFilter()
    return Model.resolveCursorRow(filterText, suggested, recent, rankedItems, selectedIndex)
  }

  function activateCursor() {
    var item = currentRow()
    if (!item) return
    if (Model.primaryCopyField(item)) copyPasswordAndClose(item)
    else openDetail(item)
  }

  function isFieldRevealed(id) {
    return revealedFields && revealedFields[id] === true
  }

  function toggleFieldReveal(id) {
    var next = {}
    var current = revealedFields || {}
    var keys = Object.keys(current)
    for (var i = 0; i < keys.length; i++) next[keys[i]] = current[keys[i]]
    next[id] = next[id] !== true
    revealedFields = next
  }

  function inspectorFieldValue(field) {
    if (!field) return ""
    var kind = String(field.kind || "text")
    if (kind === "totp") {
      var codes = pass.totpCodes || {}
      var name = String(field.field || "totp")
      var code = String(codes[name] || codes.totp || "")
      if (code === "") return pass.totpLoading ? "Loading…" : "••••••"
      return code + "  " + String(pass.totpRemaining) + "s"
    }
    if (kind === "secret" && !isFieldRevealed(field.id)) return root.maskedSecret
    return String(field.value || "")
  }

  function copyInspectorField(field) {
    if (!field || !root.selectedItem) return
    var name = String(field.field || "")
    if (name !== "") pass.copyField(root.selectedItem, name)
    else if (String(field.value || "") !== "") pass.copyText(field.value)
  }

  function openDetail(item) {
    if (!item) return
    selectedItem = item
    viewMode = "detail"
    passwordVisible = false
    revealedFields = ({})
    pass.lastError = ""
    pass.resetViewed()
    pass.inspectItem(item)
    pass.touchItem(item)
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function closeDetail() {
    viewMode = "list"
    passwordVisible = false
    revealedFields = ({})
    pass.clearUrgentPreview()
    pass.resetViewed()
    pass.resetInspector()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function openCreate() {
    var vaults = Model.vaultsFromItems(pass.items)
    draftTitle = String(filterText).trim()
    draftUsername = ""
    draftPassword = ""
    draftUrl = ""
    draftShareId = vaults.length > 0 ? vaults[0].shareId : ""
    createSubmitAttempted = false
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
    if (pass.creating || pass.generatingPassword) return
    createSubmitAttempted = true
    var title = String(draftTitle || "").trim()
    if (title === "") return
    pass.createLogin({
      shareId: draftShareId,
      title: title,
      username: draftUsername,
      password: draftPassword,
      generatePassword: draftPassword === "",
      url: draftUrl
    })
  }

  function copyPasswordAndClose(item) {
    if (!item) return
    closeAfterCopy = true
    pass.copyField(item, "password")
  }

  function handleCloseRequest() {
    if (viewMode === "detail") closeDetail()
    else if (viewMode === "create") closeCreate()
    else root.close()
  }

  function scrollItemIntoView(item) {
    root.scrollCursorIntoView()
  }

  function scrollCursorIntoView() {
    if (!listView) return
    var target = Model.listScrollTargetIndex(root.searching, selectedIndex, root.suggested.length)
    if (target < 0) listView.positionViewAtBeginning()
    else listView.positionViewAtIndex(target, ListView.Contain)
    Qt.callLater(function() { root.captureListScroll(true) })
  }

  function captureListScroll(force) {
    if (root.restoringListScroll || !listView) return
    var y = listView.contentY
    var jumpedToTop = !force && y <= 0 && root.listScrollY > 1 && !listView.moving && !listView.dragging && !listView.flicking
    if (jumpedToTop) return
    root.listScrollY = y
  }

  function restoreListScroll() {
    if (!listView || !root.opened) return
    root.restoringListScroll = true
    Qt.callLater(function() {
      if (!listView) {
        root.restoringListScroll = false
        return
      }
      listView.contentY = Model.clampListScrollY(root.listScrollY, listView.contentHeight, listView.height)
      Qt.callLater(function() {
        if (listView)
          listView.contentY = Model.clampListScrollY(root.listScrollY, listView.contentHeight, listView.height)
        root.restoringListScroll = false
      })
    })
  }

  readonly property string maskedSecret: "••••••••"

  function requestVisiblePreviews() {
    if (!root.opened || !root.showList) return
    pass.requestPreviews(visiblePreviewWindow())
  }

  function visiblePreviewWindow() {
    var list = root.searching ? (root.filtered || []) : (root.recent || [])
    var viewport = {}
    if (listView && listView.height > 0) {
      viewport.contentY = listView.contentY
      viewport.height = listView.height
      viewport.rowHeight = Style.space(44)
      viewport.indexAtTop = listView.indexAt(1, listView.contentY + 1)
      viewport.indexAtBottom = listView.indexAt(1, listView.contentY + listView.height - 1)
    }
    return Model.visiblePreviewWindow(root.searching, root.suggested, list, viewport)
  }

  function previewHovered(item) {
    if (!root.opened || !item) return
    pass.requestPreviews([item])
  }

  onOpenedChanged: {
    if (opened) {
      snapshotActiveContext()
      listScrollY = 0
      if (listView) listView.positionViewAtBeginning()
      focusSearch()
      Qt.callLater(function() {
        if (!root.opened) return
        pass.previewsEnabled = true
        root.requestVisiblePreviews()
      })
    } else {
      pass.stopPreviews()
      root.resetDraft()
    }
  }

  onCursorCountChanged: {
    clampSelection()
    if (opened) previewScrollTimer.restart()
  }

  onSuggestedChanged: {
    clampSelection()
    if (opened) previewScrollTimer.restart()
  }

  onRecentChanged: {
    clampSelection()
    restoreListScroll()
    if (opened) previewScrollTimer.restart()
  }

  onFilteredChanged: {
    clampSelection()
    restoreListScroll()
    if (opened) previewScrollTimer.restart()
  }

  PassService {
    id: pass
    settings: root.settings
  }

  Timer {
    id: searchDebounceTimer
    interval: 100
    repeat: false
    onTriggered: {
      root.listScrollY = 0
      root.debouncedFilter = root.filterText
    }
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
      if (!root.opened || !root.showCreate || pass.creating) return
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
      blocked: searchField.activeFocus || titleField.activeFocus || usernameField.activeFocus || passwordField.activeFocus || urlField.activeFocus || vaultDropdown.popupOpen || statusText.activeFocus || (root.showCreate && !keyCatcher.activeFocus)
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
          if (root.viewMode === "detail" && root.selectedItem) {
            var field = Model.primaryCopyField(root.selectedItem)
            if (field) pass.copyField(root.selectedItem, field)
          }
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
                enabled: !pass.generatingPassword
                iconText: "󰅁"
                tooltipText: "Back"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.showCreate ? root.closeCreate() : root.closeDetail()
              }

              Text {
                Layout.fillWidth: true
                text: root.showCreate ? "Create Login" : (root.showDetail && root.selectedItem ? String(root.selectedItem.title || "Item") : "Proton Pass")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                visible: pass.copying || pass.viewing || pass.creating || pass.generatingPassword || pass.refreshing || pass.inspecting
                text: pass.copying ? "Copying…" : (pass.inspecting ? "Loading…" : (pass.viewing ? "Loading…" : (pass.creating ? "Saving…" : (pass.generatingPassword ? "Generating…" : "Refreshing…"))))
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
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
            visible: root.viewMode === "list" && pass.status !== "missing" && pass.status !== "unauthenticated" && pass.status !== "locked" && pass.status !== "migration-required" && pass.status !== "error"
            width: parent.width
            placeholderText: "Search"
            text: root.filterText
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: root.setFilterText(text)
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.filterText !== "") {
                  root.setFilterText("")
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
                root.commitPendingFilter()
                var first = Model.resolveCursorRow(root.filterText, root.suggested, root.recent, root.rankedItems, 0)
                if (first) {
                  if (Model.primaryCopyField(first)) root.copyPasswordAndClose(first)
                  else root.openDetail(first)
                }
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
            visible: root.showList && root.statusHint === "" && pass.fetchWarning !== ""
            width: parent.width
            text: pass.fetchWarning
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.showList && root.statusHint === "" && pass.lastError !== ""
            width: parent.width
            text: pass.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.showLoading
            width: parent.width
            text: "Loading items…"
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

          TextEdit {
            id: statusText
            visible: !root.showDetail && !root.showCreate && root.statusHint !== ""
            width: parent.width
            text: root.statusHint
            color: pass.status === "error" || pass.status === "missing" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            readOnly: true
            selectByMouse: true
            selectByKeyboard: true
            activeFocusOnTab: pass.status === "migration-required"
            Keys.onEscapePressed: function(event) {
              root.handleCloseRequest()
              event.accepted = true
            }
          }
        }

        Item {
          id: body
          anchors.top: chrome.bottom
          anchors.topMargin: chrome.height > 0 ? Style.space(8) : 0
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          ListView {
            id: listView
            opacity: root.showList && root.statusHint === "" ? 1 : 0
            enabled: root.showList && root.statusHint === ""
            interactive: enabled
            z: 0
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            cacheBuffer: Style.space(160)
            model: root.searching ? root.filtered : root.recent
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            onContentYChanged: {
              previewScrollTimer.restart()
              root.captureListScroll(false)
            }
            onMovementEnded: root.captureListScroll(true)
            onFlickEnded: root.captureListScroll(true)

            header: Column {
              width: listView.width
              spacing: Style.space(8)
              visible: !root.searching
              height: visible ? implicitHeight : 0

              Column {
                visible: root.suggested.length > 0
                width: parent.width
                spacing: Style.space(4)

                PanelSectionHeader {
                  text: "SUGGESTED"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Repeater {
                  model: root.suggested
                  LoginRow {
                    required property var modelData
                    required property int index
                    width: listView.width
                    item: modelData
                    cursorIndex: index
                  }
                }
              }

              PanelSectionHeader {
                visible: root.recent.length > 0
                text: "MOST RECENT"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
            }

            delegate: LoginRow {
              required property var modelData
              required property int index
              width: listView.width
              item: modelData
              cursorIndex: Model.listRowCursorIndex(root.searching, root.suggested.length, index)
            }

            footer: Text {
              visible: root.searching && root.filtered.length === 0
              width: listView.width
              text: "No matching items."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Flickable {
            id: inspectorFlick
            visible: root.showDetail
            z: 1
            anchors.fill: parent
            contentWidth: width
            contentHeight: inspectorColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: inspectorColumn
              width: inspectorFlick.width
              spacing: Style.space(8)

              Text {
                visible: pass.inspecting && !pass.inspector
                width: parent.width
                text: "Loading…"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                visible: !!pass.inspector
                width: parent.width
                text: pass.inspector ? Model.itemTypeLabel(pass.inspector.itemType) : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }

              Repeater {
                model: pass.inspector && pass.inspector.sections ? pass.inspector.sections : []

                Column {
                  required property var modelData
                  width: inspectorColumn.width
                  spacing: Style.space(4)

                  PanelSectionHeader {
                    width: parent.width
                    text: String(modelData.title || "").toUpperCase()
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Repeater {
                    model: modelData.fields || []

                    InspectorField {
                      required property var modelData
                      width: inspectorColumn.width
                      field: modelData
                    }
                  }
                }
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

          Flickable {
            id: createFlick
            visible: root.showCreate
            z: 1
            anchors.fill: parent
            contentWidth: width
            contentHeight: createForm.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: createForm
              width: createFlick.width
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: "Save a new account to Proton Pass."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              PanelSectionHeader {
                width: parent.width
                text: "ACCOUNT DETAILS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Row {
                width: parent.width

                Text {
                  text: "Title"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  text: "  Required"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              TextField {
                id: titleField
                width: parent.width
                placeholderText: "e.g. GitHub"
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

              Text {
                visible: root.createSubmitAttempted && String(root.draftTitle).trim() === ""
                width: parent.width
                text: "Title is required."
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                width: parent.width
                text: "Username"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              TextField {
                id: usernameField
                width: parent.width
                placeholderText: "Email or username"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: root.draftUsername = text
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

              Text {
                width: parent.width
                text: "Website"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              TextField {
                id: urlField
                width: parent.width
                placeholderText: "https://example.com"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: root.draftUrl = text
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

              Text {
                width: parent.width
                text: "Vault"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Dropdown {
                id: vaultDropdown
                visible: root.vaultOptions.length > 0
                width: parent.width
                label: ""
                value: root.draftShareId
                options: root.vaultOptions
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChanged: function(value) { root.draftShareId = value }
                Keys.onPressed: function(event) {
                  if (event.key !== Qt.Key_Escape) return
                  if (vaultDropdown.popupOpen) vaultDropdown.close()
                  else root.closeCreate()
                  event.accepted = true
                }
              }

              Text {
                visible: root.vaultOptions.length === 0
                width: parent.width
                text: "The default Proton Pass vault will be used."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              PanelSeparator {
                width: parent.width
                foreground: root.foreground
              }

              PanelSectionHeader {
                width: parent.width
                text: "SECURITY"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                width: parent.width
                text: "Password"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: passwordField
                  Layout.fillWidth: true
                  placeholderText: "Leave blank to generate"
                  password: true
                  foreground: root.foreground
                  font.family: root.fontFamily
                  onTextChanged: root.draftPassword = text
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

                Button {
                  id: generateButton
                  text: pass.generatingPassword ? "Generating…" : "Generate"
                  iconText: "󰝨"
                  enabled: !pass.generatingPassword && !pass.creating
                  bordered: true
                  focusable: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: pass.generatePassword()
                  Keys.onEscapePressed: function(event) {
                    root.closeCreate()
                    event.accepted = true
                  }
                }
              }

              Text {
                visible: root.draftPassword === ""
                width: parent.width
                text: "Leave this blank and Proton Pass will generate a password when you create the login."
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

              Button {
                id: createButton
                width: parent.width
                text: pass.creating ? "Creating…" : "Create Login"
                iconText: pass.creating ? "󰑮" : "󰄬"
                iconSpinning: pass.creating
                enabled: !pass.creating && !pass.generatingPassword
                selected: true
                bordered: true
                focusable: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                verticalPadding: Style.space(10)
                onClicked: root.saveCreate()
                Keys.onEscapePressed: function(event) {
                  root.closeCreate()
                  event.accepted = true
                }
              }
            }
          }
        }
      }
    }

  component LoginRow: ItemRow {
    property int cursorIndex: 0
    hasCursor: root.cursorActive && root.selectedIndex === cursorIndex
    foreground: root.foreground
    dim: root.dim
    fontFamily: root.fontFamily
    onHovered: {
      root.cursorActive = true
      root.selectedIndex = cursorIndex
      root.previewHovered(item)
    }
    onActivated: root.openDetail(item)
  }

  component InspectorField: CursorSurface {
    id: inspectorField
    property var field: ({})

    readonly property string kind: field && field.kind ? String(field.kind) : "text"
    readonly property bool revealable: kind === "secret"
    readonly property bool wrapValue: kind === "note" || kind === "secret"
    readonly property string label: field && field.label ? String(field.label) : ""
    readonly property string displayValue: root.inspectorFieldValue(field)

    width: parent ? parent.width : implicitWidth
    foreground: root.foreground
    implicitHeight: fieldContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.copyInspectorField(inspectorField.field)
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
          text: inspectorField.label.toUpperCase()
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1
        }

        Text {
          Layout.fillWidth: true
          text: inspectorField.displayValue !== "" ? inspectorField.displayValue : "—"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: inspectorField.wrapValue ? Text.WrapAnywhere : Text.NoWrap
          elide: inspectorField.wrapValue ? Text.ElideNone : Text.ElideRight
        }
      }

      PanelActionButton {
        visible: inspectorField.revealable
        iconText: root.isFieldRevealed(inspectorField.field && inspectorField.field.id) ? "󰈉" : "󰈈"
        tooltipText: root.isFieldRevealed(inspectorField.field && inspectorField.field.id) ? "Hide" : "Show"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.toggleFieldReveal(inspectorField.field && inspectorField.field.id)
      }

      PanelActionButton {
        visible: String(inspectorField.field && inspectorField.field.field || inspectorField.field && inspectorField.field.value || "") !== ""
        iconText: "󰆏"
        tooltipText: "Copy"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.copyInspectorField(inspectorField.field)
      }
    }
  }
}
