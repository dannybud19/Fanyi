# Fanyi (翻译)

Fanyi is a desktop app for macOS that translates any text you highlight, in any application, without needing to copy-paste it into a separate tool. It lives quietly in the menu bar: highlight text anywhere — a browser, a PDF, a chat app, an editor — double-tap the fn / 🌐 key, and a small floating "island" at the bottom of your screen shows the translation a moment later.

It does not use any AI or language model. Translation is done entirely through Google Translate's free public web endpoint, with no API key or account required.

## Required macOS setting (do this first)

macOS will otherwise intercept the fn double-tap before Fanyi ever sees it:

1. **System Settings → Keyboard → "Press 🌐 key to"** → set to **Do Nothing**.
2. Also in Keyboard settings, check the **Dictation** shortcut isn't set to "Press 🌐 twice." If it is, change it (or turn off that Dictation shortcut).

## Build & install

```
./build.sh install
```

This compiles the app, ad-hoc code-signs it, copies `Fanyi.app` to `/Applications`, resets its Accessibility permission (ad-hoc signatures change every build, which invalidates the old grant), and launches it.

To just build without installing: `./build.sh`.

## First launch

Fanyi will prompt for **Accessibility** access — approve it (or later, via the menu bar icon → "Grant Accessibility access…", which opens System Settings directly to the right pane). This permission is required both to detect the fn double-tap globally and to read selected text from other apps.

**Every rebuild resets this permission** — after each `./build.sh install`, re-approve Accessibility for Fanyi before testing again.

## Using it

1. Highlight text in any app.
2. Double-tap fn.
3. The island appears at the bottom-center of your screen with the translation. Click it to copy the translation. Press Esc, click elsewhere, or double-tap fn again on the same selection to dismiss it early.

Menu bar icon (speech bubble) → choose target language, toggle pinyin display, toggle launch at login, or quit.

## Troubleshooting

- **Hotkey doesn't fire:** check, in order — (1) Accessibility is actually granted (menu bar status line should say "Double-tap fn to translate", not "Grant Accessibility access…"), (2) the Keyboard settings above, (3) that you're doing a clean press-release-press within about a third of a second, not holding fn.
- **Nothing happens on PDF/Preview selections:** Fanyi falls back to a synthesized ⌘C if Accessibility can't read the selection directly; make sure the PDF text is actually selectable (not a scanned image without OCR).
- **Translation fails:** check your network connection; requests time out after 8 seconds.
# Fanyi
