import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Item inspector: hero, quick actions, live 2FA and every field, keyboard first.
//   ↑↓ field · ↵ copy field · Space reveal · c password · u username · t 2FA
//   Ctrl+O website · Esc/← back
FocusScope {
  id: root

  property var panel: null
  property var pass: null

  property int fieldCursor: -1
  property var revealed: ({})

  readonly property var item: panel.selectedItem
  readonly property var inspector: pass.inspector
  // Sections without the primary 2FA field (the 2FA card shows it), plus a flat
  // field list for the keyboard cursor. Each section knows its first flat index.
  readonly property var sections: {
    var out = []
    var offset = 0
    var source = inspector && inspector.sections ? inspector.sections : []
    for (var i = 0; i < source.length; i++) {
      var kept = (source[i].fields || []).filter(function(f) { return f.id !== "totp" })
      if (kept.length === 0) continue
      out.push({ title: String(source[i].title || ""), fields: kept, offset: offset })
      offset += kept.length
    }
    return out
  }
  readonly property var fields: {
    var out = []
    for (var i = 0; i < sections.length; i++) out = out.concat(sections[i].fields)
    return out
  }
  readonly property bool hasPassword: Model.primaryCopyField(item) !== ""
  readonly property bool hasUser: !!item && String(item.username || item.email || "") !== ""
  readonly property bool hasTotp: (!!item && item.hasTotp === true) || (!!inspector && inspector.hasTotp === true)
  readonly property string website: Model.primaryUrl(item)
  readonly property string totpCode: {
    var codes = pass.totpCodes || {}
    var live = Model.liveCode(pass.liveCodes, item, pass.now)
    return String(codes.totp || (live ? live.code : ""))
  }
  readonly property int totpRemaining: Model.totpSecondsRemaining(pass.now, 30)

  onItemChanged: {
    fieldCursor = -1
    revealed = ({})
    scroller.contentY = 0
  }

  function isRevealed(field) {
    return !!field && revealed[field.id] === true
  }

  function toggleReveal(field) {
    if (!field || field.kind !== "secret") return
    var next = {}
    for (var key in revealed) next[key] = revealed[key]
    next[field.id] = !next[field.id]
    revealed = next
  }

  function displayValue(field) {
    if (!field) return ""
    if (field.kind === "totp") {
      var codes = pass.totpCodes || {}
      var code = String(codes[String(field.field || "totp")] || codes.totp || "")
      return code !== "" ? Model.formatCode(code) : "··· ···"
    }
    if (field.kind === "secret" && !isRevealed(field)) return "••••••••••••"
    return String(field.value || "")
  }

  function copyField(field) {
    if (!field || !item) return
    if (field.kind === "totp") {
      var codes = pass.totpCodes || {}
      var code = String(codes[String(field.field || "totp")] || codes.totp || "")
      if (code !== "") pass.copyText(code, "2FA code")
      return
    }
    var name = String(field.field || "")
    if (name !== "") pass.copyField(item, name, String(field.label || Model.fieldLabel(name)))
    else if (String(field.value || "") !== "") pass.copyText(field.value, String(field.label || "Value"))
  }

  function copyTotp() {
    if (totpCode !== "") pass.copyText(totpCode, "2FA code")
    else if (hasTotp) pass.notify("2FA code is still loading", "info")
  }

  function fieldRowAt(index) {
    for (var s = sectionRepeater.count - 1; s >= 0; s--) {
      var section = sectionRepeater.itemAt(s)
      if (section && index >= section.offset) return section.rowAt(index - section.offset)
    }
    return null
  }

  function moveField(step) {
    if (fields.length === 0) return
    fieldCursor = Math.max(0, Math.min(fields.length - 1, fieldCursor < 0 ? 0 : fieldCursor + step))
    var row = fieldRowAt(fieldCursor)
    if (!row) return
    var y = row.mapToItem(content, 0, 0).y
    if (y < scroller.contentY) scroller.contentY = Math.max(0, y - Style.space(8))
    else if (y + row.height > scroller.contentY + scroller.height)
      scroller.contentY = Math.min(scroller.contentHeight - scroller.height, y + row.height - scroller.height + Style.space(8))
  }

  Keys.onPressed: function(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var handled = true
    if (panel.handleGlobalKey(event)) {
    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Left || event.key === Qt.Key_Backspace) {
      panel.back()
    } else if (event.key === Qt.Key_Down || event.text === "j") {
      moveField(1)
    } else if (event.key === Qt.Key_Up || event.text === "k") {
      moveField(-1)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (fieldCursor >= 0) copyField(fields[fieldCursor])
      else if (hasPassword) panel.copy(item, "password")
    } else if (event.key === Qt.Key_Space) {
      if (fieldCursor >= 0) toggleReveal(fields[fieldCursor])
    } else if (ctrl && event.key === Qt.Key_O) {
      panel.openWebsite(item)
    } else if (!ctrl && event.text === "c" && hasPassword) {
      panel.copy(item, "password")
    } else if (!ctrl && event.text === "u" && hasUser) {
      panel.copy(item, "username")
    } else if (!ctrl && event.text === "t") {
      copyTotp()
    } else {
      handled = false
    }
    event.accepted = handled
  }

  Flickable {
    id: scroller
    anchors.fill: parent
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: content
      width: scroller.width
      spacing: Style.space(12)

      // Hero.
      RowLayout {
        width: parent.width
        spacing: Style.space(12)

        Favicon {
          item: root.item
          size: Style.space(46)
          foreground: panel.foreground
          fontFamily: panel.fontFamily
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            Layout.fillWidth: true
            text: root.item ? String(root.item.title || "Untitled") : ""
            textFormat: Text.PlainText
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.title + 2
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            text: root.item
              ? [Model.itemTypeLabel(root.item.itemType), String(root.item.vaultName || "")].filter(function(s) { return s !== "" }).join(" · ")
              : ""
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: root.website !== ""
            text: Model.displayHost(root.website) + "  󰏌"
            color: siteMouse.containsMouse ? panel.foreground : panel.accent
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight

            MouseArea {
              id: siteMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: panel.openWebsite(root.item)
            }
          }
        }
      }

      // Quick actions.
      Flow {
        width: parent.width
        spacing: Style.space(6)

        Button {
          visible: root.hasPassword
          text: "Password"
          iconText: "󰆏"
          tooltipText: "Copy password (c)"
          selected: true
          bordered: true
          foreground: panel.foreground
          fontFamily: panel.fontFamily
          onClicked: panel.copy(root.item, "password")
        }
        Button {
          visible: root.hasUser
          text: "Username"
          iconText: "󰀄"
          tooltipText: "Copy username (u)"
          bordered: true
          foreground: panel.foreground
          fontFamily: panel.fontFamily
          onClicked: panel.copy(root.item, "username")
        }
        Button {
          visible: root.hasTotp
          text: "2FA"
          iconText: "󰦯"
          tooltipText: "Copy 2FA code (t)"
          bordered: true
          foreground: panel.foreground
          fontFamily: panel.fontFamily
          onClicked: root.copyTotp()
        }
        Button {
          visible: root.website !== ""
          text: "Open"
          iconText: "󰏌"
          tooltipText: "Open website (Ctrl+O)"
          bordered: true
          foreground: panel.foreground
          fontFamily: panel.fontFamily
          onClicked: panel.openWebsite(root.item)
        }
      }

      // Live 2FA.
      Rectangle {
        visible: root.hasTotp
        width: parent.width
        implicitHeight: totpRow.implicitHeight + Style.space(18)
        radius: Style.cornerRadius + 2
        color: Qt.rgba(panel.foreground.r, panel.foreground.g, panel.foreground.b, totpMouse.containsMouse ? 0.10 : 0.06)

        RowLayout {
          id: totpRow
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(10)

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
              text: "2FA CODE"
              color: panel.dim
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
            }
            Text {
              text: root.totpCode !== "" ? Model.formatCode(root.totpCode) : "··· ···"
              color: root.totpRemaining <= 5 && root.totpCode !== "" ? panel.urgent : panel.foreground
              opacity: root.totpCode !== "" ? 1 : 0.45
              font.family: panel.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              font.letterSpacing: 2
            }
          }

          TotpRing {
            visible: root.totpCode !== ""
            size: Style.space(26)
            fraction: root.totpRemaining / 30
            remaining: root.totpRemaining
            foreground: panel.foreground
            urgent: panel.urgent
          }
          Text {
            visible: root.totpCode !== ""
            text: root.totpRemaining + "s"
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          id: totpMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.copyTotp()
        }
      }

      // Loading.
      Text {
        visible: pass.inspecting && !root.inspector
        text: "Loading item…"
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.body
        SequentialAnimation on opacity {
          running: pass.inspecting
          loops: Animation.Infinite
          NumberAnimation { from: 0.35; to: 1; duration: 650 }
          NumberAnimation { from: 1; to: 0.35; duration: 650 }
        }
      }

      // Fields, grouped by section.
      Repeater {
        id: sectionRepeater
        model: root.sections

        Column {
          id: sectionColumn
          required property var modelData
          readonly property int offset: modelData.offset
          function rowAt(i) { return rowRepeater.itemAt(i) }

          width: content.width
          spacing: Style.space(2)

          PanelSectionHeader {
            width: parent.width
            visible: sectionColumn.modelData.title !== ""
            text: sectionColumn.modelData.title.toUpperCase()
            foreground: panel.foreground
            fontFamily: panel.fontFamily
          }

          Repeater {
            id: rowRepeater
            model: sectionColumn.modelData.fields

            CursorSurface {
              id: fieldRow
              required property var modelData
              required property int index
              readonly property int flatIndex: sectionColumn.offset + index
              readonly property bool secret: modelData.kind === "secret"
              readonly property bool multiline: modelData.kind === "note" || (secret && root.isRevealed(modelData))

              width: content.width
              foreground: panel.foreground
              hasCursor: root.fieldCursor === flatIndex
              implicitHeight: fieldContent.implicitHeight + Style.space(12)

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.fieldCursor = fieldRow.flatIndex
                onClicked: root.copyField(fieldRow.modelData)
              }

              RowLayout {
                id: fieldContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(6)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  Text {
                    text: String(fieldRow.modelData.label || "")
                    color: panel.dim
                    font.family: panel.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    Layout.fillWidth: true
                    text: root.displayValue(fieldRow.modelData) || "—"
                    textFormat: Text.PlainText
                    color: panel.foreground
                    font.family: panel.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: fieldRow.multiline ? Text.WrapAnywhere : Text.NoWrap
                    elide: fieldRow.multiline ? Text.ElideNone : Text.ElideRight
                    maximumLineCount: fieldRow.multiline ? 12 : 1
                  }
                }

                PanelActionButton {
                  visible: fieldRow.secret
                  iconText: root.isRevealed(fieldRow.modelData) ? "󰈉" : "󰈈"
                  tooltipText: root.isRevealed(fieldRow.modelData) ? "Hide (Space)" : "Show (Space)"
                  foreground: panel.foreground
                  fontFamily: panel.fontFamily
                  onClicked: root.toggleReveal(fieldRow.modelData)
                }
                PanelActionButton {
                  iconText: "󰆏"
                  tooltipText: "Copy (↵)"
                  foreground: panel.foreground
                  fontFamily: panel.fontFamily
                  onClicked: root.copyField(fieldRow.modelData)
                }
              }
            }
          }
        }
      }
    }
  }
}
