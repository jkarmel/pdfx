import QtQuick
import QtQuick.Window

Rectangle {
  id: root
  property string text: ""
  property string icon: ""
  property bool active: false
  property bool enabled: true
  property bool compact: false     // icon only
  property string tooltip: ""
  property bool tipAbove: false    // bottom bar buttons open their tooltip upward
  signal clicked()
  readonly property bool iconOnly: compact && icon.length > 0
  implicitHeight: 28
  implicitWidth: iconOnly ? 32 : label.implicitWidth + 20
  radius: Theme.radius
  color: active ? Theme.accent : (mouse.containsMouse && enabled ? Theme.surfaceRaised : "transparent")
  border.width: 1
  border.color: active ? Theme.accent : (mouse.containsMouse && enabled ? Theme.border : "transparent")
  opacity: enabled ? 1 : 0.4
  Text {
    id: label
    anchors.centerIn: parent
    text: root.iconOnly ? root.icon : ((root.icon ? root.icon + " " : "") + root.text)
    color: root.active ? Theme.background : Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: 13
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
  Rectangle {
    visible: mouse.containsMouse && (root.tooltip.length > 0 || root.iconOnly)
    y: root.tipAbove ? -height - 6 : parent.height + 6
    // Keep the label inside the window: position relative to the scene, not the button.
    x: {
      var hovering = mouse.containsMouse
      var sceneX = root.mapToItem(null, 0, 0).x
      var windowWidth = root.Window.width > 0 ? root.Window.width : sceneX + root.width + 400
      var desired = (root.width - width) / 2
      var minX = 8 - sceneX
      var maxX = windowWidth - 8 - width - sceneX
      return hovering ? Math.max(minX, Math.min(maxX, desired)) : desired
    }
    width: tip.implicitWidth + 16
    height: tip.implicitHeight + 10
    radius: 4
    color: Theme.surfaceRaised
    border.color: Theme.border
    z: 50
    Text { id: tip; anchors.centerIn: parent; text: root.tooltip || root.text; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 12 }
  }
}
