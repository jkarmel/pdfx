import QtQuick
import QtQuick.Controls
import Pdfx

// Scrollable page stack with field overlays and placement tools.
Flickable {
  id: root
  property PdfDoc doc: null
  property real dpr: 1
  property real zoom: 1.0          // device-independent pixels per PDF point
  property bool fitWidth: true
  property string mode: "browse"   // browse | sign | text
  property string signaturePath: ""
  property real signatureWidthFrac: 0.28
  property string flashField: ""
  property string hoverInfo: ""
  signal fieldEdited(string name, string value)
  signal placed()
  signal status(string message)

  readonly property real margin: width < 700 ? 12 : 24
  readonly property real gap: 18
  readonly property real maxPagePoints: {
    var m = 612
    var sizes = doc ? doc.pageSizes : []
    for (var i = 0; i < sizes.length; i++) m = Math.max(m, sizes[i].width)
    return m
  }
  readonly property real effectiveZoom: fitWidth ? Math.max(0.2, (width - margin * 2) / maxPagePoints) : zoom
  onEffectiveZoomChanged: if (!fitWidth) zoom = effectiveZoom
  // Page whose top third is under the viewport's upper part.
  readonly property int currentPage: {
    var probe = contentY + Math.min(height / 3, 200)
    var count = pages.count
    var last = 0
    for (var i = 0; i < count; i++) {
      var item = pages.itemAt(i)
      if (!item) return last
      if (item.y + margin + item.height > probe) return i
      last = i
    }
    return last
  }

  contentWidth: Math.max(width, column.width + margin * 2)
  contentHeight: column.height + margin * 2
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.HorizontalAndVerticalFlick
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
  ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

  function fieldsFor(page) {
    var out = []
    var all = doc ? doc.fields : []
    for (var i = 0; i < all.length; i++) if (all[i].page === page && all[i].visible !== false) out.push(all[i])
    return out
  }
  function pageItem(page) { return pages.itemAt(page) }
  function scrollToPage(page) {
    var item = pages.itemAt(page)
    if (!item) return
    contentY = Math.max(0, Math.min(contentHeight - height, item.y + margin - 12))
  }
  function scrollToField(name) {
    var f = doc ? doc.field(name) : null
    if (!f || f.page === undefined) return
    var item = pages.itemAt(f.page)
    if (!item) return
    var y = item.y + margin + f.y * item.height - height / 3
    contentY = Math.max(0, Math.min(contentHeight - height, y))
    flashField = f.name
    flashTimer.restart()
  }
  function commitEditor() { if (editor.visible) editor.commit() }
  function cancelEditor() { editor.visible = false; editor.fieldName = ""; editor.textMode = false }

  Timer { id: flashTimer; interval: 2200; onTriggered: root.flashField = "" }

  Column {
    id: column
    x: Math.max(root.margin, (root.width - width) / 2)
    y: root.margin
    spacing: root.gap
    Repeater {
      id: pages
      model: root.doc ? root.doc.pageCount : 0
      delegate: Item {
        id: page
        required property int index
        readonly property var size: root.doc.pageSizes[index] || ({width: 612, height: 792})
        width: Math.round(size.width * root.effectiveZoom)
        height: Math.round(size.height * root.effectiveZoom)

        Rectangle { anchors.fill: parent; anchors.margins: -2; anchors.topMargin: 0; color: Qt.rgba(0,0,0,0.28); radius: 3; z: -1 }
        Rectangle { anchors.fill: parent; color: "white" }
        Image {
          id: pageImage
          anchors.fill: parent
          asynchronous: true
          cache: false
          fillMode: Image.Stretch
          smooth: true
          mipmap: false
          sourceSize: Qt.size(Math.round(page.width * root.dpr), Math.round(page.height * root.dpr))
          source: root.doc && root.doc.key ? "image://pdfx/" + root.doc.key + "/" + page.index + "/" + root.doc.revision : ""
        }
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          visible: pageImage.status === Image.Loading && pageImage.progress < 1
          Text { anchors.centerIn: parent; text: "Rendering page " + (page.index + 1) + "…"; color: "#888"; font.family: Theme.fontFamily; font.pixelSize: 13 }
        }

        // Form field overlays
        Repeater {
          model: root.fieldsFor(page.index)
          delegate: Rectangle {
            id: fieldBox
            required property var modelData
            readonly property bool flashing: root.flashField === modelData.name
            x: modelData.x * page.width
            y: modelData.y * page.height
            width: Math.max(4, modelData.width * page.width)
            height: Math.max(4, modelData.height * page.height)
            visible: root.mode === "browse"
            color: flashing ? Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.45)
                 : (fieldMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                 : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, modelData.readOnly ? 0.04 : 0.12))
            border.width: 1
            border.color: flashing ? Theme.warning : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
            radius: 2
            Behavior on color { ColorAnimation { duration: 180 } }
            MouseArea {
              id: fieldMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: fieldBox.modelData.readOnly ? Qt.ArrowCursor : (fieldBox.modelData.type === "text" ? Qt.IBeamCursor : Qt.PointingHandCursor)
              onEntered: root.hoverInfo = fieldBox.modelData.type + "  " + fieldBox.modelData.name + (fieldBox.modelData.value ? "  =  " + fieldBox.modelData.value : "")
              onExited: root.hoverInfo = ""
              onClicked: {
                var f = fieldBox.modelData
                if (f.readOnly) { root.status("Field is read-only"); return }
                if (f.type === "checkbox" || f.type === "radio") {
                  root.fieldEdited(f.name, f.value === "true" ? "false" : "true")
                } else if (f.type === "text") {
                  root.editField(f, page, fieldBox)
                } else if (f.type === "choice") {
                  chooser.open(f, page, fieldBox)
                } else {
                  root.status("Digital signature fields cannot be filled; use Sign to place a visual signature")
                }
              }
            }
          }
        }

        // Placement tools
        MouseArea {
          id: placeArea
          anchors.fill: parent
          hoverEnabled: true
          enabled: root.mode !== "browse"
          visible: enabled
          cursorShape: root.mode === "text" ? Qt.IBeamCursor : Qt.CrossCursor
          onPositionChanged: function(m) { ghost.mx = m.x; ghost.my = m.y }
          onClicked: function(m) {
            if (root.mode === "sign" && root.signaturePath) {
              var w = ghost.width, h = ghost.height
              var rx = (m.x - w / 2) / page.width, ry = (m.y - h / 2) / page.height
              rx = Math.max(0, Math.min(1 - w / page.width, rx)); ry = Math.max(0, Math.min(1 - h / page.height, ry))
              if (root.doc.addImage(page.index, Qt.rect(rx, ry, w / page.width, h / page.height), root.signaturePath)) {
                root.status("Signature placed on page " + (page.index + 1) + " (Ctrl+Z undoes)")
                root.placed()
              } else root.status(root.doc.error)
            } else if (root.mode === "text") {
              root.startText(page, m.x, m.y)
            }
          }
          Image {
            id: ghost
            property real mx: -1000
            property real my: -1000
            visible: root.mode === "sign" && root.signaturePath !== "" && placeArea.containsMouse
            source: root.signaturePath ? "file://" + root.signaturePath : ""
            width: root.signatureWidthFrac * page.width
            height: sourceSize.height > 0 ? width * sourceSize.height / sourceSize.width : width * 0.3
            x: mx - width / 2
            y: my - height / 2
            opacity: 0.85
            fillMode: Image.PreserveAspectFit
          }
        }
      }
    }
  }

  // Inline text editor shared by form fields and the free text tool.
  function editField(f, pageItem, box) {
    editor.fieldName = f.name
    editor.textMode = false
    editor.pageIndex = pageItem.index
    editor.parent = pageItem
    editor.x = box.x; editor.y = box.y; editor.width = box.width; editor.height = box.height
    editor.font.pixelSize = Math.max(9, Math.min(box.height * 0.72, 11 * root.effectiveZoom * 1.35))
    editor.text = f.value
    editor.visible = true
    editor.forceActiveFocus()
    editor.selectAll()
  }
  function startText(pageItem, px, py) {
    editor.fieldName = ""
    editor.textMode = true
    editor.pageIndex = pageItem.index
    editor.parent = pageItem
    var h = 11 * root.effectiveZoom * 1.4
    editor.x = px; editor.y = py - h / 2
    editor.width = Math.max(80, pageItem.width - px - 8); editor.height = h
    editor.font.pixelSize = 11 * root.effectiveZoom
    editor.text = ""
    editor.visible = true
    editor.forceActiveFocus()
  }
  TextInput {
    id: editor
    property string fieldName: ""
    property bool textMode: false
    property int pageIndex: 0
    visible: false
    z: 20
    color: "#111"
    font.family: textMode ? "Helvetica" : Theme.fontFamily
    verticalAlignment: TextInput.AlignVCenter
    leftPadding: 3
    clip: true
    Rectangle { anchors.fill: parent; z: -1; color: "white"; border.color: Theme.accent; border.width: 2; radius: 2 }
    function commit() {
      if (!visible) return
      var value = text
      visible = false
      if (textMode) {
        if (value.trim().length) {
          var pageItem = parent
          var metrics = Qt.createQmlObject('import QtQuick; TextMetrics { }', root)
          metrics.font = editor.font; metrics.text = value
          var wpx = Math.min(pageItem.width - editor.x - 4, metrics.width + 10)
          metrics.destroy()
          var rect = Qt.rect(editor.x / pageItem.width, editor.y / pageItem.height, wpx / pageItem.width, editor.height / pageItem.height)
          if (root.doc.addText(pageIndex, rect, value, 11, "Helvetica")) { root.status("Text added (Ctrl+Z undoes)"); root.placed() }
          else root.status(root.doc.error)
        }
      } else if (fieldName) {
        var f = root.doc.field(fieldName)
        if (f && f.value !== value) root.fieldEdited(fieldName, value)
      }
      fieldName = ""; textMode = false
    }
    Keys.onReturnPressed: commit()
    Keys.onEnterPressed: commit()
    Keys.onTabPressed: commit()
    Keys.onEscapePressed: { root.cancelEditor(); root.status("") }
    onActiveFocusChanged: if (!activeFocus && visible) commit()
  }

  // Choice popup
  Rectangle {
    id: chooser
    property var field: null
    visible: false
    z: 30
    width: 220
    height: Math.min(260, list.contentHeight + 8)
    color: Theme.surfaceRaised
    border.color: Theme.border
    radius: Theme.radius
    function open(f, pageItem, box) {
      field = f
      parent = pageItem
      x = Math.min(box.x, pageItem.width - width - 4)
      y = box.y + box.height + 2
      visible = true
    }
    ListView {
      id: list
      anchors.fill: parent
      anchors.margins: 4
      clip: true
      model: chooser.field ? chooser.field.choices : []
      delegate: Rectangle {
        required property string modelData
        width: list.width
        height: 26
        radius: 4
        color: rowMouse.containsMouse ? Theme.selection : "transparent"
        Text { anchors.verticalCenter: parent.verticalCenter; x: 8; text: modelData; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width - 16 }
        MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { chooser.visible = false; root.fieldEdited(chooser.field.name, modelData) } }
      }
    }
  }
  MouseArea { anchors.fill: parent; z: 25; visible: chooser.visible; onClicked: chooser.visible = false }
}
