import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Search, filter chips and the item list. The search field keeps focus and owns
// list navigation, so typing always searches.
Item {
  id: root

  property var panel: null
  property var pass: null

  // True while any 2FA row is inside the viewport.
  property bool showsTotp: false

  function focusSearch() { search.forceActiveFocus() }
  function clearSearch() { search.text = "" }
  function resetScroll() { list.positionViewAtBeginning() }

  function revealCursor() {
    var rowIndex = panel.listModel.items[panel.cursor]
    if (rowIndex === undefined) return
    // Keep the section header in view when the first item is selected.
    if (panel.cursor === 0) list.positionViewAtBeginning()
    else list.positionViewAtIndex(rowIndex, ListView.Contain)
  }

  function updateShowsTotp() {
    if (!visible || list.count === 0) {
      showsTotp = false
      return
    }
    var top = list.indexAt(1, list.contentY + 1)
    var bottom = list.indexAt(1, list.contentY + list.height - 2)
    if (top < 0) top = 0
    if (bottom < 0) bottom = list.count - 1
    var rows = panel.listModel.rows
    for (var i = top; i <= bottom && i < rows.length; i++) {
      if (rows[i].kind === "item" && rows[i].item.hasTotp === true) {
        showsTotp = true
        return
      }
    }
    showsTotp = false
  }

  onVisibleChanged: totpScan.restart()

  Timer {
    id: totpScan
    interval: 150
    onTriggered: root.updateShowsTotp()
  }

  Connections {
    target: panel
    function onListModelChanged() { totpScan.restart() }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    TextField {
      id: search
      Layout.fillWidth: true
      placeholderText: panel.filter === "all"
        ? "Search " + pass.items.length + " items"
        : "Search " + Model.filterLabel(panel.filter).toLowerCase()
      text: panel.query
      foreground: panel.foreground
      font.family: panel.fontFamily
      onTextChanged: if (text !== panel.query) panel.setQuery(text)

      Keys.onPressed: function(event) {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        var shift = (event.modifiers & Qt.ShiftModifier) !== 0
        var handled = true
        if (panel.handleGlobalKey(event)) {
          // shared shortcut
        } else if (event.key === Qt.Key_Escape) {
          panel.back()
        } else if (event.key === Qt.Key_Down) {
          panel.moveCursor(1)
        } else if (event.key === Qt.Key_Up) {
          panel.moveCursor(-1)
        } else if (event.key === Qt.Key_PageDown) {
          panel.moveCursor(8)
        } else if (event.key === Qt.Key_PageUp) {
          panel.moveCursor(-8)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          panel.commitQuery()
          if (ctrl) panel.copyCode()
          else if (shift) panel.copy(panel.cursorItem, "username")
          else panel.activate()
        } else if (ctrl && event.key === Qt.Key_O) {
          panel.openWebsite()
        } else if (ctrl && event.key === Qt.Key_Right) {
          panel.cycleFilter(1)
        } else if (ctrl && event.key === Qt.Key_Left) {
          panel.cycleFilter(-1)
        } else if (event.key === Qt.Key_Right && cursorPosition === text.length && panel.cursorItem) {
          panel.openDetail()
        } else {
          handled = false
        }
        event.accepted = handled
      }
    }

    FilterBar {
      Layout.fillWidth: true
      panel: root.panel
      pass: root.pass
    }

    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      reuseItems: true
      cacheBuffer: Style.space(200)
      model: panel.listModel.rows
      spacing: Style.space(1)
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      onContentYChanged: totpScan.restart()
      onHeightChanged: totpScan.restart()

      delegate: Loader {
        id: rowLoader
        required property var modelData
        required property int index
        width: list.width
        sourceComponent: modelData.kind === "header" ? headerRow : itemRow

        Component {
          id: headerRow
          Item {
            implicitHeight: label.implicitHeight + Style.space(rowLoader.index === 0 ? 4 : 12)
            Row {
              id: label
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(3)
              spacing: Style.space(6)
              Text {
                text: String(rowLoader.modelData.title || "").toUpperCase()
                color: panel.dim
                font.family: panel.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }
              Text {
                text: String(rowLoader.modelData.count || "")
                color: panel.dim
                opacity: 0.7
                font.family: panel.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Component {
          id: itemRow
          ItemRow {
            readonly property int cursorIndex: rowLoader.modelData.cursor
            item: rowLoader.modelData.item
            hasCursor: panel.cursor === cursorIndex
            code: item && item.hasTotp ? Model.liveCode(pass.liveCodes, item, pass.now) : null
            hint: Model.primaryCopyField(item) ? "↵ copy" : "↵ open"
            foreground: panel.foreground
            dim: panel.dim
            urgent: panel.urgent
            fontFamily: panel.fontFamily
            onHovered: panel.cursor = cursorIndex
            onActivated: panel.openDetail(item)
            onCodeClicked: panel.copyCode(item)
          }
        }
      }

      // Empty states.
      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        visible: list.count === 0
        spacing: Style.space(6)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: panel.searching ? "󰍉" : Model.filterGlyph(panel.filter)
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.display
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: panel.searching ? "Nothing matches “" + panel.debouncedQuery.trim() + "”"
            : pass.items.length === 0 ? "Your vaults are empty" : "No items here"
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          visible: panel.searching || panel.filter !== "all"
          text: panel.filter !== "all" ? "Ctrl+← / Ctrl+→ to change the filter" : "Ctrl+N saves a new login"
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
