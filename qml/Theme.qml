pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Follows the active Omarchy theme: colors from the current theme's
// colors.toml, font from `omarchy font current`. Both are watched so a
// theme switch restyles open windows live.
QtObject {
  id: root
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/current"
  property var palette: ({})
  property string fontFamily: "JetBrainsMono Nerd Font"
  property string scriptDir: Qt.resolvedUrl("../assets/fonts/").toString()

  function pick(key, fallback) { return palette[key] || fallback }
  readonly property color background: pick("background", "#1f2430")
  readonly property color foreground: pick("foreground", "#cccac2")
  readonly property color accent: pick("accent", "#6dcbfa")
  readonly property color selection: pick("selection", "#274364")
  readonly property color muted: pick("color8", "#686868")
  readonly property color danger: pick("color1", "#ed8274")
  readonly property color success: pick("color2", "#87d96c")
  readonly property color warning: pick("color3", "#facc6e")
  readonly property bool dark: background.hslLightness < 0.5
  readonly property color surface: dark ? Qt.lighter(background, 1.25) : Qt.darker(background, 1.06)
  readonly property color surfaceRaised: dark ? Qt.lighter(background, 1.5) : Qt.darker(background, 1.12)
  readonly property color border: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property color canvas: dark ? Qt.darker(background, 1.35) : Qt.darker(background, 1.15)
  readonly property int radius: 6

  function parseToml(text) {
    var out = {}
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*"([^"]*)"/)
      if (m) out[m[1]] = m[2]
    }
    return out
  }

  property FileView colorsFile: FileView {
    path: root.stateDir + "/theme/colors.toml"
    watchChanges: true
    preload: true
    onLoaded: root.palette = root.parseToml(text())
    onFileChanged: reload()
  }
  property Process fontProcess: Process {
    command: ["omarchy", "font", "current"]
    running: true
    stdout: StdioCollector { onStreamFinished: { var f = text.trim(); if (f.length) root.fontFamily = f } }
  }
  property FileView themeNameFile: FileView {
    path: root.stateDir + "/theme.name"
    watchChanges: true
    onFileChanged: { reload(); root.fontProcess.running = true }
  }
}
