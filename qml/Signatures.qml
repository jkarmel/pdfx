pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Pdfx

// Saved signatures are PNG files in ~/.local/share/pdfx/signatures.
// A typed signature is rendered with one of the bundled script fonts.
QtObject {
  id: root
  readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/pdfx/signatures"
  property var items: []   // [{name, path}]
  readonly property var fonts: [
    { id: "homemade", label: "Homemade Apple", file: "HomemadeApple.ttf" },
    { id: "aurore", label: "La Belle Aurore", file: "LaBelleAurore.ttf" },
    { id: "muellerhoff", label: "Herr Von Muellerhoff", file: "HerrVonMuellerhoff.ttf" }
  ]
  property var fontFamilies: ({})
  signal changed()

  readonly property string defaultFont: "homemade"
  function fontFamily(id) { return fontFamilies[id] || fontFamilies[defaultFont] || "serif" }
  function find(name) {
    for (var i = 0; i < items.length; i++) if (items[i].name === name) return items[i]
    return null
  }
  function pathFor(name) { var s = find(name); return s ? s.path : "" }
  function refresh() { lister.running = true }
  function remove(name) {
    var s = find(name)
    if (!s) return false
    remover.command = ["rm", "-f", s.path]
    remover.running = true
    return true
  }
  function slug(name) { return name.trim().replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") }

  function createTyped(name, text, fontId, host, callback) {
    var safe = slug(name)
    if (!safe || !text.trim()) { if (callback) callback(false, "name and text are required"); return }
    var file = ""
    for (var i = 0; i < fonts.length; i++) if (fonts[i].id === fontId || fonts[i].id === defaultFont && !file) file = fonts[i].file
    for (var j = 0; j < fonts.length; j++) if (fonts[j].id === fontId) file = fonts[j].file
    var target = root.dir + "/" + safe + ".png"
    var error = PdfxUtil.renderTypedSignature(text, root.fontSource(file).toString(), target, "#111111")
    root.refresh()
    if (callback) callback(error === "", error === "" ? target : error)
    return error === ""
  }
  function importImage(name, sourcePath, callback) {
    var safe = slug(name)
    if (!safe) { if (callback) callback(false, "name is required"); return }
    importer.command = ["cp", "-f", sourcePath, root.dir + "/" + safe + ".png"]
    importer.callback = callback
    importer.running = true
  }

  property Process mkdir: Process {
    command: ["mkdir", "-p", root.dir]
    running: true
    onExited: root.refresh()
  }
  property Process lister: Process {
    command: ["sh", "-c", "ls -1 \"$1\"/*.png 2>/dev/null", "sh", root.dir]
    stdout: StdioCollector {
      onStreamFinished: {
        var list = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var p = lines[i].trim()
          if (!p) continue
          var base = p.substring(p.lastIndexOf("/") + 1).replace(/\.png$/, "")
          list.push({ name: base, path: p })
        }
        root.items = list
        root.changed()
      }
    }
  }
  property Process remover: Process { onExited: root.refresh() }
  property Process importer: Process {
    property var callback: null
    onExited: function(code) { root.refresh(); if (callback) callback(code === 0, code === 0 ? "" : "copy failed"); callback = null }
  }
  function fontSource(file) { return Qt.resolvedUrl("../assets/fonts/" + file) }
  Component.onCompleted: {
    var map = {}
    for (var i = 0; i < fonts.length; i++) map[fonts[i].id] = PdfxUtil.fontFamilyFor(fontSource(fonts[i].file).toString())
    fontFamilies = map
  }
}
