# App Store listing (EN) — OK-ia Markdown Viewer

Secondary App Store language: **English**. Applies to **iOS** and **macOS** (same texts).
Mirror of [`listing-fr.md`](listing-fr.md) — keep both in sync when either changes.
Paste into App Store Connect → *App Information* and *Version*, English localisation.

> Wording note: the app's own English strings avoid US/UK spelling clashes where possible
> (« entity highlighting » rather than colouring/coloring). Keep that habit here.

---

## App name (30 char. max)
**`OK-ia Markdown Viewer`** (21) ✅ — same name in every language, no translation.

> The on-device display name stays **“md Viewer”** (`CFBundleDisplayName`), independent of the
> store name.

## Subtitle (30 char. max)
- `Markdown & Mermaid reader` (25) ✅
- alt: `Offline Markdown reports` (24)

## Promotional text (170 char. — editable without review)
> Open your Markdown files with Mermaid diagrams, Leaflet maps, callouts and entity
> highlighting — faithful to ok-ia.ch, 100% offline.

## Description
```
OK-ia Markdown Viewer displays your Markdown files exactly as the ok-ia.ch viewer does —
same typography, same colours, same rendering pipeline.

FEATURES
• Faithful Markdown rendering (headings, tables, lists, quotes)
• Mermaid diagrams: flowchart, sequence, gantt, pie, mindmap — with full-screen zoom
• Leaflet maps (Obsidian plugin style): positioned markers, CARTO/OSM base maps,
  full-screen button for portrait or landscape navigation
• Obsidian callouts (note, tip, warning, bug…), wiki-links, entity highlighting (NER)
• Document summary by Apple Intelligence — on-device, properly formatted (chapters, bold, lists)
• Chat with the document: ask questions, structured answers grounded in its content alone,
  generated on-device (summary and chat require an Apple Intelligence capable device)
• Siri, Spotlight and Shortcuts: “Open the latest report”, “Summarise a report”…
• Automatic table of contents, in-document search, adjustable text size
• Paginated PDF export (A4 or Letter), Word and PowerPoint; .md file sharing
• Dark mode, portrait and landscape, iPhone + iPad + Mac
• Interface in French, English, German, Spanish and Italian
• 100% offline: rendering, diagrams, callouts and the AI summary need no connection
  (only the map base tiles load online)

Open a .md file from Files, the iOS share sheet, another app, or a web link (mdviewer://).

“What the algorithms still miss.” — ok-ia.ch
```

## Keywords (100 char. max, comma-separated, no stray spaces)
```
markdown,mermaid,diagram,leaflet,map,obsidian,callout,report,summary,ai,pdf,md,viewer,offline
```
(~93 char. — trim if needed; “siri/shortcuts” are indexed through the App Shortcuts phrases)

## URLs
- **Support URL** (required): `https://ok-ia.ch` ✅
- **Marketing URL** (optional): `https://ok-ia.ch`
- **Privacy policy URL** (required): `https://ok-ia.ch/mdviewer/confidentialite.html` ✅
  → the page is French-only for now; acceptable, Apple requires a reachable policy, not a
  translated one.

## Category
- Primary: **`Productivity`** ✅
- Secondary (optional): `Utilities`

## Age rating
- Target: **4+**. Answer “None/Never” to everything.
- ⚠️ Watch out: **“Unrestricted web access”** → answer **No** (the app displays Markdown
  documents, it is not a browser). External links open in Safari / the system browser, which is
  not unrestricted in-app web access.

## Copyright
- **`© 2026 OK-ia`** ✅

## Price
- **Free** ✅ — no limited availability, available in every country.

## What's new in this version (release notes 1.1.0)
```
Five languages, and your reports become conversational.

NEW
• Interface in English, French, German, Spanish and Italian — the app follows
  your device's language, or the one you pick in Settings
• Chat with the document: ask questions about the open report. Answers are
  structured into chapters and draw on its content alone
• The opening screen offers questions taken from the document itself
• Answers are written in the app's language, even when the report is written
  in another
• PDF export on A4 (or Letter, depending on your region): a proper paginated
  document, ready to annotate with the Pencil in Notes or to send on. Maps and
  diagrams appear whole, and no heading is left stranded at the foot of a page

FASTER, CLEARER
• Image-heavy reports appear straight away: images load as you read instead of
  holding up the whole document
• Entity highlighting now works whatever language the report is written in
• Offline, a map says it is unavailable and lists its markers instead of
  showing a grey frame
• Very large documents show a waiting message rather than an empty screen

The summary and the chat require an Apple Intelligence-capable device (iOS 26 or
later). Like the rest of the app, they run on the device: no text is sent
anywhere.
```

<details>
<summary>Archive — release notes 1.0.0</summary>

```
First public release.
• Markdown rendering faithful to ok-ia.ch
• Mermaid diagrams with zoom
• Leaflet maps with full screen
• Callouts, wiki-links, entity highlighting
• Document summary by Apple Intelligence (on-device)
• Siri / Spotlight / Shortcuts actions
• PDF export, search, table of contents
• iPhone, iPad and Mac
```

</details>
