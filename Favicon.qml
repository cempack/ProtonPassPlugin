import QtQuick
import qs.Commons
import "Model.js" as Model

// Site icon for an item, falling back through favicon sources and then to the
// item type glyph on a tinted tile.
Rectangle {
  id: root

  property var item: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int size: Style.space(30)

  property var _sources: []
  property int _index: 0
  readonly property string _source: _index >= 0 && _index < _sources.length ? String(_sources[_index]) : ""

  implicitWidth: size
  implicitHeight: size
  radius: Math.min(Style.cornerRadius + 2, size / 2)
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
  clip: true

  function reload() {
    _index = 0
    _sources = item ? Model.faviconUrls(item) : []
  }

  onItemChanged: reload()
  Component.onCompleted: reload()

  Image {
    id: image
    anchors.fill: parent
    anchors.margins: Math.round(root.size * 0.16)
    source: root._source
    sourceSize.width: 64
    sourceSize.height: 64
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: true
    smooth: true
    visible: root._source !== "" && status === Image.Ready
    onStatusChanged: {
      if (status === Image.Error) root._index = Model.nextFaviconIndex(root._sources.length, root._index, true)
    }
  }

  Text {
    anchors.centerIn: parent
    visible: !image.visible
    text: root.item ? Model.itemTypeGlyph(root.item) : "󰌆"
    color: root.foreground
    opacity: 0.85
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.size * 0.5)
  }
}
