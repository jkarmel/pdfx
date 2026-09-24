import QtQuick
import QtQuick.Controls
import Pdfx

// Vertical page previews. Click a page to jump to it.
Rectangle {
  id: root
  property PdfDoc doc: null
  property int currentPage: 0
  property real dpr: 1
  signal pageChosen(int page)
  color: Theme.surface
  Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }

  ListView {
    id: list
    anchors.fill: parent
    anchors.margins: 10
    anchors.rightMargin: 11
    spacing: 12
    clip: true
    model: root.doc ? root.doc.pageCount : 0
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    highlightFollowsCurrentItem: false
    Component.onCompleted: positionViewAtBeginning()
    Connections {
      target: root
      function onCurrentPageChanged() {
        if (list.count === 0) return
        var item = list.itemAtIndex(root.currentPage)
        var top = item ? item.y : root.currentPage * (list.contentHeight / Math.max(1, list.count))
        var bottom = top + (item ? item.height : 0)
        if (top < list.contentY + 20) list.contentY = Math.max(0, top - 20)
        else if (bottom > list.contentY + list.height - 20) list.contentY = Math.min(Math.max(0, list.contentHeight - list.height), bottom - list.height + 20)
      }
    }
    delegate: Item {
      id: thumb
      required property int index
      readonly property var size: root.doc.pageSizes[index] || ({width: 612, height: 792})
      readonly property bool current: index === root.currentPage
      width: list.width
      height: frame.height + 18
      Rectangle {
        id: frame
        width: parent.width - 6
        x: 3
        height: Math.round(width * size.height / size.width)
        color: "white"
        border.width: thumb.current ? 2 : 1
        border.color: thumb.current ? Theme.accent : Theme.border
        Image {
          anchors.fill: parent
          anchors.margins: thumb.current ? 2 : 1
          asynchronous: true
          cache: false
          fillMode: Image.Stretch
          sourceSize: Qt.size(Math.round(width * root.dpr), Math.round(height * root.dpr))
          source: root.doc && root.doc.key ? "image://pdfx/" + root.doc.key + "/" + thumb.index + "/" + root.doc.revision : ""
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pageChosen(thumb.index) }
      }
      Text {
        anchors.top: frame.bottom
        anchors.topMargin: 3
        anchors.horizontalCenter: parent.horizontalCenter
        text: thumb.index + 1
        color: thumb.current ? Theme.accent : Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: 11
      }
    }
  }
}
