# Sottomano

macOS launcher: a leader key opens a panel of single-key bindings, and each key
either opens another layer or runs an action. It replaces the Hammerspoon
RecursiveBinder setup in `dotfiles`, which is where the design of the panel
comes from.

Bundle id `com.samirettali.sottomano`. `LSUIElement`, so no Dock icon and no
menu bar item: the hotkey is the whole interface.

## Build & run

Plain SwiftPM, no Xcode project, following Pulse:

- `make bundle` assembles `dist/Sottomano.app`, `make run` also launches it,
  `make dev` builds unoptimised.
- `Packaging/Info.plist` is copied in by the Makefile. `LSUIElement` lives
  there, so a bare `swift run` binary is not the shipped app.
- `run` kills the running copy first. Two instances mean two hotkey
  registrations and the second one loses.

`make release` signs and notarises the app and DMG locally; follow the
`macos-app-release` skill. Publishing a GitHub release updates the Homebrew cask
and dispatches NUR's `update.yml` with `only=sottomano`. `NUR_DISPATCH_TOKEN` is
managed in `infra/github/secrets.tf`; without it, NUR's daily update is the fallback.
Dotfiles already installs `nurPkgs.sottomano`; its NUR input must be updated after
the package update PR merges.

## Why native, and what it buys

Hammerspoon drove the panel with a `hs.eventtap`, and macOS stops delivering
events to a tap while Secure Input is held — which is exactly when a password
field has the focus. `modal_focus.lua` worked around it by handing focus to the
Finder for the duration of the modal.

Here the panel is an `NSPanel` that becomes key and reads `NSEvent` directly, so
there is no tap, no Accessibility permission, and nothing to launder the focus
through. The hotkey is `RegisterEventHotKey`, a Carbon API that is not a tap
either.

Putting text into the focused window is the one action that needs Accessibility:
posting a synthetic event is privileged either way. Everything else — launching,
opening a URL, running a command, rearranging the displays — asks for nothing.

It is a synthetic ⌘V, not a key event per character. Typing was tried first and
kept the pasteboard out of it, but a long entry took a visible age, and an
application that reads the field while it fills saw a hundred half-written
states. So the text is lent to the pasteboard, marked
`org.nspasteboard.ConcealedType` in case a password from the vault goes through
it, and what was there is put back a quarter of a second later — a picture or a
file already on the pasteboard is not put back, since there is nothing to
restore it from. The watcher is paused for the length of it, so the history does
not gain a copy of what was just pasted out of it.

The panel takes keys and the whole thing lands within a frame, against the
three or four Hammerspoon needed.

`NSApp.activate()` on show is not optional, and neither is activating the
previous application on hide: nothing gives the focus back on its own, and a
typed action would otherwise land in a window that had already gone. Activation
is asynchronous — reading `isKeyWindow` on the line after it still says false.

`KeyPanel` overrides `canBecomeKey`, since a borderless window refuses by
default. Without it the panel could never resign key either, which is what
closing on a click outside relies on.

## What it covers

Launches, the filesystem, the clipboard history, emoji, linkding bookmarks,
spotctl playlists, the paste entries, the query layer (with shift searching the
selection), the rbw vault and the three monitor arrangements. The applications
picker, the layout toggle and the Spotify transport keys keep their own bindings
through `hotkeys`.

The tree is deliberately shallow: everything reachable in two keys, one layer at
most. The clipboard transforms lived here until they were removed for going
unused — `git log -- Sources/Sottomano/Transform.swift` has them.

