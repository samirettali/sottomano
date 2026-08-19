# Sottomano

A macOS launcher driven by one leader key.

Press ⌘space and a panel lists the keys available. Each key opens another layer,
opens something to search in, or acts and is done — so a command is a short
sequence rather than a shortcut to remember: `⌘space o` for the applications,
`⌘space c` for the clipboard, `⌘space v p` for a password.

- `escape` closes the panel, `delete` goes back one layer.
- Everything is declared in `~/.config/sottomano/keymap.json`, which is read
  again whenever it is written. See `keymap.example.json`.

## What it does

- **Launch**, open a URL, run a command, type a snippet.
- **Search** in a list a command prints, with fuzzy matching and frecency: the
  applications, the emoji, your bookmarks, your playlists, your password
  manager. A list can name a picture for each row — a playlist cover, a favicon
  — and only the rows on screen are fetched.
- **Walk the filesystem** from the keyboard: the query filters where you are
  standing, return goes in, delete comes back out.
- **A clipboard history** that keeps text, pictures and files, skips whatever a
  password manager marks as concealed, and pastes a file back as a file.
- **Ask for a query** and open it in whichever search engine, or search
  whatever is selected without being asked.
- **Rearrange the displays**, cycle the keyboard layout, and make caps lock send
  escape when tapped on its own while staying control when held.

## Install

```sh
brew install --cask samirettali/tap/sottomano
```

Or build it: `make run` needs a Swift toolchain from Xcode or the Command Line
Tools.

## Why it is not Hammerspoon

It replaces a Hammerspoon setup that did the same things. The panel there was
drawn by an event tap, and macOS stops delivering events to a tap while Secure
Input is held — exactly when a password field has the focus — so the launcher
had to hand the focus to the Finder for the duration of a modal.

Here the panel is an `NSPanel` that becomes key and reads `NSEvent` directly:
no tap, and nothing to launder the focus through. The hotkey is
`RegisterEventHotKey`, which is not a tap either. Typing a snippet is the one
thing that needs Accessibility, and the caps lock tap the one thing that stops
under Secure Input.

The whole panel lands within a frame.

## Licence

MIT.
