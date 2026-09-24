import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Pdfx
import "qml"

// PDFX — sign and fill PDFs natively on Omarchy. One long-lived process
// hosts every window; `pdfx` (the CLI) talks to it over Quickshell IPC.
ShellRoot {
  id: app
  property int nextId: 1
  property var windows: ({})        // windowId -> PdfxWindow
  property string lastWindowId: ""

  ListModel { id: docs }

  Instantiator {
    model: docs
    delegate: PdfxWindow {
      required property var model
      windowId: model.wid
      filePath: model.path
      workspace: model.workspace
      Component.onCompleted: { var next = app.windows; next[windowId] = this; app.windows = next; app.lastWindowId = windowId }
      onWindowClosed: function(id) { app.forget(id) }
    }
  }

  function forget(id) {
    for (var i = 0; i < docs.count; i++) if (docs.get(i).wid === id) { docs.remove(i); break }
    var next = ({}); for (var k in windows) if (k !== id) next[k] = windows[k]
    windows = next
    if (lastWindowId === id) { lastWindowId = ""; for (var j in windows) lastWindowId = j }
  }

  function open(path, workspace) {
    var id = "w" + nextId++
    docs.append({ wid: id, path: path, workspace: workspace || "" })
    return id
  }

  function resolveWindow(ref) {
    if (!ref || ref === "last") return windows[lastWindowId] || null
    if (windows[ref]) return windows[ref]
    for (var k in windows) {
      var w = windows[k]
      if (w.filePath === ref || w.fileName === ref || w.filePath.indexOf(ref) >= 0) return w
    }
    return null
  }

  function handle(req) {
    var op = req.op
    if (op === "ping") return { ok: true, version: "0.1.1" }
    if (op === "open") {
      if (!req.path) return { ok: false, error: "path is required" }
      var id = open(req.path, req.workspace || "")
      return { ok: true, window: id }
    }
    if (op === "windows") {
      var list = []
      for (var k in windows) list.push(windows[k].info())
      return { ok: true, windows: list }
    }
    if (op === "signatures") return { ok: true, dir: Signatures.dir, signatures: Signatures.items }
    if (op === "signature-create") {
      if (!req.text) return { ok: false, error: "text is required" }
      var name = req.name || req.text
      var created = Signatures.createTyped(name, req.text, req.font || Signatures.defaultFont, null, null)
      return created ? { ok: true, name: Signatures.slug(name), path: Signatures.dir + "/" + Signatures.slug(name) + ".png" } : { ok: false, error: "could not render signature" }
    }
    if (op === "signature-import") {
      if (!req.path) return { ok: false, error: "path is required" }
      Signatures.importImage(req.name || "imported", req.path, null)
      return { ok: true }
    }
    var w = resolveWindow(req.window)
    if (!w) return { ok: false, error: req.window ? "no window " + req.window : "no open windows" }
    w.lastError = ""
    switch (op) {
    case "info": return { ok: true, window: w.info() }
    case "fields": return { ok: true, window: w.windowId, fields: w.doc.fields }
    case "pages": return { ok: true, window: w.windowId, pages: w.doc.pageSizes }
    case "fill": {
      if (!req.fields || typeof req.fields !== "object") return { ok: false, error: "fields must be an object of name: value" }
      var results = w.fill(req.fields)
      var failed = 0; for (var f in results) if (results[f] !== "ok") failed++
      return { ok: failed === 0, results: results }
    }
    case "sign": {
      var sigPath = req.image || Signatures.pathFor(req.signature || "")
      if (!sigPath) {
        if (Signatures.items.length === 1 && !req.signature) sigPath = Signatures.items[0].path
        else return { ok: false, error: "signature not found; pass signature (a saved name) or image (a PNG path)", available: Signatures.items.map(function(s) { return s.name }) }
      }
      var ok = w.placeSignature(req.page || 0, Number(req.x) || 0, Number(req.y) || 0, Number(req.width) || 0.28, sigPath)
      return ok ? { ok: true, added: w.doc.addedAnnotations() } : { ok: false, error: w.lastError || w.doc.error }
    }
    case "text": {
      if (!req.text) return { ok: false, error: "text is required" }
      var okT = w.placeText(req.page || 0, Number(req.x) || 0, Number(req.y) || 0, Number(req.width) || 0, String(req.text), Number(req.size) || 11)
      return okT ? { ok: true, added: w.doc.addedAnnotations() } : { ok: false, error: w.lastError || w.doc.error }
    }
    case "undo": return { ok: w.undo() }
    case "save": {
      var okS = w.save(req.path || "")
      return okS ? { ok: true, path: w.doc.path } : { ok: false, error: w.lastError || w.doc.error }
    }
    case "screenshot": {
      if (!req.path) return { ok: false, error: "path is required" }
      w.screenshot(req.path)
      return { ok: true, path: req.path, note: "written asynchronously" }
    }
    case "save-dialog": { w.openSaveDialog(); return { ok: true } }
    case "sign-dialog": { w.openSignDialog(req.view || "", req.mode || ""); return { ok: true } }
    case "focus": { w.visible = true; return { ok: true } }
    case "close": { w.visible = false; return { ok: true } }
    }
    return { ok: false, error: "unknown op " + op }
  }

  IpcHandler {
    target: "pdfx"
    function request(json: string): string {
      var req
      try { req = JSON.parse(json) } catch (e) { return JSON.stringify({ ok: false, error: "invalid JSON: " + e }) }
      try { return JSON.stringify(app.handle(req)) } catch (e2) { return JSON.stringify({ ok: false, error: String(e2) }) }
    }
    function ping(): string { return "pdfx ok" }
  }
}