`controlBracketEscape` is an independent, default-off Control+[ → Escape option.
It shares the `CapsEscape` tap, rewriting the physical bracket key's down,
repeat and up events to unmodified Escape. Both options reload with the keymap;
the tap stays alive after disabling them to finish an in-flight key release.
See [Escape mappings](README.md#escape-mappings) for configuration and limits.

**A secret never goes through the pasteboard.** A pick with `secret` types
what `typeOutput` answers as key events carrying the characters — twenty per
event, which the system caps, so a password is two or three events landing
whole rather than one per character. `copyOutput` is the other verb of the
same row, shift+return: the output goes on the pasteboard marked concealed,
so the history here and any other manager let it pass. Neither `pbcopy` nor
the browser extensions write that marker: `pbconceal` in dotfiles does for
the shell, and Chromium's `org.chromium.source-url` — a `chrome-extension://`
page for an extension — is matched against the ids of the known managers
for the browser. A row that got in anyway leaves with ⌘⌫.

**The history is sealed at rest.** `clipboard.enc` is the JSON run through
AES-GCM with a key the keychain holds, made once by the signed app, so the
file on its own says nothing and the key never sits beside it. Pictures and
thumbnails are not sealed: what leaks is text. Writes are atomic, since a
crash halfway through would leave a file that no longer opens.

The text lent to the pasteboard by a paste is put back only if the change
count is still the one the loan had: a copy made in the meantime has already
taken the loan off, and writing the old text over it would lose the copy.

`capsEscape` carries what ControlEscape.spoon did: control released with nothing
else pressed sends escape, control with another key stays control. There is no
duration threshold, because duration says nothing — a tap is a tap however slow
it was. Both mappings need Accessibility and stop under Secure Input; a toast
reports when the permission is missing.

**Development builds are signed with the Developer ID, not ad-hoc.** An ad-hoc
signature changes with every build, so TCC treats each build as a new
application and the Accessibility grant silently stops applying while the
toggle in System Settings still reads as on.

Left in Hammerspoon: the window tiling fallbacks in `bindings.lua`, which only
run on a machine without aerospace.

## Keymap

`~/.config/sottomano/keymap.json`, decoded straight into `Keymap`. See
`keymap.example.json`. An entry with `entries` is a layer; otherwise it carries
one of `launch`, `url` or `shell`.

- **No name means the entry binds but stays out of the panel.** That is how the
  shift variants stay bound without listing every engine twice.
- **The keymap is read again whenever it is written.** A watcher on the file
  hands over a new one — theme, bindings and hotkeys alike — so trying a colour
  costs a save. It happens on the change rather than on the next open, which
  leaves the path between the hotkey and the first frame untouched.
- **The keymap is generated by nix**, in `home/mac/sottomano.nix`. It has to be:
  an app launched by `open` inherits launchd's PATH, so every command a binding
  runs is named by its store path. `emoji.json` is written next to it, reduced
  from the emojione data already pinned for Hammerspoon.
- A `pick` entry either names a list the app builds itself — clipboard, emoji,
  applications — or gives a command whose lines are the choices, tab separated
  into value, name and subtitle. `{}` in what runs afterwards is the value.
- **A list can carry pictures.** A fourth, tab separated field names one — a
  playlist cover, a favicon — fetched only for the rows on screen, kept under
  `~/.cache/sottomano/covers` and asked for again after a month. A list of a
  hundred and fifty playlists would otherwise open a hundred and fifty
  connections to draw eight of them.
- **The vault's favicons come from the sites themselves**, `https://<host>/favicon.ico`,
  with the host taken from the `uris` that `rbw list --raw` already carries.
  Not from a favicon service: handing one the domains in a password vault is
  handing over the list of where there is an account.
- **`pick.cache` names a file under `~/.cache/sottomano`.** With one, the list
  left there is shown at once and the command runs behind it, replacing what is
  on screen when it answers. It is what makes the linkding bookmarks open now
  rather than after half a second of tailnet.
- **A vault entry passes the name as an argument, not inside the command line.**
  `rbw get "$1"` with the name as `$1` means a name carrying a quote cannot
  break out of the shell.

Panel keys are matched as characters from `charactersIgnoringModifiers`, so a
layout change still binds the key the label shows. A global hotkey is the other
way round: Carbon takes a key code, which binds the physical position, and that
is what a hotkey wants — it stays under the same finger.

## Themes

`theme` in the keymap is a set of options, not the name of one. Every theme that
existed was this panel with different knobs, so the knobs are what is configured:

- `shape` — `list`, or the two that could not be reduced to knobs without being
  spoilt: `keyboard` (the layer lit on a drawing of the keyboard, FastTap's
  argument on the board itself) and `depth` (the layers walked through kept
  behind the current one).
- `flow` — `replace` or `columns`. Miller columns, as the NeXTSTEP browser had
  them, or a panel that takes the place of the one before it.
- `key` — `column` or `inline`. A column of its own, or the initial of the name,
  which is the key anyway.
- `arrow`, `title`, `group` — the arrow between key and name, the road taken
  written over the panel, and the rows sorted into layers, then what opens a
  search, then what acts and is done.
- `top`, `size`, `padding`, `radius`, `borderWidth`, `animation` (seconds, zero
  turns every animation off).
- `background` — a colour, or `glass` for the material macOS draws behind a
  window. Then `border`, `text`, `muted`, `rule`, `selection`, as `#rgb`,
  `#rrggbb` or `#rrggbbaa`.

**One row is drawn in one place.** `RowView` serves both the list and the
columns; they had their own copies once, and half the options silently stopped
working in half the panel.

`iconSize` is the square everything in the icon column is drawn in — an
application's icon, the thumbnail of a copied picture, a colour, an emoji — and
a row's padding follows from it, so the two cannot fall out of proportion.

**Every row of a list is the same height, and whether there is an icon column is
decided over the whole list.** Both were once worked out from the rows in view,
so the column appeared and vanished as the selection moved past the entries
that had icons, and everything below it shifted.

## Browsing

`browse` on an entry opens the filesystem at that directory, which is what `f`
does. It is a place, not a search over the whole disk: the query filters where
you are standing, return goes in, and delete on an empty query comes back out.
The arrows do the same for a hand already on them, and shift+return reveals the
selection in the Finder for the times only the Finder will do.

The clipboard keeps pictures and files as well as text. A file is pasted back
as a file rather than as its path, and its thumbnail is made once when it is
copied: decoding a 24-megapixel photograph to draw it at 22 points, once per
row, is what made the panel take a moment to open. Frecency is left out of it —
a line of the clipboard is a one-off, and remembering it only filled the store
with text that never returns.

**A row that is a timestamp says when it is.** An epoch of 10, 13, 16 or 19
digits, or an ISO 8601 date, gets a clock and the UTC date in place of the
character count, and selecting it lays out every form of it beside the list —
UTC, local, ISO, relative, the three epochs, weekday, ISO week, day of year —
in the place a picture would go. The epoch has to land between 2000 and 2060:
an Italian mobile number read as seconds is a date in the 2070s. A date
without a zone is read as UTC, since a log line without one is a server's.
Tab moves the cursor onto the table and back, return pastes the form under
it and shift+return copies it: the verbs the row already has, with another
value. `Timestamp` is what tells; a `Choice` carries the table as `details`,
so a row that stands for data other than a date can use the same panel.

**A row that is a document is shown written out.** Text opening with `{` or
`[` is read by `JSONValue.parse`, which takes strict JSON and what the Mongo
shell prints — bare keys, single quotes, trailing commas, `ObjectId('…')`
around a value — with one reader, since the strict form is a subset of the
loose one. Keys keep their order and numbers their spelling: the document is
looked at, not computed with. It is pretty-printed beside the list, every
node open: a folding tree was tried first and opened on one collapsed line,
which said nothing. Tab puts the cursor on the first key, the cursor passes
over the root and the closing brackets — the row itself pastes the whole —
and return pastes the line: a string bare, a container written out again.
Sixteen lines and it scrolls; a thousand-line document would otherwise
reach the bottom of the screen.

Directories come before files and dotfiles are left out — on this machine they
are configuration, and configuration is reached by its own means.

## Panel

The visual system is the Hammerspoon panel, and the numbers in `Style` are the
ones settled there: black fill, a 3pt border at 40% white, 12pt radius, 24pt
padding, JetBrains Mono at 19pt with the system monospaced face as a fallback.

**A panel that replaces another one dissolves into it.** The one leaving is kept
alive behind the one arriving rather than photographed: a picture cannot carry
the glass, which the window server draws behind the window and not in the view,
so it came with its own dark background and that flashed. The frame around them
never moves — only the contents cross — and the window snaps to its final size,
since animating that would re-lay-out every frame.

**The window draws the shadow, not SwiftUI.** macOS derives it from the window's
alpha when the window is not opaque, which gives a shadow that follows the
rounded corner — but it caches it, so `invalidateShadow()` has to follow every
resize. Without that the previous shadow stays, and its square corners show
through as black lines around the panel.

- The key is at full white and a leaf action's label is quieter than a layer's.
  The key is the only thing that has to be read.
- The rule divides what leads somewhere from what finishes. Above it: a layer of
  keys, but also a picker, the filesystem and anything that asks a question —
  everything that puts another panel on screen. Below it: what acts and is done.
  Splitting on "has sub-keys" instead put the clipboard among the finished ones,
  which it is not.
- The panel hangs from a line a third of the way down the screen, so the top
  edge does not move as a layer changes the number of rows.
