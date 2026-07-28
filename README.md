# PhotoUploader

A native macOS app for managing the photo library at
[rossbower.com/photography](https://rossbower.com). It reads a photo's
metadata, builds the resized images and colour palette, and regenerates the
static site — no external tooling, interpreters, or services involved.

## What it does

- **Imports** photos by drag-and-drop (anywhere in the window, or onto the
  Dock icon) or via a file picker.
- **Extracts** everything ImageIO exposes: camera, lens, exposure, dates and
  GPS. Values are read-only; a checkbox per field chooses what gets published.
  Only the fields the site originally showed are ticked by default.
- **Reverse-geocodes** GPS coordinates so a photo's location can publish as
  raw coordinates, a street address, or a place/business name.
- **Generates** four download tiers (small/medium/large plus a byte-exact copy
  of the original upload) and an adaptive per-photo colour palette that themes
  the photo's page.
- **Writes** the whole static site: `index.html` plus one flat
  `<slug>.html` page per photo.

## The site it edits

The app doesn't contain the website — it edits a *separate* repo
([rossb468/Website](https://github.com/rossb468/Website)) in place, writing to
that repo's `photography/` directory. On first launch it asks for that repo's
root folder and remembers it; use **Change…** in the header to repoint it.

`photography/data/photos.json` is the source of truth. Every save regenerates
all HTML from it, so the generated pages are disposable — never hand-edit them.

## Building

Open `PhotoUploader.xcodeproj` in Xcode and run, or from the command line:

```bash
./build_app.sh
```

That produces a signed, double-clickable `PhotoUploader.app` in the repo root.

## Project layout

The Xcode project is **generated** from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
`build_app.sh` regenerates it automatically, so new source files get picked up
without touching the `.pbxproj` by hand. `project.yml` is the single source of
truth for build settings and the `Info.plist`.

```
Sources/PhotoUploader/
  App/      SwiftUI entry point, app delegate, repo-location prompt
  Models/   photos.json schema + the in-app editing model
  Engine/   EXIF, geocoding, image processing, palette, site generation
  Views/    the library browser and metadata form
```

`Engine/` is plain, UI-free logic; `Views/` holds all the SwiftUI.
