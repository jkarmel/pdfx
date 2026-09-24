import QtQuick
import Quickshell
import Quickshell.Io

// One Save button, two outcomes: overwrite the original, or write a new file
// with a suggested name, into a folder you can change (or browse for).
Rectangle {
  id: root
  property string originalPath: ""
  property string suggestedName: ""
  signal overwrite()
  signal saveAs(string path)
  signal dismissed()
  readonly property string originalDirectory: originalPath.substring(0, originalPath.lastIndexOf("/"))
  readonly property string originalName: originalPath.substring(originalPath.lastIndexOf("/") + 1)
  property string message: ""
  anchors.fill: parent
  color: Qt.rgba(0, 0, 0, 0.45)
  z: 100
  MouseArea { anchors.fill: parent; onClicked: root.dismissed() }

  onVisibleChanged: {
    if (!visible) { chooser.running = false; return }
    nameInput.text = suggestedName
    folderInput.text = originalDirectory
    message = ""
  }
  function commitSaveAs() {
    var name = nameInput.text.trim()
    var folder = folderInput.text.trim().replace(/\/+$/, "")
    if (!name) { message = "Enter a file name."; return }
    if (!folder) { message = "Enter a folder."; return }
    if (folder.indexOf("~") === 0) folder = Quickshell.env("HOME") + folder.substring(1)
    if (!/\.pdf$/i.test(name)) name += ".pdf"
    var path = folder + "/" + name
    if (path === originalPath) { root.overwrite(); return }
    root.saveAs(path)
  }
  function browse() {
    if (chooser.running) return
    var folder = folderInput.text.trim() || originalDirectory
    if (folder.indexOf("~") === 0) folder = Quickshell.env("HOME") + folder.substring(1)
    chooser.command = [Qt.resolvedUrl("../bin/pdfx-choose-save").toString().replace(/^file:\/\//, ""), folder, nameInput.text.trim() || root.suggestedName, "Save PDF"]
    chooser.running = true
    message = "Choose where to save in the file dialog…"
  }
  Process {
    id: chooser
    stdout: StdioCollector {
      onStreamFinished: {
        var path = text.trim()
        if (path) { root.message = ""; root.saveAs(path) }
      }
    }
    stderr: StdioCollector { onStreamFinished: if (text.trim()) root.message = text.trim() }
    onExited: function(code) { if (code !== 0 && root.message.indexOf("Choose") === 0) root.message = "" }
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - 32, 600)
    height: body.implicitHeight + 40
    radius: Theme.radius + 2
    color: Theme.surface
    border.color: Theme.border
    MouseArea { anchors.fill: parent }
    Column {
      id: body
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
      anchors.margins: 20
      spacing: 14
      Text { text: "Save"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 16; font.bold: true }

      // Option 1: overwrite
      Rectangle {
        width: parent.width; height: 64; radius: Theme.radius
        color: overwriteMouse.containsMouse ? Theme.surfaceRaised : Theme.background
        border.color: overwriteMouse.containsMouse ? Theme.accent : Theme.border
        Column {
          anchors.verticalCenter: parent.verticalCenter; x: 14; width: parent.width - 28; spacing: 3
          Text { text: "Overwrite the original"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13; font.bold: true }
          Text { text: root.originalPath; width: parent.width; elide: Text.ElideMiddle; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 12 }
        }
        MouseArea { id: overwriteMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.overwrite() }
      }

      // Option 2: new file
      Rectangle {
        width: parent.width; height: newFileColumn.implicitHeight + 24; radius: Theme.radius
        color: Theme.background
        border.color: (nameInput.activeFocus || folderInput.activeFocus) ? Theme.accent : Theme.border
        Column {
          id: newFileColumn
          anchors.top: parent.top; anchors.topMargin: 12; x: 14; width: parent.width - 28; spacing: 8
          Text { text: "Save as a new file"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13; font.bold: true }
          Row {
            width: parent.width; spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; width: 52; text: "Folder"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 12 }
            Rectangle {
              width: parent.width - 52 - 8 - 96 - 8; height: 32; radius: 4; color: Theme.surfaceRaised; border.color: folderInput.activeFocus ? Theme.accent : Theme.border
              TextInput {
                id: folderInput
                anchors.fill: parent; anchors.margins: 7
                color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 12; clip: true
                selectByMouse: true; selectionColor: Theme.selection; selectedTextColor: Theme.foreground
                Keys.onReturnPressed: root.commitSaveAs()
                Keys.onEscapePressed: root.dismissed()
              }
            }
            ToolButton { icon: "󰉋"; text: "Browse…"; width: 96; height: 32; tooltip: "Pick a folder and name in the system file dialog"; onClicked: root.browse() }
          }
          Row {
            width: parent.width; spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; width: 52; text: "Name"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 12 }
            Rectangle {
              width: parent.width - 52 - 8 - 96 - 8; height: 32; radius: 4; color: Theme.surfaceRaised; border.color: nameInput.activeFocus ? Theme.accent : Theme.border
              TextInput {
                id: nameInput
                anchors.fill: parent; anchors.margins: 7
                color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 12; clip: true
                selectByMouse: true; selectionColor: Theme.selection; selectedTextColor: Theme.foreground
                Keys.onReturnPressed: root.commitSaveAs()
                Keys.onEnterPressed: root.commitSaveAs()
                Keys.onEscapePressed: root.dismissed()
              }
            }
            ToolButton { text: "Save"; active: true; width: 96; height: 32; onClicked: root.commitSaveAs() }
          }
        }
      }
      Text { text: root.message || "Enter saves the new file. Esc cancels."; color: root.message && root.message.indexOf("Choose") !== 0 ? Theme.danger : Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 12; wrapMode: Text.WrapAnywhere; width: parent.width }
    }
  }
}
