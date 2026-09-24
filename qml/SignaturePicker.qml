import QtQuick

// Sign dialog. First view: saved signatures, click one to place it, or Add new.
// Second view: create by typing, drawing, or importing a PNG.
Rectangle {
  id: root
  signal chosen(string path)
  signal dismissed()
  property string message: ""
  property string view: "saved"        // saved | create
  property string createMode: "type"   // type | draw | import
  property string newFont: Signatures.defaultFont
  anchors.fill: parent
  color: Qt.rgba(0, 0, 0, 0.45)
  z: 100
  MouseArea { anchors.fill: parent; onClicked: root.dismissed() }

  onVisibleChanged: {
    if (!visible) return
    message = ""
    view = Signatures.items.length === 0 ? "create" : "saved"
    canvas.clear()
    Qt.callLater(function() { if (view === "create") nameInput.forceActiveFocus() })
  }

  function finish(ok, info, name) {
    if (!ok) { message = info; return }
    message = ""
    var s = Signatures.find(name)
    if (s) root.chosen(s.path); else view = "saved"
  }
  function createTyped() {
    var text = typeInput.text.trim()
    if (!text) { message = "Type the name to sign with."; return }
    var name = nameInput.text.trim() || text
    Signatures.createTyped(name, text, root.newFont, null, function(ok, info) { root.finish(ok, info, Signatures.slug(name)) })
  }
  function createDrawn() {
    if (canvas.strokes.length === 0) { message = "Draw your signature first."; return }
    var name = nameInput.text.trim() || ("drawn-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss"))
    var target = Signatures.dir + "/" + Signatures.slug(name) + ".png"
    canvas.grabToImage(function(result) {
      if (!result.saveToFile(target)) { message = "Could not write " + target; return }
      var error = PdfxUtil.trimTransparent(target, 24)
      Signatures.refresh()
      if (error) { message = error; return }
      // refresh() lists asynchronously; hand the path over directly.
      canvas.clear()
      root.chosen(target)
    }, Qt.size(canvas.width * 3, canvas.height * 3))
  }
  function createImported() {
    var path = pathInput.text.trim()
    if (!path) { message = "Enter the path of a PNG."; return }
    var name = nameInput.text.trim() || "imported"
    Signatures.importImage(name, path, function(ok, info) { root.finish(ok, info, Signatures.slug(name)) })
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - 32, 640)
    height: Math.min(parent.height - 32, body.implicitHeight + 40)
    radius: Theme.radius + 2
    color: Theme.surface
    border.color: Theme.border
    MouseArea { anchors.fill: parent }
    Keys.onEscapePressed: root.dismissed()

    Flickable {
      anchors.fill: parent
      anchors.margins: 20
      contentHeight: body.implicitHeight
      clip: true
      Column {
        id: body
        width: parent.width
        spacing: 14

        // ------------------------------------------------------- header
        Item {
          width: parent.width; height: 30
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.view === "saved" ? "Sign with" : "New signature"
            color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 16; font.bold: true
          }
          ToolButton {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            visible: root.view === "saved"
            icon: "󰐕"; text: "Add new"; active: true
            onClicked: { root.view = "create"; root.message = ""; nameInput.forceActiveFocus() }
          }
          ToolButton {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            visible: root.view === "create" && Signatures.items.length > 0
            icon: "󰁍"; text: "Saved"
            onClicked: { root.view = "saved"; root.message = "" }
          }
        }

        // ------------------------------------------------------- saved
        Flow {
          visible: root.view === "saved"
          width: parent.width
          spacing: 10
          Repeater {
            model: Signatures.items
            delegate: Rectangle {
              required property var modelData
              width: 190; height: 96
              radius: Theme.radius
              color: "white"
              border.color: sigMouse.containsMouse ? Theme.accent : Theme.border
              border.width: sigMouse.containsMouse ? 2 : 1
              Image { anchors.fill: parent; anchors.margins: 8; anchors.bottomMargin: 26; source: "file://" + parent.modelData.path; fillMode: Image.PreserveAspectFit; cache: false }
              Text { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.margins: 6; text: parent.modelData.name; color: "#333"; font.family: Theme.fontFamily; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width - 40 }
              Text {
                anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 6
                text: "✕"; color: "#999"; font.pixelSize: 12
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: Signatures.remove(parent.parent.modelData.name) }
              }
              MouseArea { id: sigMouse; anchors.fill: parent; anchors.bottomMargin: 26; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.chosen(parent.modelData.path) }
            }
          }
        }
        Text {
          visible: root.view === "saved"
          width: parent.width; wrapMode: Text.WordWrap
          text: "Click a signature, then click where it goes on the page."
          color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 12
        }

        // ------------------------------------------------------- create
        Row {
          visible: root.view === "create"
          spacing: 6
          ToolButton { icon: "󰊄"; text: "Type"; active: root.createMode === "type"; onClicked: { root.createMode = "type"; typeInput.forceActiveFocus() } }
          ToolButton { icon: "󰏫"; text: "Draw"; active: root.createMode === "draw"; onClicked: root.createMode = "draw" }
          ToolButton { icon: "󰋩"; text: "Import PNG"; active: root.createMode === "import"; onClicked: { root.createMode = "import"; pathInput.forceActiveFocus() } }
        }

        // name (label) shared by all modes
        Row {
          visible: root.view === "create"
          spacing: 8
          width: parent.width
          Text { anchors.verticalCenter: parent.verticalCenter; text: "Save as"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 12 }
          Rectangle {
            width: 220; height: 30; radius: 4; color: Theme.surfaceRaised; border.color: nameInput.activeFocus ? Theme.accent : Theme.border
            TextInput { id: nameInput; anchors.fill: parent; anchors.margins: 6; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 12; clip: true
              Text { visible: !parent.text; text: root.createMode === "type" ? "label (defaults to the name)" : "label"; color: Theme.muted; font: parent.font } }
          }
        }

        // type
        Column {
          visible: root.view === "create" && root.createMode === "type"
          width: parent.width
          spacing: 10
          Row {
            spacing: 8
            width: parent.width
            Rectangle {
              width: parent.width - 100; height: 34; radius: 4; color: Theme.surfaceRaised; border.color: typeInput.activeFocus ? Theme.accent : Theme.border
              TextInput { id: typeInput; anchors.fill: parent; anchors.margins: 8; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 14; clip: true
                Text { visible: !parent.text; text: "Your name as you'd sign it"; color: Theme.muted; font: parent.font }
                Keys.onReturnPressed: root.createTyped() }
            }
            ToolButton { text: "Create"; active: true; width: 92; height: 34; onClicked: root.createTyped() }
          }
          Flow {
            width: parent.width
            spacing: 6
            Repeater {
              model: Signatures.fonts
              delegate: Rectangle {
                required property var modelData
                readonly property bool on: root.newFont === modelData.id
                width: sample.implicitWidth + 24; height: 44; radius: Theme.radius
                color: on ? Theme.accent : Theme.surfaceRaised
                border.color: on ? Theme.accent : Theme.border
                Text {
                  id: sample
                  anchors.centerIn: parent
                  text: typeInput.text || "Jeremy Karmel"
                  color: on ? Theme.background : Theme.foreground
                  font.family: Signatures.fontFamily(modelData.id)
                  font.pixelSize: 24
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.newFont = modelData.id }
              }
            }
          }
        }

        // draw
        Column {
          visible: root.view === "create" && root.createMode === "draw"
          width: parent.width
          spacing: 8
          Rectangle {
            width: parent.width; height: 220; radius: Theme.radius
            color: "white"; border.color: Theme.border
            Rectangle { x: 24; y: parent.height - 56; width: parent.width - 48; height: 1; color: "#c8c8c8" }
            Text { visible: canvas.strokes.length === 0; anchors.centerIn: parent; text: "Sign here with the mouse or a pen"; color: "#b0b0b0"; font.family: Theme.fontFamily; font.pixelSize: 13 }
            Canvas {
              id: canvas
              anchors.fill: parent
              property var strokes: []
              property var current: null
              function clear() { strokes = []; current = null; requestPaint() }
              onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = "#101010"; ctx.lineWidth = 3.2; ctx.lineCap = "round"; ctx.lineJoin = "round"
                var all = strokes.slice(); if (current) all.push(current)
                for (var s = 0; s < all.length; s++) {
                  var pts = all[s]
                  if (pts.length === 1) { ctx.beginPath(); ctx.arc(pts[0].x, pts[0].y, 1.6, 0, Math.PI * 2); ctx.fillStyle = "#101010"; ctx.fill(); continue }
                  ctx.beginPath(); ctx.moveTo(pts[0].x, pts[0].y)
                  for (var i = 1; i < pts.length - 1; i++) {
                    var mx = (pts[i].x + pts[i + 1].x) / 2, my = (pts[i].y + pts[i + 1].y) / 2
                    ctx.quadraticCurveTo(pts[i].x, pts[i].y, mx, my)
                  }
                  ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y)
                  ctx.stroke()
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                onPressed: function(m) { canvas.current = [{x: m.x, y: m.y}]; canvas.requestPaint() }
                onPositionChanged: function(m) { if (canvas.current) { canvas.current.push({x: m.x, y: m.y}); canvas.requestPaint() } }
                onReleased: { if (canvas.current) { var next = canvas.strokes.slice(); next.push(canvas.current); canvas.strokes = next; canvas.current = null; canvas.requestPaint() } }
              }
            }
          }
          Row {
            spacing: 8
            ToolButton { text: "Create"; active: true; width: 92; height: 34; enabled: canvas.strokes.length > 0; onClicked: root.createDrawn() }
            ToolButton { icon: "󰕌"; text: "Undo stroke"; enabled: canvas.strokes.length > 0; onClicked: { var next = canvas.strokes.slice(); next.pop(); canvas.strokes = next; canvas.requestPaint() } }
            ToolButton { text: "Clear"; enabled: canvas.strokes.length > 0; onClicked: canvas.clear() }
          }
        }

        // import
        Row {
          visible: root.view === "create" && root.createMode === "import"
          spacing: 8
          width: parent.width
          Rectangle {
            width: parent.width - 100; height: 34; radius: 4; color: Theme.surfaceRaised; border.color: pathInput.activeFocus ? Theme.accent : Theme.border
            TextInput { id: pathInput; anchors.fill: parent; anchors.margins: 8; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 12; clip: true
              Text { visible: !parent.text; text: "/path/to/signature.png (transparent background works best)"; color: Theme.muted; font: parent.font }
              Keys.onReturnPressed: root.createImported() }
          }
          ToolButton { text: "Import"; active: true; width: 92; height: 34; onClicked: root.createImported() }
        }

        Text { visible: root.message.length > 0; text: root.message; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: 12; wrapMode: Text.WrapAnywhere; width: parent.width }
      }
    }
  }
}
