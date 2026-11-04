# Watch

A grid of live YouTube, Rumble, and Kick channels in one macOS window.

Requires `yt-dlp` (`brew install yt-dlp`) for YouTube. Streams are resolved
with yt-dlp (YouTube) or straight from the site (Rumble, Kick) and played natively
with AVPlayer — no re-encoding, no web views.

## Run

    make run        # debug build, from the terminal (same as `swift run Watch`)
    make install    # release Watch.app, copied to /Applications
    make uninstall

`make install PREFIX=~/Applications` installs somewhere else; `make app` just
builds `.build/Watch.app`. Or `open Package.swift` to work on it in Xcode.

The installed app and `make run` share the channel list but keep their tile
layout separately (the app's settings live under its bundle ID).

## Channels

Watch keeps a list of channels; each tile shows one of them. Edit the list in
**Watch ▸ Settings…** (⌘,): paste a channel and press Return, give it a
friendly name, drag to reorder, select and press Delete to remove. A channel
can be from YouTube, Rumble (prefix 'rumble:'), Kick (prefix 'kick:').

The list lives in `~/Library/Application Support/Watch/channels.json`
(**Show File in Finder** in the Channels window). It can be edited by hand;
entries can be `{"id": "NASA", "name": "NASA"}` or plain strings in any of the
forms above. Watch rereads it when you switch back to the app.

## Tiles

- **Stream ▸ 4 / 6 / 9 Tiles** (⌘4, ⌘6, ⌘9) sets how many tiles show. The
  shape follows the window: whichever arrangement gives the biggest 16:9
  picture, so six tiles are 2×3 in a typical window and 3×2 in a very wide
  one. Hidden tiles keep their channel, so going from 9 to 4 and back
  restores them.
- **Right-click a tile** to choose its channel. Picking a channel that's on
  another tile swaps the two without reloading either.
- New tiles fill with the next channels in the list that aren't showing.

## Zoom

- **Double-click a tile** to zoom in on it one step: first it expands to a
  2×2 block, covering the three spots next to it; then it fills the window.
  With four tiles a 2×2 block is the whole window, so it goes straight to
  full. Double-click a full-window tile to go back to the grid.
- **Esc** zooms out one step, **⌘0** goes back to the grid, **⌘=** zooms in on
  the tile you're listening to.
- Tiles hidden by a zoomed-in tile are paused, and jump to live when they
  come back.
- While zoomed, pressing a hidden tile's number moves the zoom to it, so in a
  full-window tile 1–9 flip between channels.

## Controls

- Click a tile (or press its number, 1–9) to hear it; everything else is muted.
- Press `M` to mute all.
- Press `R` to re-resolve every stream (useful if a channel just went live).
- Streams re-resolve themselves every few hours and on playback failure.

## Rumble

Rumble has no "what's live now" page, so Watch loads the channel's
livestreams page itself (one request, no yt-dlp) and plays the first stream
marked live. Rumble rate-limits requests, so failed tiles back off (90 s,
doubling, up to 10 min); an offline Rumble channel is rechecked at least every
10 minutes, or press `R`.

## Kick

Watch asks Kick's channel API (`kick.com/api/v2/channels/<name>`, one
request) whether the channel is live and where its stream is. The stream URL
carries a short-lived token that's only checked when playback starts; a tile
that loses playback re-resolves and gets a fresh one.
