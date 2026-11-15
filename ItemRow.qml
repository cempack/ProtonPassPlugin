import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One item in the list: icon, title, subtitle and, for 2FA items, the live code.
CursorSurface {
  id: root

  property var item: null
  property var code: null  // { code, remaining, fraction } from Model.liveCode
  property color dim: Qt.darker(foreground, 1.55)
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family
  property string hint: ""

  readonly property bool totp: item ? item.hasTotp === true : false

  signal activated()
  signal hovered()
  signal codeClicked()

  implicitHeight: Math.max(Style.space(46), content.implicitHeight + Style.space(12))

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hovered()
    onClicked: root.activated()
  }

  RowLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)

    Favicon {
      item: root.item
      size: Style.space(30)
      foreground: root.foreground
      fontFamily: root.fontFamily
      Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.space(1)

      Text {
        Layout.fillWidth: true
        text: root.item ? String(root.item.title || "Untitled") : ""
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.hasCursor
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.item ? Model.itemSubtitle(root.item) : ""
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    // Live 2FA code: click to copy.
    Item {
      visible: root.totp
      Layout.alignment: Qt.AlignVCenter
      implicitWidth: codeRow.implicitWidth + Style.space(8)
      implicitHeight: codeRow.implicitHeight + Style.space(6)

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, codeMouse.containsMouse ? 0.14 : 0.06)
      }

      Row {
        id: codeRow
        anchors.centerIn: parent
        spacing: Style.space(5)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.code ? Model.formatCode(root.code.code) : "··· ···"
          color: root.code && root.code.remaining <= 5 ? root.urgent : root.foreground
          opacity: root.code ? 1 : 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          font.letterSpacing: 0.5
        }

        TotpRing {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.code !== null
          size: Style.space(14)
          fraction: root.code ? root.code.fraction : 0
          remaining: root.code ? root.code.remaining : 0
          foreground: root.foreground
          urgent: root.urgent
        }
      }

      MouseArea {
        id: codeMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.code !== null
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered()
        onClicked: root.codeClicked()
      }
    }

    Text {
      visible: root.hasCursor && root.hint !== ""
      Layout.alignment: Qt.AlignVCenter
      text: root.hint
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
