# PDFX

Sign and fill PDFs natively on Omarchy. Poppler renders the pages and writes the
edits, Quickshell draws the windows, and a small CLI lets an agent fill a form
while you watch it happen in the window.

- **Sign**: click a saved signature, click the page. Signatures are typed in one
  of three handwriting fonts or imported as a PNG and stored in `~/.local/share/pdfx/signatures`.
- **Fill**: real AcroForm fields, edited in place on the page or in the side
  panel. Poppler regenerates the field appearance, so the screen shows exactly
  what gets saved.
- **Text**: type anywhere on a page for letters without form fields.
- **Save**: one button. Overwrite the original, or save as a new file beside it
  with a suggested `<name> - signed.pdf` you can edit.
- **Layout**: document actions on top, view controls and status on the bottom,
  page thumbnails on the left, form fields on the right. Side panels fold away
  automatically in narrow tiles and toggle with one click or key.
- **Windows**: as many as you want, each a normal Hyprland window on the
  workspace you asked for. One process hosts them all.
- **Theme**: colors and font follow the active Omarchy theme, live.

## Install

On Omarchy, once the package is published:

```bash
omarchy pkg add pdfx
```

From source (needs `poppler-qt6`, `cmake`, `ninja`, `quickshell`, which Omarchy has):

```bash
bin/build      # compiles the Poppler QML module into build/qml/Pdfx
bin/install    # links ~/.local/bin/pdfx and registers pdfx.desktop
```

Re-run `bin/build` after Qt or Poppler updates. A system install uses
`cmake --install build`, which puts the module on Qt's import path and the app
under `/usr/share/pdfx`.

## Use

```bash
pdfx open form.pdf                  # opens on the workspace of the calling terminal
pdfx open form.pdf --workspace 3    # or a named/numbered workspace
pdfx fields                         # every field with its page-relative rectangle
pdfx fill 'Name=Feeling Great Corporation' 'Agree=true'
pdfx fill --json '{"f1_01[0]": "Jeremy Karmel"}'
pdfx signatures
pdfx signature-create "Jeremy Karmel" --name jeremy --font homemade   # see --help for fonts
pdfx sign --page 1 --x 0.12 --y 0.73 --width 0.25 --signature jeremy
pdfx text "09/24/2026" --page 1 --x 0.66 --y 0.74
pdfx undo
pdfx save                           # in place
pdfx save --to ~/Documents/form-signed.pdf
pdfx screenshot shot.png            # what the user sees, for an agent to check
pdfx windows
```

Coordinates are fractions of the page: `x`, `y` are the top-left corner, `width`
is a fraction of page width, and the signature keeps its aspect ratio. Window
arguments accept an id (`w1`), `last`, or part of the file name.

Every command prints JSON. The app starts on demand and keeps running after
the last window closes; `quickshell kill -p ~/Projects/pdfx/shell.qml` stops it.

## Keys

| Key | Action |
|---|---|
| Ctrl+S | Save (overwrite or new name) |
| Ctrl+Z | Undo last placed signature or text |
| Ctrl+F | Toggle the fields panel |
| Ctrl+T | Toggle page thumbnails |
| PageUp / PageDown | Previous / next page |
| + / − / Ctrl+0 | Zoom (resizes the signature while placing one) |
| Esc | Leave sign/text mode |
| Ctrl+W | Close window |

## Layout

```
shell.qml            Quickshell entry point: window list + `pdfx` IPC target
qml/PdfxWindow.qml   one document window; every IPC op is a function here
qml/PageView.qml     page stack, field overlays, placement tools
qml/FieldsPanel.qml  side panel of form fields
qml/SignaturePicker  choose / create / import signatures
qml/Theme.qml        Omarchy theme colors and font, watched live
src/                 Poppler QML module (PdfDoc, page image provider, PdfxUtil)
bin/pdfx             CLI (Python, stdlib only)
bin/pdfx-place       moves a new window to a Hyprland workspace silently
assets/fonts         OFL script fonts for typed signatures
```

Typed-signature fonts: Homemade Apple (default), La Belle Aurore and Herr Von
Muellerhoff, from Google Fonts under Apache 2.0 and the SIL Open Font License;
see `assets/fonts/README.md`.
