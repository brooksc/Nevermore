# Recording the demo

Produces `docs/media/` — the GIFs the README uses and the 1080p preview for the
App Store. Everything is captured from **demo mode**, so no real address ever
appears in a published asset, and the purple banner in the footage says as much.

```bash
./reset-demo.sh                      # rebuild a clean demo mailbox, frame the window
./drive-demo.sh                      # run the storyboard (watch it, don't touch the mouse)
./build-media.sh                     # master.mov -> preview + GIFs
```

To record, run the reset first, then start the capture and the driver **from a
single shell** — anything that delays the driver relative to the recording
shows up as dead air at the front and a truncated ending:

```bash
./reset-demo.sh
{ ( sleep 1.5; SCENE_LOG=scenes.txt ./drive-demo.sh ) & } \
  && screencapture -v -V 46 -R 55,100,1600,900 master.mov
```

`scenes.txt` records when each scene began, which is what the caption timings in
`build-media.sh` are derived from — the alternative is guessing from the script
and being a second out everywhere.

## Things that cost time the first time

- **The window must be 1600×900 points at (55,100).** `screencapture -R`
  captures that region at 2× — 3200×1800, exactly 16:9, so it scales to 1080p
  with nothing cropped and no letterboxing. `reset-demo.sh` sets it.
- **Rows are addressed by name, not index.** Unsubscribing or ignoring removes
  a row and everything below shifts up.
- **Selection and keyboard focus have to be set together**, via the
  accessibility API. Setting focus alone doesn't survive a sheet closing, and
  the following keystrokes then go nowhere — silently. Two scenes were missing
  from the early takes for exactly this reason.
- **After a sheet, use menu shortcuts** (`⌘I`, `⌘⌫`) rather than the single-key
  equivalents (`i`, `d`). Menu commands act on the selection whatever holds
  focus.
- **Every keystroke re-activates the app.** A stray focus change otherwise
  sends it somewhere else entirely.
- **This ffmpeg has no `drawtext`** (no libfreetype) and no `subtitles` filter
  (no libass), so captions are rendered to PNG with ImageMagick and composited.
  `docs/media/captions.srt` carries the same text for the site's video element.

## App Store preview constraints

1920×1080, 15–30 seconds. The storyboard runs ~40s, so `build-media.sh` speeds
it up 1.4× to land at 28.8s. If you add a scene, check the duration still fits
before uploading — App Store Connect rejects anything over 30s.
