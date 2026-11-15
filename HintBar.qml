import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Footer: keyboard hints for the current page, replaced by a toast when there
// is feedback (copied, created, errors).
Item {
  id: root

  property var panel: null
  property var pass: null

  readonly property var hints: {
    if (panel.blocked) return [["↵", "continue"], ["Esc", "close"]]
    if (panel.page === "detail") return [["↵", "copy"], ["␣", "reveal"], ["c", "pass"], ["u", "user"], ["t", "2FA"]]
    if (panel.page === "generator") return [["↵", "copy"], ["r", "new"], ["m", "mode"], ["←→", "length"], ["n", "save"]]
    if (panel.page === "create") return [["↵", "next"], ["Ctrl ↵", "save"], ["Ctrl G", "generate"]]
    return [["↵", "copy"], ["⇧↵", "user"], ["Ctrl ↵", "2FA"], ["→", "open"], ["Ctrl ←→", "filter"]]
  }
  readonly property bool toast: pass.notice !== ""
  readonly property color toastColor: pass.noticeTone === "error" ? panel.urgent
    : pass.noticeTone === "success" ? panel.accent : panel.foreground

  implicitHeight: Style.space(24)

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 1
    color: panel.faint
  }

  // Hints.
  Row {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: 2
    spacing: Style.space(9)
    opacity: root.toast ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Repeater {
      model: root.hints
      Row {
        required property var modelData
        spacing: Style.space(3)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: keyText.implicitWidth + Style.space(8)
          implicitHeight: keyText.implicitHeight + Style.space(2)
          radius: Style.space(3)
          color: panel.faint
          Text {
            id: keyText
            anchors.centerIn: parent
            text: modelData[0]
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption - 1
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: modelData[1]
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption - 1
        }
      }
    }
  }

  // Toast.
  RowLayout {
    anchors.fill: parent
    anchors.topMargin: 2
    spacing: Style.space(6)
    opacity: root.toast ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140 } }

    Text {
      text: pass.noticeTone === "error" ? "󰅚" : pass.noticeTone === "success" ? "󰄬" : "󰋽"
      color: root.toastColor
      font.family: panel.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      Layout.fillWidth: true
      text: pass.notice
      textFormat: Text.PlainText
      color: root.toastColor
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
    }
  }
}
