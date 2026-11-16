import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Title row: back button on sub-pages, title + account, busy state and actions.
Item {
  id: root

  property var panel: null
  property var pass: null

  readonly property bool subPage: panel.page !== "list" && !panel.blocked
  readonly property string title: {
    if (panel.blocked || panel.page === "list") return "Proton Pass"
    if (panel.page === "generator") return "Generator"
    if (panel.page === "create") return "New login"
    return panel.selectedItem ? String(panel.selectedItem.title || "Item") : "Item"
  }
  readonly property string busyText: pass.signingIn ? "Waiting for browser…"
    : pass.creating ? "Saving…"
    : pass.refreshing && pass.items.length > 0 ? "Syncing…"
    : ""

  implicitHeight: row.implicitHeight

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(6)

    PanelActionButton {
      visible: root.subPage
      iconText: "󰅁"
      tooltipText: "Back (Esc)"
      foreground: panel.foreground
      fontFamily: panel.fontFamily
      onClicked: panel.back()
    }

    PassIcon {
      visible: !root.subPage
      iconSize: Style.font.icon + 6
      color: panel.accent
      Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      Text {
        Layout.fillWidth: true
        text: root.title
        textFormat: Text.PlainText
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.busyText !== "" ? root.busyText
          : (!root.subPage && pass.email !== "" ? pass.email : "")
        textFormat: Text.PlainText
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    PanelActionButton {
      visible: !panel.blocked && panel.page !== "generator"
      iconText: "󰟵"
      tooltipText: "Password generator (Ctrl+G)"
      foreground: panel.foreground
      fontFamily: panel.fontFamily
      onClicked: panel.openGenerator()
    }

    PanelActionButton {
      visible: !panel.blocked && panel.page === "list"
      iconText: "󰐕"
      tooltipText: "New login (Ctrl+N)"
      foreground: panel.foreground
      fontFamily: panel.fontFamily
      onClicked: panel.openCreate("")
    }

    PanelActionButton {
      id: syncButton
      visible: !panel.blocked && panel.page === "list"
      enabled: !pass.refreshing
      iconText: "󰑐"
      tooltipText: "Sync now (Ctrl+R)"
      foreground: panel.foreground
      fontFamily: panel.fontFamily
      onClicked: panel.refresh()

      RotationAnimator on rotation {
        running: pass.refreshing
        loops: Animation.Infinite
        from: 0
        to: 360
        duration: 900
        onStopped: syncButton.rotation = 0
      }
    }

    PanelActionButton {
      iconText: "󰏌"
      tooltipText: "Open Proton Pass"
      foreground: panel.foreground
      fontFamily: panel.fontFamily
      onClicked: {
        pass.launchApp()
        panel.close()
      }
    }
  }
}
