---
id: TASK-18
title: Shrink unsubscribe.gif for the marketing page
status: On Hold
assignee: []
created_date: '2026-08-09 18:53'
updated_date: '2026-08-24 03:17'
labels:
  - media
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/media/unsubscribe.gif is 1.6 MB, which is fine on GitHub but heavy for a page that loads it on scroll. Dropping to about 900px wide or 10fps gets it near 600 KB.

Regenerate with scripts/demo-recording/build-media.sh rather than re-encoding the GIF, so the palette stays clean.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 unsubscribe.gif under about 700 KB with no visible quality loss
- [ ] #2 Regenerated through build-media.sh and the parameters committed
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-24 03:17
---
Parked, with a measurement the task was right to predict.

Tried the shortcut anyway: re-encoded the existing GIF at 900px/10fps with a fresh palette (`palettegen stats_mode=diff`, `paletteuse dither=bayer diff_mode=rectangle`). It came out at **1.9 MB, larger than the 1.6 MB original**. Without dithering: exactly 1.6 MB, no gain and visible banding.

The reason is that the shipped GIF was built from clean source frames with inter-frame optimisation intact, and a GIF-to-GIF re-encode discards that — the new palette costs more than the smaller dimensions save. So the task's instruction to "regenerate with build-media.sh rather than re-encoding" is now measured rather than assumed.

Regenerating needs the source captures, which are not in the repo (`cap/` is gitignored), so it means re-recording the demo through the GUI. Combined with the maintainer's own read — "with today's internet 1.6MB isn't excessive" — the sensible time to do this is the next time the demo is re-recorded for any other reason. Not worth a session of its own.
---
<!-- COMMENTS:END -->
