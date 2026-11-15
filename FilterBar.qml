import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Type chips with counts (All, 2FA, Logins, …) and a vault picker when there is
// more than one vault. Ctrl+←/→ in the search field cycles the chips.
ColumnLayout {
  id: root

  property var panel: null
  property var pass: null

  spacing: Style.space(6)
  visible: pass.items.length > 0

  Dropdown {
    Layout.fillWidth: true
    visible: panel.vaults.length > 1
    showLabel: false
    label: "Vault"
    value: panel.vault
    options: [{ value: "", label: "All vaults" }].concat(panel.vaults.map(function(v) {
      return { value: v.shareId, label: v.name }
    }))
    foreground: panel.foreground
    fontFamily: panel.fontFamily
    onChanged: function(value) {
      panel.setVault(value)
      panel.focusPage()
    }
  }

  Flickable {
    id: strip
    Layout.fillWidth: true
    implicitHeight: chipRow.implicitHeight
    contentWidth: chipRow.implicitWidth
    contentHeight: chipRow.implicitHeight
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    function revealSelected() {
      for (var i = 0; i < chipRepeater.count; i++) {
        var chip = chipRepeater.itemAt(i)
        if (!chip || chip.key !== panel.filter) continue
        if (chip.x < contentX) contentX = chip.x
        else if (chip.x + chip.width > contentX + width) contentX = chip.x + chip.width - width
      }
    }

    Connections {
      target: panel
      function onFilterChanged() { Qt.callLater(strip.revealSelected) }
    }

    Row {
      id: chipRow
      spacing: Style.space(5)

      Repeater {
        id: chipRepeater
        model: panel.chips

        Rectangle {
          id: chip
          required property var modelData
          readonly property string key: modelData.key
          readonly property bool selected: panel.filter === key

          implicitWidth: chipContent.implicitWidth + Style.space(16)
          implicitHeight: chipContent.implicitHeight + Style.space(8)
          radius: height / 2
          color: selected
            ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.22)
            : Qt.rgba(panel.foreground.r, panel.foreground.g, panel.foreground.b, chipMouse.containsMouse ? 0.10 : 0.05)
          border.width: selected ? 1 : 0
          border.color: panel.accent

          Behavior on color { ColorAnimation { duration: 120 } }

          Row {
            id: chipContent
            anchors.centerIn: parent
            spacing: Style.space(5)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: chip.modelData.glyph
              color: chip.selected ? panel.accent : panel.dim
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption + 1
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: chip.modelData.label
              color: chip.selected ? panel.foreground : panel.dim
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: chip.selected
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: String(chip.modelData.count)
              color: panel.dim
              opacity: 0.75
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              panel.setFilter(chip.key)
              panel.focusPage()
            }
          }
        }
      }
    }
  }
}
