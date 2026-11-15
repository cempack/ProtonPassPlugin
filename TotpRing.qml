import QtQuick
import qs.Commons

// Countdown ring for a 2FA code: full at the start of a window, empty at expiry.
Canvas {
  id: root

  property real fraction: 1
  property int remaining: 0
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property int size: Style.space(16)
  property real lineWidth: Math.max(2, Math.round(size / 7))

  readonly property color _color: remaining > 0 && remaining <= 5 ? urgent : foreground

  implicitWidth: size
  implicitHeight: size
  antialiasing: true

  onFractionChanged: requestPaint()
  on_ColorChanged: requestPaint()
  onWidthChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var r = (Math.min(width, height) - lineWidth) / 2
    var cx = width / 2
    var cy = height / 2
    ctx.lineWidth = lineWidth
    ctx.lineCap = "round"
    ctx.strokeStyle = Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
    ctx.beginPath()
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.stroke()
    var f = Math.max(0, Math.min(1, fraction))
    if (f <= 0) return
    ctx.strokeStyle = _color
    ctx.beginPath()
    ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * f)
    ctx.stroke()
  }
}
