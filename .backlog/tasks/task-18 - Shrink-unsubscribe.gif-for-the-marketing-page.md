---
id: TASK-18
title: Shrink unsubscribe.gif for the marketing page
status: To Do
assignee: []
created_date: '2026-08-09 18:53'
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
