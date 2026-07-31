# Markdown Writer

A native macOS editor for writing Markdown. One file, one window, nothing else.

## Build

Requires macOS 14+ and Xcode 15+.

```sh
./Scripts/make-app.sh          # → build/MarkdownWriter.app
open build/MarkdownWriter.app
```

Or work in Xcode:

```sh
brew install xcodegen
xcodegen generate
open MarkdownWriter.xcodeproj
```

The SwiftPM target alone (`swift build`) produces a bare executable. macOS needs a
bundle for document types and the menu bar, which is what `make-app.sh` assembles.

## Design decisions

**Live preview — no source/preview split.** The document just looks right.
`**bold**` is bold with no asterisks, `# ` is gone and the heading is simply
large, `[label](url)` shows the label, `- ` is a drawn bullet, `- [x]` is a drawn
checkbox, quotes get a margin bar, fenced code gets a panel with its fences
hidden. Put the caret on a line and that line's syntax reappears, so you can edit
it; move away and it dissolves. Obsidian and Typora both work this way.

The buffer is never rewritten. Concealed characters are still in the text
storage — they simply generate no glyphs (`NSLayoutManager.GlyphProperty.null`,
via the layout manager delegate in `WritingTextView`). What you type is exactly
what gets saved, byte for byte.

**Measure over width.** The text column is capped near 68 characters and centered.
Full screen makes the margins wider, not the lines longer — a 27" display with
edge-to-edge text is unreadable, and every serious writing app caps the measure.

**Chrome appears only when sought.** No toolbar, no sidebar, no file browser.
Hidden titlebar; the traffic lights float over the page. A status bar with the
filename, word count and the appearance switch fades in when the pointer reaches
the bottom edge, and it never intercepts clicks meant for the text.

**Serif body, warm neutrals.** New York for prose, SF Mono for code. Backgrounds
are warm off-white and near-black rather than `#FFF`/`#000` — pure white is harsh
over long sessions and pure black crushes antialiasing.

**Three-way appearance.** Auto / Light / Dark, in the status bar and under View →
Appearance. Auto follows the system. Colors are dynamic `NSColor`s, so switching
is an immediate redraw, not a re-parse.

**No substitutions.** Smart quotes, em-dash substitution and autocorrect are all
off. They silently corrupt Markdown source. Spell check stays on.

**One window per file.** Window tabbing is disabled outright, so two documents can
never end up in one window.

## Keys

| | |
|---|---|
| ⌘B / ⌘I | bold / italic (wraps or unwraps the selection) |
| ⌘K | link — caret lands in the URL slot |
| ⇧⌘K | inline code |
| ⇧⌘X | strikethrough |
| ⌘+ / ⌘- / ⌘0 | text size |
| ⌘F | find bar |

## Scope

Deliberately absent: image support, file browser, preview pane, export, themes,
sync.

## Known limits

- **Parsing is regex-based, not CommonMark.** Fenced code, headings, quotes,
  lists, task lists, tables and the usual inline spans are handled. Not handled:
  setext headings (`===` underlines), indented code blocks (ambiguous with
  lists), reference-style link definitions, nested emphasis edge cases. These
  render as plain text — no corruption, just no rendering.
- **Text shifts when the caret enters a line**, because that line's syntax comes
  back. This is inherent to live preview; Obsidian and Typora do the same. It's
  the price of not having a separate preview pane.
- **Concealed characters still occupy caret positions.** Arrowing along a line
  is unaffected, since the line you're on is always revealed. Crossing lines
  vertically can land the caret in hidden syntax on rare occasions.
- **Tables are styled monospace, not laid out as grids.** Real table layout means
  a text attachment per table; the delimiter row stays visible.
- **Every edit re-parses the whole document** and, when the syntax map moves,
  re-lays it out. Fine to roughly 100k characters; beyond that typing latency
  will show. The fix is to scope re-parsing to the edited block and rescan
  fences only.
- **The app is ad-hoc signed.** Fine locally; distribution needs a Developer ID
  and notarization.
