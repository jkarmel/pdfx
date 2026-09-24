import QtQuick
import QtQuick.Controls
import Pdfx

// Side panel listing every form field; edits here go through the same
// path as an agent's `fill` request, so both stay in sync.
Rectangle {
  id: root
  property PdfDoc doc: null
  property string flashField: ""
  signal fieldEdited(string name, string value)
  signal jumpTo(string name)
  color: Theme.surface
  border.color: Theme.border

  Column {
    anchors.fill: parent
    anchors.margins: 10
    spacing: 8
    Text {
      text: (root.doc ? root.doc.fields.length : 0) + " form fields"
      color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13; font.bold: true
    }
    Text {
      visible: root.doc && root.doc.fields.length === 0
      width: parent.width
      wrapMode: Text.WordWrap
      text: "This document has no fillable fields. Use Sign and Text to add a signature or type onto the page."
      color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 12
    }
    ListView {
      id: list
      width: parent.width
      height: parent.height - y
      clip: true
      spacing: 6
      model: root.doc ? root.doc.fields : []
      ScrollBar.vertical: ScrollBar {}
      delegate: Rectangle {
        id: row
        required property var modelData
        required property int index
        width: list.width - 8
        height: body.implicitHeight + 16
        radius: Theme.radius
        color: root.flashField === modelData.name ? Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.25) : Theme.background
        border.color: root.flashField === modelData.name ? Theme.warning : Theme.border
        Behavior on color { ColorAnimation { duration: 180 } }
        Column {
          id: body
          x: 8; y: 8
          width: parent.width - 16
          spacing: 4
          Row {
            spacing: 6
            width: parent.width
            Text {
              text: row.modelData.shortName || row.modelData.name
              color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 12; font.bold: true
              elide: Text.ElideMiddle; width: parent.width - kind.width - 6
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.jumpTo(row.modelData.name) }
            }
            Text { id: kind; text: row.modelData.type + "  p" + (row.modelData.page + 1); color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 11 }
          }
          // text editor
          Rectangle {
            visible: row.modelData.type === "text" || (row.modelData.type === "choice" && row.modelData.editable)
            width: parent.width; height: 26
            radius: 4; color: Theme.surfaceRaised; border.color: input.activeFocus ? Theme.accent : Theme.border
            TextInput {
              id: input
              anchors.fill: parent; anchors.margins: 5
              text: row.modelData.value
              color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 12
              clip: true
              readOnly: row.modelData.readOnly
              function commit() { if (text !== row.modelData.value) root.fieldEdited(row.modelData.name, text) }
              Keys.onReturnPressed: commit()
              Keys.onEnterPressed: commit()
              onActiveFocusChanged: if (!activeFocus) commit()
            }
          }
          // checkbox / radio
          Row {
            visible: row.modelData.type === "checkbox" || row.modelData.type === "radio"
            spacing: 8
            Rectangle {
              width: 18; height: 18; radius: row.modelData.type === "radio" ? 9 : 3
              color: row.modelData.value === "true" ? Theme.accent : Theme.surfaceRaised
              border.color: Theme.border
              Text { anchors.centerIn: parent; text: row.modelData.value === "true" ? "✓" : ""; color: Theme.background; font.pixelSize: 13; font.bold: true }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.fieldEdited(row.modelData.name, row.modelData.value === "true" ? "false" : "true") }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: row.modelData.value === "true" ? "checked" : "unchecked"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 12 }
          }
          // choice options
          Flow {
            visible: row.modelData.type === "choice"
            width: parent.width
            spacing: 4
            Repeater {
              model: row.modelData.choices || []
              delegate: Rectangle {
                required property string modelData
                readonly property bool on: row.modelData.value.split(", ").indexOf(modelData) >= 0
                height: 22; width: opt.implicitWidth + 14; radius: 11
                color: on ? Theme.accent : Theme.surfaceRaised; border.color: Theme.border
                Text { id: opt; anchors.centerIn: parent; text: modelData; color: on ? Theme.background : Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 11 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.fieldEdited(row.modelData.name, modelData) }
              }
            }
          }
          Text {
            visible: row.modelData.type === "signature"
            text: "Digital signature field (place a visual signature with Sign)"
            color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 11; wrapMode: Text.WordWrap; width: parent.width
          }
        }
      }
    }
  }
}
