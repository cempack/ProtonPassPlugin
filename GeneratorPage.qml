import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Password / passphrase generator backed by `pass-cli password generate`.
//   ↵ or c copy · r regenerate · m switch mode · +/− length · n new login · Esc back
FocusScope {
  id: root

  property var panel: null
  property var pass: null

  property string mode: "random"
  property int length: 20
  property bool uppercase: true
  property bool numbers: true
  property bool symbols: true
  property int words: 5
  property string separator: "hyphens"
  property bool capitalise: true

  readonly property var options: ({
    mode: mode, length: length, uppercase: uppercase, numbers: numbers, symbols: symbols,
    words: words, separator: separator, capitalise: capitalise
  })
  readonly property var strength: Model.generatorStrength(options)
  readonly property color strengthColor: strength.level <= 1 ? panel.urgent
    : strength.level === 2 ? Qt.tint(panel.urgent, Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.5))
    : panel.accent
  readonly property color symbolColor: Qt.tint(panel.foreground, Qt.rgba(panel.urgent.r, panel.urgent.g, panel.urgent.b, 0.6))

  function regenerate() {
    pass.generate(options)
  }

  onOptionsChanged: if (visible) regenTimer.restart()

  Timer {
    id: regenTimer
    interval: 140
    onTriggered: root.regenerate()
  }

  function copy() {
    if (pass.generated !== "") pass.copyText(pass.generated, mode === "passphrase" ? "Passphrase" : "Password")
  }

  function adjust(step) {
    if (mode === "passphrase") words = Math.max(3, Math.min(10, words + step))
    else length = Math.max(8, Math.min(64, length + step))
  }

  // Digits and symbols get their own colours so look-alike characters are easy to read.
  function styled(value) {
    var out = ""
    for (var i = 0; i < value.length; i++) {
      var ch = value.charAt(i)
      var safe = ch === "&" ? "&amp;" : ch === "<" ? "&lt;" : ch === ">" ? "&gt;" : ch === "\"" ? "&quot;" : ch
      if (/[0-9]/.test(ch)) out += "<font color='" + panel.accent + "'>" + safe + "</font>"
      else if (/[^A-Za-z0-9]/.test(ch)) out += "<font color='" + symbolColor + "'>" + safe + "</font>"
      else out += safe
    }
    return out
  }

  Keys.onPressed: function(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var handled = true
    if (!ctrl && event.text === "n") {
      if (pass.generated !== "") panel.openCreate(pass.generated)
    } else if (panel.handleGlobalKey(event)) {
    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
      panel.back()
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.text === "c") {
      copy()
    } else if (event.text === "r" || event.key === Qt.Key_Space) {
      regenerate()
    } else if (event.text === "m") {
      mode = mode === "random" ? "passphrase" : "random"
    } else if (event.text === "+" || event.text === "=" || event.key === Qt.Key_Right) {
      adjust(1)
    } else if (event.text === "-" || event.key === Qt.Key_Left) {
      adjust(-1)
    } else {
      handled = false
    }
    event.accepted = handled
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(12)

    ButtonGroup {
      Layout.fillWidth: true
      options: [
        { value: "random", label: "Random", icon: "󰒲" },
        { value: "passphrase", label: "Passphrase", icon: "󰗊" }
      ]
      value: root.mode
      foreground: panel.foreground
      fontFamily: panel.fontFamily
      focusable: false
      onChanged: function(value) {
        root.mode = value
        root.forceActiveFocus()
      }
    }

    // Output.
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: Math.max(Style.space(76), output.implicitHeight + Style.space(24))
      radius: Style.cornerRadius + 2
      color: Qt.rgba(panel.foreground.r, panel.foreground.g, panel.foreground.b, outputMouse.containsMouse ? 0.10 : 0.06)

      Text {
        id: output
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(12)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.StyledText
        text: pass.generated !== "" ? root.styled(pass.generated) : (pass.generating ? "Generating…" : "")
        color: panel.foreground
        opacity: pass.generating && pass.generated === "" ? 0.5 : 1
        font.family: "monospace"
        font.pixelSize: Style.font.title + 2
        wrapMode: Text.WrapAnywhere
      }

      MouseArea {
        id: outputMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.copy()
      }
    }

    // Strength.
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)

      Rectangle {
        Layout.fillWidth: true
        implicitHeight: Style.space(4)
        radius: height / 2
        color: Qt.rgba(panel.foreground.r, panel.foreground.g, panel.foreground.b, 0.1)

        Rectangle {
          width: parent.width * root.strength.fraction
          height: parent.height
          radius: parent.radius
          color: root.strengthColor
          Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: root.strength.label
          color: root.strengthColor
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Text {
          text: "≈ " + root.strength.bits + " bits"
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // Length / words.
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)

      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: root.mode === "passphrase" ? "Words" : "Length"
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          text: String(root.mode === "passphrase" ? root.words : root.length)
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      PanelSlider {
        Layout.fillWidth: true
        bar: panel.bar
        integer: true
        step: 1
        minimum: root.mode === "passphrase" ? 3 : 8
        maximum: root.mode === "passphrase" ? 10 : 64
        value: root.mode === "passphrase" ? root.words : root.length
        onMoved: function(value) {
          if (root.mode === "passphrase") root.words = Math.round(value)
          else root.length = Math.round(value)
        }
      }
    }

    // Options.
    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.space(10)
      rowSpacing: Style.space(6)

      Option { visible: root.mode === "random"; label: "Uppercase"; checked: root.uppercase; onToggled: root.uppercase = !root.uppercase }
      Option { visible: root.mode === "random"; label: "Symbols"; checked: root.symbols; onToggled: root.symbols = !root.symbols }
      Option { visible: root.mode === "passphrase"; label: "Capitalise"; checked: root.capitalise; onToggled: root.capitalise = !root.capitalise }
      Option { label: "Numbers"; checked: root.numbers; onToggled: root.numbers = !root.numbers }
    }

    Dropdown {
      Layout.fillWidth: true
      visible: root.mode === "passphrase"
      showLabel: false
      label: "Separator"
      value: root.separator
      options: [
        { value: "hyphens", label: "Hyphens  a-b" },
        { value: "spaces", label: "Spaces  a b" },
        { value: "periods", label: "Periods  a.b" },
        { value: "commas", label: "Commas  a,b" },
        { value: "underscores", label: "Underscores  a_b" },
        { value: "numbers", label: "Numbers  a4b" },
        { value: "numbers-and-symbols", label: "Numbers & symbols  a4!b" }
      ]
      foreground: panel.foreground
      fontFamily: panel.fontFamily
      onChanged: function(value) {
        root.separator = value
        root.forceActiveFocus()
      }
    }

    Item { Layout.fillHeight: true }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)

      Button {
        Layout.fillWidth: true
        text: "Regenerate"
        iconText: "󰑐"
        iconSpinning: pass.generating
        bordered: true
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        onClicked: root.regenerate()
      }
      Button {
        Layout.fillWidth: true
        text: "New login"
        iconText: "󰐕"
        enabled: pass.generated !== ""
        bordered: true
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        onClicked: panel.openCreate(pass.generated)
      }
      Button {
        Layout.fillWidth: true
        text: "Copy"
        iconText: "󰆏"
        enabled: pass.generated !== ""
        selected: true
        bordered: true
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        onClicked: root.copy()
      }
    }
  }

  component Option: RowLayout {
    id: option
    property string label: ""
    property bool checked: false
    signal toggled()

    Layout.fillWidth: true
    spacing: Style.space(8)

    Text {
      Layout.fillWidth: true
      text: option.label
      color: panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.body
    }
    ToggleSwitch {
      checked: option.checked
      cursorRing: false
      foreground: panel.foreground
      accent: panel.accent
      onToggled: option.toggled()
    }
  }
}
