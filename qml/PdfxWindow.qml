import QtQuick
import Quickshell
import Quickshell.Io
import Pdfx

// One PDF window. Document actions live in the top bar, view controls and
// status in the bottom bar, page thumbnails on the left, form fields on the
// right. Every IPC op is a function here; the bars call the same functions.
FloatingWindow {
  id: win
  required property string windowId
  required property string filePath
  property string workspace: ""
  property bool placed: workspace === ""
  property string placementToken: "pdfx#" + windowId
  property string statusText: ""
  property string lastError: ""
  property bool showFields: false
  property bool showThumbs: false
  property bool userSetFields: false
  property bool userSetThumbs: false
  readonly property bool compact: width < 700
  readonly property bool narrow: width < 980
  signal windowClosed(string windowId)

  readonly property string fileName: filePath.substring(filePath.lastIndexOf("/") + 1)
  title: placed ? (fileName + (doc.modified ? " •" : "") + " — PDFX") : placementToken
  implicitWidth: Quickshell.env("PDFX_TEST_WIDTH") ? Number(Quickshell.env("PDFX_TEST_WIDTH")) : 1180
  implicitHeight: Quickshell.env("PDFX_TEST_HEIGHT") ? Number(Quickshell.env("PDFX_TEST_HEIGHT")) : 900
  color: Theme.canvas

  PdfDoc { id: doc }
  property alias doc: doc

  Component.onCompleted: {
    if (!doc.load(filePath)) { statusText = doc.error; lastError = doc.error }
    else statusText = doc.pageCount + " page" + (doc.pageCount === 1 ? "" : "s") + ", " + doc.fields.length + " form field" + (doc.fields.length === 1 ? "" : "s")
    showFields = doc.fields.length > 0 && !narrow
    showThumbs = doc.pageCount > 1 && !narrow
    if (workspace !== "") placer.running = true
  }
  onVisibleChanged: if (!visible) win.windowClosed(windowId)
  // Panels fold away when the tile gets narrow unless the user pinned them.
  onNarrowChanged: {
    if (!userSetFields) showFields = doc.fields.length > 0 && !narrow
    if (!userSetThumbs) showThumbs = doc.pageCount > 1 && !narrow
  }

  Process {
    id: placer
    command: [Qt.resolvedUrl("../bin/pdfx-place").toString().replace(/^file:\/\//, ""), win.placementToken, win.workspace]
    onExited: win.placed = true
  }
  Timer { interval: 6000; running: win.workspace !== "" && !win.placed; onTriggered: win.placed = true }

  // ------------------------------------------------------------ actions
  function setStatus(message) { statusText = message; statusTimer.restart() }
  Timer { id: statusTimer; interval: 5000; onTriggered: if (!doc.error) statusText = "" }

  function fill(map) {
    var results = {}
    var okCount = 0
    var lastName = ""
    for (var name in map) {
      var ok = doc.setField(name, String(map[name]))
      results[name] = ok ? "ok" : doc.error
      if (ok) { okCount++; lastName = name }
    }
    if (lastName) { pageView.scrollToField(doc.field(lastName).name); panel.flashField = doc.field(lastName).name; panelFlash.restart() }
    setStatus(okCount + " field" + (okCount === 1 ? "" : "s") + " filled")
    return results
  }
  Timer { id: panelFlash; interval: 2200; onTriggered: panel.flashField = "" }

  function placeSignature(page, x, y, widthFrac, imagePath) {
    var info = PdfxUtil.imageInfo(imagePath)
    if (!info.width) { lastError = "Cannot read " + imagePath; return false }
    var size = doc.pageSizes[page]
    if (!size) { lastError = "No page " + (page + 1); return false }
    var wPt = widthFrac * size.width
    var hPt = wPt * info.height / info.width
    var ok = doc.addImage(page, Qt.rect(x, y, wPt / size.width, hPt / size.height), imagePath)
    if (ok) { pageView.scrollToPage(page); setStatus("Signature placed on page " + (page + 1)) } else lastError = doc.error
    return ok
  }
  function placeText(page, x, y, widthFrac, text, pointSize) {
    var size = doc.pageSizes[page]
    if (!size) { lastError = "No page " + (page + 1); return false }
    var pt = pointSize > 0 ? pointSize : 11
    var hFrac = (pt * 1.4) / size.height
    var wFrac = widthFrac > 0 ? widthFrac : Math.min(1 - x, (text.length * pt * 0.55 + 8) / size.width)
    var ok = doc.addText(page, Qt.rect(x, y, wFrac, hFrac), text, pt, "Helvetica")
    if (ok) { pageView.scrollToPage(page); setStatus("Text added on page " + (page + 1)) } else lastError = doc.error
    return ok
  }
  function undo() {
    var ok = doc.removeLastAnnotation()
    setStatus(ok ? "Removed last placed item" : "Nothing to undo")
    return ok
  }
  function save(path) {
    pageView.commitEditor()
    var ok = doc.save(path || "")
    if (ok) setStatus("Saved " + doc.path); else { lastError = doc.error; setStatus(doc.error) }
    return ok
  }
  function suggestedName() {
    var name = fileName.replace(/\.pdf$/i, "")
    return (/ - signed$/i.test(name) ? name : name + " - signed") + ".pdf"
  }
  function openSaveDialog() { pageView.commitEditor(); saveDialog.visible = true }
  function screenshot(path) { return content.grabToImage(function(result) { result.saveToFile(path) }) }
  function startSign() { picker.visible = true }
  function openSignDialog(view, mode) {
    picker.visible = true
    if (view) picker.view = view
    if (mode) picker.createMode = mode
  }
  function useSignature(path) {
    picker.visible = false
    pageView.signaturePath = path
    pageView.mode = "sign"
    var name = path.substring(path.lastIndexOf("/") + 1).replace(/\.png$/, "")
    setStatus("Signing with " + name + ": click where it goes. + and − resize it, Esc cancels.")
  }
  function toggleText() {
    pageView.mode = pageView.mode === "text" ? "browse" : "text"
    setStatus(pageView.mode === "text" ? "Click on the page and type. Enter commits, Esc cancels." : "")
  }
  function browse() { pageView.mode = "browse"; pageView.cancelEditor() }
  function toggleFields() { userSetFields = true; showFields = !showFields }
  function toggleThumbs() { userSetThumbs = true; showThumbs = !showThumbs }
  function zoomIn() { pageView.fitWidth = false; pageView.zoom = pageView.zoom * 1.15 }
  function zoomOut() { pageView.fitWidth = false; pageView.zoom = pageView.zoom / 1.15 }
  function info() {
    return { id: windowId, path: doc.path, pages: doc.pageCount, page: pageView.currentPage + 1, fields: doc.fields.length, modified: doc.modified,
             workspace: workspace, revision: doc.revision, added: doc.addedAnnotationCount(), width: width, height: height, error: doc.error }
  }

  // ------------------------------------------------------------ layout
  Rectangle {
    id: content
    anchors.fill: parent
    color: Theme.canvas
    focus: true
    Keys.onPressed: function(e) {
      var ctrl = e.modifiers & Qt.ControlModifier
      if (e.key === Qt.Key_Escape) { win.browse(); picker.visible = false; saveDialog.visible = false; e.accepted = true }
      else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) {
        if (pageView.mode === "sign") pageView.signatureWidthFrac = Math.min(0.9, pageView.signatureWidthFrac * 1.1); else win.zoomIn()
        e.accepted = true
      } else if (e.key === Qt.Key_Minus) {
        if (pageView.mode === "sign") pageView.signatureWidthFrac = Math.max(0.05, pageView.signatureWidthFrac / 1.1); else win.zoomOut()
        e.accepted = true
      } else if (e.key === Qt.Key_0 && ctrl) { pageView.fitWidth = true; e.accepted = true }
      else if (e.key === Qt.Key_S && ctrl) { win.openSaveDialog(); e.accepted = true }
      else if (e.key === Qt.Key_Z && ctrl) { win.undo(); e.accepted = true }
      else if (e.key === Qt.Key_F && ctrl) { win.toggleFields(); e.accepted = true }
      else if (e.key === Qt.Key_T && ctrl) { win.toggleThumbs(); e.accepted = true }
      else if (e.key === Qt.Key_W && ctrl) { win.visible = false; e.accepted = true }
      else if (e.key === Qt.Key_PageDown) { pageView.scrollToPage(Math.min(doc.pageCount - 1, pageView.currentPage + 1)); e.accepted = true }
      else if (e.key === Qt.Key_PageUp) { pageView.scrollToPage(Math.max(0, pageView.currentPage - 1)); e.accepted = true }
    }

    // Top bar: things that change the document.
    Rectangle {
      id: topBar
      anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
      height: 42
      z: 10   // tooltips overflow the bar and must draw over the page
      color: Theme.surface
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
      Row {
        id: actions
        anchors.verticalCenter: parent.verticalCenter
        x: 8
        spacing: 4
        ToolButton { icon: "󰏫"; text: "Sign"; compact: win.compact; active: pageView.mode === "sign"; tooltip: "Place a saved signature"; onClicked: pageView.mode === "sign" ? win.browse() : win.startSign() }
        ToolButton { icon: "󰊄"; text: "Text"; compact: win.compact; active: pageView.mode === "text"; tooltip: "Type onto the page"; onClicked: win.toggleText() }
        ToolButton { icon: "󰕌"; text: "Undo"; compact: win.compact; enabled: doc.addedCount > 0; tooltip: "Remove the last placed item (Ctrl+Z)"; onClicked: win.undo() }
        Item { width: 6; height: 1 }
        Rectangle { width: 1; height: 22; color: Theme.border; anchors.verticalCenter: parent.verticalCenter }
        Item { width: 6; height: 1 }
        ToolButton { icon: "󰆓"; text: "Save"; compact: win.compact; tooltip: "Overwrite the original or save as a new file (Ctrl+S)"; onClicked: win.openSaveDialog() }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.left: actions.right
        anchors.leftMargin: 16
        horizontalAlignment: Text.AlignRight
        text: win.fileName + (doc.modified ? "  •" : "")
        visible: width > 80
        color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 12; elide: Text.ElideMiddle
      }
    }

    Thumbnails {
      id: thumbs
      anchors.top: topBar.bottom
      anchors.bottom: bottomBar.top
      anchors.left: parent.left
      width: win.showThumbs ? Math.min(150, Math.max(96, win.width * 0.16)) : 0
      visible: win.showThumbs
      doc: doc
      dpr: win.screen ? win.screen.devicePixelRatio : 1
      currentPage: pageView.currentPage
      onPageChosen: function(page) { pageView.scrollToPage(page) }
    }

    PageView {
      id: pageView
      anchors.top: topBar.bottom
      anchors.bottom: bottomBar.top
      anchors.left: thumbs.right
      anchors.right: panel.left
      doc: doc
      dpr: win.screen ? win.screen.devicePixelRatio : 1
      onFieldEdited: function(name, value) { if (!doc.setField(name, value)) win.setStatus(doc.error) }
      onPlaced: pageView.mode = "browse"
      onStatus: function(message) { win.setStatus(message) }
    }

    FieldsPanel {
      id: panel
      anchors.top: topBar.bottom
      anchors.bottom: bottomBar.top
      anchors.right: parent.right
      width: win.showFields ? Math.min(300, Math.max(200, win.width * 0.3)) : 0
      visible: win.showFields
      doc: doc
      onFieldEdited: function(name, value) { if (!doc.setField(name, value)) win.setStatus(doc.error) }
      onJumpTo: function(name) { pageView.scrollToField(name) }
    }

    // Bottom bar: view controls and status.
    Rectangle {
      id: bottomBar
      anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
      height: 36
      z: 10
      color: Theme.surface
      Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.border }
      Row {
        id: viewControls
        anchors.verticalCenter: parent.verticalCenter
        x: 8
        spacing: 4
        ToolButton { tipAbove: true; icon: "󰕰"; text: "Pages"; compact: win.compact; active: win.showThumbs; enabled: doc.pageCount > 1; tooltip: "Page thumbnails (Ctrl+T)"; onClicked: win.toggleThumbs() }
        ToolButton { tipAbove: true; icon: "󰈙"; text: "Fields"; compact: win.compact; active: win.showFields; enabled: doc.fields.length > 0; tooltip: doc.fields.length > 0 ? "Form fields (Ctrl+F)" : "No form fields in this document"; onClicked: win.toggleFields() }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: viewControls.right
        anchors.leftMargin: 14
        anchors.right: zoomControls.left
        anchors.rightMargin: 14
        text: pageView.hoverInfo || win.statusText
        visible: width > 60
        color: doc.error ? Theme.danger : Theme.muted
        font.family: Theme.fontFamily; font.pixelSize: 12; elide: Text.ElideRight
      }
      Row {
        id: zoomControls
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 8
        spacing: 4
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: doc.pageCount > 1
          text: (pageView.currentPage + 1) + " / " + doc.pageCount
          color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 12
          rightPadding: 8
        }
        ToolButton { tipAbove: true; icon: "󰍴"; compact: true; tooltip: "Zoom out (−)"; onClicked: win.zoomOut() }
        ToolButton {
          tipAbove: true
          text: pageView.fitWidth ? "Fit" : Math.round(pageView.effectiveZoom * 100 / 1.333) + "%"
          active: pageView.fitWidth; tooltip: "Fit page width (Ctrl+0)"; onClicked: pageView.fitWidth = true
          implicitWidth: 52
        }
        ToolButton { tipAbove: true; icon: "󰐕"; compact: true; tooltip: "Zoom in (+)"; onClicked: win.zoomIn() }
      }
    }

    SaveDialog {
      id: saveDialog
      visible: false
      originalPath: doc.path
      suggestedName: win.suggestedName()
      onOverwrite: { visible = false; win.save("") }
      onSaveAs: function(path) { visible = false; win.save(path) }
      onDismissed: visible = false
    }

    SignaturePicker {
      id: picker
      visible: false
      onChosen: function(path) { win.useSignature(path) }
      onDismissed: visible = false
    }
  }
}
