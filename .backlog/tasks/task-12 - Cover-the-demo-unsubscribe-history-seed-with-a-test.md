---
id: TASK-12
title: Cover the demo unsubscribe-history seed with a test
status: Done
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-10 02:00'
labels:
  - tests
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
seedDemoHistoryIfNeeded in AppModel writes back-dated unsubscribe records so Reappeared has something in it. It is guarded on demo mode and an empty history, and the whole point is that the reappeared/honoured split falls out of the real isReappeared comparison rather than a flag.

None of that is tested. A regression would be silent — the collection just goes back to being empty, which is exactly the bug this fixed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test asserts seeding produces the expected reappeared and honoured senders
- [ ] #2 Test asserts seeding does not run twice or overwrite an acted-in demo
- [ ] #3 Test asserts nothing is seeded outside demo mode
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The rule moved from AppModel into DemoData.plannedUnsubscribes(for:now:). The app target is an executable, so nothing living there can be imported by the tests — the logic worth testing had to move to where it could be reached. AppModel now only applies what the rule returns. Seven tests, all asserting through the same newest-message-versus-attempt-date comparison the app uses, so drifting seed dates fail the suite. 117 passing.
<!-- SECTION:NOTES:END -->
