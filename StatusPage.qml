import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Everything shown instead of the list: loading skeleton, sign-in, missing
// pass-cli and load errors. ↵ runs the primary action.
FocusScope {
  id: root

  property var panel: null
  property var pass: null

  readonly property string kind: pass.needsSignIn ? "signin"
    : pass.status === "missing" ? "missing"
    : pass.status === "error" ? "error"
    : "loading"
  readonly property string installCommand: "omarchy pkg aur add proton-pass-cli"

  function primary() {
    if (kind === "signin") pass.signingIn ? pass.cancelSignIn() : pass.signIn()
    else if (kind === "missing") pass.copyText(installCommand, "Install command")
    else if (kind === "error") pass.refresh(true)
  }

  Keys.onPressed: function(event) {
    var handled = true
    if (panel.handleGlobalKey(event)) {
    } else if (event.key === Qt.Key_Escape) {
      panel.close()
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      primary()
    } else {
      handled = false
    }
    event.accepted = handled
  }

  // Loading skeleton.
  Column {
    anchors.fill: parent
    visible: root.kind === "loading"
    spacing: Style.space(10)

    Repeater {
      model: 7
      RowLayout {
        required property int index
        width: parent.width
        spacing: Style.space(10)
        opacity: shimmer.value * (1 - index * 0.1)

        Rectangle {
          implicitWidth: Style.space(30)
          implicitHeight: Style.space(30)
          radius: Style.cornerRadius + 2
          color: panel.faint
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(5)
          Rectangle { implicitWidth: Style.space(120 + (index * 37) % 80); implicitHeight: Style.space(9); radius: 3; color: panel.faint }
          Rectangle { implicitWidth: Style.space(80 + (index * 53) % 90); implicitHeight: Style.space(7); radius: 3; color: panel.faint }
        }
      }
    }

    QtObject {
      id: shimmer
      property real value: 1
      SequentialAnimation on value {
        running: root.kind === "loading" && root.visible
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 0.45; duration: 700; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 0.45; to: 1; duration: 700; easing.type: Easing.InOutQuad }
      }
    }
  }

  // Sign-in, missing and error.
  ColumnLayout {
    anchors.centerIn: parent
    width: parent.width - Style.space(24)
    visible: root.kind !== "loading"
    spacing: Style.space(10)

    PassIcon {
      Layout.alignment: Qt.AlignHCenter
      visible: root.kind === "signin"
      iconSize: Style.font.displayLarge + 8
      color: panel.accent
    }

    Text {
      Layout.alignment: Qt.AlignHCenter
      visible: root.kind !== "signin"
      text: root.kind === "missing" ? "󰏗" : "󰀦"
      color: root.kind === "error" ? panel.urgent : panel.accent
      font.family: panel.fontFamily
      font.pixelSize: Style.font.displayLarge + 8
    }

    Text {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      text: root.kind === "signin" ? (pass.signingIn ? "Finish in your browser" : "Sign in to Proton Pass")
        : root.kind === "missing" ? "pass-cli is not installed"
        : "Could not load your vaults"
      color: panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.title + 2
      font.bold: true
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: {
        if (root.kind === "signin") {
          if (pass.signingIn) return "A Proton sign-in page opened in your browser. Approve it there and your items load here."
          if (pass.status === "locked") return "The session is locked. Sign in again to continue."
          if (pass.status === "migration-required") return "The saved session could not be read. Signing in again replaces it."
          return "The panel keeps its own session, separate from any pass-cli login in a terminal."
        }
        if (root.kind === "missing") return "Install the Proton Pass CLI, then reopen this panel."
        return pass.lastError || "Something went wrong talking to pass-cli."
      }
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.body
    }

    // Copyable install command.
    Rectangle {
      visible: root.kind === "missing"
      Layout.fillWidth: true
      implicitHeight: command.implicitHeight + Style.space(14)
      radius: Style.cornerRadius
      color: Qt.rgba(panel.foreground.r, panel.foreground.g, panel.foreground.b, commandMouse.containsMouse ? 0.10 : 0.06)
      Text {
        id: command
        anchors.centerIn: parent
        text: root.installCommand + "  󰆏"
        color: panel.foreground
        font.family: "monospace"
        font.pixelSize: Style.font.caption
      }
      MouseArea {
        id: commandMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.primary()
      }
    }

    Text {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      visible: root.kind === "signin" && !pass.signingIn && pass.lastError !== "" && pass.lastError !== pass.statusMessageFor(pass.status, "")
      text: pass.lastError
      color: panel.urgent
      wrapMode: Text.WordWrap
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Button {
      Layout.fillWidth: true
      Layout.topMargin: Style.space(4)
      visible: root.kind !== "missing"
      text: root.kind === "signin" ? (pass.signingIn ? "Cancel" : "Sign in") : "Try again"
      iconText: root.kind === "signin" ? (pass.signingIn ? "󰜺" : "󰍂") : "󰑐"
      selected: !pass.signingIn
      bordered: true
      foreground: panel.foreground
      fontFamily: panel.fontFamily
      verticalPadding: Style.space(10)
      onClicked: root.primary()
    }
  }
}
