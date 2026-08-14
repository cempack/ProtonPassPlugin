import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

CursorSurface {
  id: root

  property var item: null
  property int rowIndex: 0
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  readonly property string titleText: item ? String(item.title || "Untitled") : "Untitled"
  readonly property string subtitleText: item ? Model.itemSubtitle(item) : ""
  readonly property string glyph: Model.letterGlyph(titleText)

  signal activated()
  signal hovered()

  implicitHeight: row.implicitHeight + Style.spacing.rowPaddingX

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    preventStealing: false
    propagateComposedEvents: true
    onEntered: root.hovered()
    onClicked: root.activated()
  }

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)

    Rectangle {
      Layout.preferredWidth: Style.space(28)
      Layout.preferredHeight: Style.space(28)
      Layout.alignment: Qt.AlignVCenter
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

      Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)

      Text {
        Layout.fillWidth: true
        text: root.titleText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        visible: root.subtitleText !== ""
        Layout.fillWidth: true
        text: root.subtitleText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      text: "󰅂"
      color: Qt.darker(root.foreground, 1.8)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      Layout.alignment: Qt.AlignVCenter
    }
  }
}
