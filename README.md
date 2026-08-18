# Sottomano

A macOS launcher driven by one leader key.

Press the hotkey and a panel lists the keys available. Each key opens another
layer or runs an action, so a command is a short sequence rather than a
shortcut to remember: `⌘space o z` opens Zed.

- `escape` closes the panel, `delete` goes back one layer.
- The bindings live in `~/.config/sottomano/keymap.json`. See
  `keymap.example.json`.

## Build

```sh
make run
```

Requires a Swift toolchain from Xcode or the Command Line Tools.
