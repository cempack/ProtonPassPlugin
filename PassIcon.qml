import QtQuick
import QtQuick.Shapes
import qs.Commons

// Plugin mark: a shield with a keyhole, drawn on a 24-unit grid and scaled to
// the icon size in the theme colour.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: implicitWidth
  height: implicitHeight

  Shape {
    width: 24
    height: 24
    scale: root.width / 24
    transformOrigin: Item.TopLeft
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.color
      fillRule: ShapePath.OddEvenFill
      strokeWidth: -1
      PathSvg { path: "M12 1.2L20.6 4.6V11c0 5.4-3.6 9.9-8.6 11.8C7 20.9 3.4 16.4 3.4 11V4.6Zm0 2.4L5.7 6.1V11c0 4.2 2.6 7.8 6.3 9.4c3.7-1.6 6.3-5.2 6.3-9.4V6.1Z" }
    }
    ShapePath {
      fillColor: root.color
      strokeWidth: -1
      PathSvg { path: "M12 7.9a2.3 2.3 0 1 1 0 4.6a2.3 2.3 0 1 1 0-4.6ZM10.9 11.5h2.2l0.6 4.6h-3.4Z" }
    }
  }
}
