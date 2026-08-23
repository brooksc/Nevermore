---
id: TASK-31
title: Tell people what a sender will cost them next year
status: Done
assignee: []
created_date: '2026-08-10 01:49'
updated_date: '2026-08-23 20:36'
labels:
  - product
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreKit/Domain/SenderForecast.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Domain/SenderCadence.swift
  - >-
    Packages/NevermoreKit/Sources/NevermoreKit/Domain/UnsubscribePeriodReport.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Views/InspectorView.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/Suites.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/TestSupport.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app knows first seen, last received and message count, so it can say what a subscription costs going forward: "about 156 more a year at this rate". A forecast argues for the unsubscribe better than a backlog count does, because the backlog is sunk and the forecast is not.

Same data supports a trend — a sender that has gone from monthly to twice weekly is worth surfacing, and is exactly the kind of drift nobody notices from the inbox.

No new fetching: this is arithmetic over what is already stored.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Per-sender forecast shown in the inspector
- [x] #2 Cadence changes surfaced where they are material
- [x] #3 Wording stays honest about it being an estimate from past rate
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`SenderForecast` (NevermoreKit/Domain) turns the dates already on file into a
forward rate, shown in the inspector under the statistics — the same four
numbers read forward instead of backward, and above the buttons because it is
an argument about which one to press.

TASK-32's cadence was extracted rather than duplicated: `SenderCadence` now owns
the median-gap rhythm and the bounded silence threshold, and
`UnsubscribePeriodReport.quietSpan` delegates to it. One definition, so the
sidebar and the inspector cannot disagree about the same sender.

Minimum evidence before any yearly figure: 5 messages spanning 60 days. Below
either bar the panel says it does not know. A sender past its own silence
threshold is reported as stopped rather than forecast at last year's rate.

Two estimators, deliberately: the *mean* gap drives the rate (a retailer's
Black Friday week is mail you will receive) while the *median* gap drives the
"has it stopped" question (a burst must not shrink the usual gap). Where they
diverge 3× the sender is labelled as arriving in bursts.

The lapse check reads the last 10 messages, not all of history — a weekly
newsletter that went monthly a year ago has a week-long median across its whole
life, so a punctual monthly issue read as a fortnight of ominous silence.

Wording leads with a hedged cadence in words ("About once a week") and offers a
coarsely-rounded annual figure as support, because "156 a year" claims a
precision the sample cannot carry. `staysWithinTheEvidence` asserts the copy
still hedges and never promises, mirroring TASK-32.

Trend: first half of the history against the second, surfaced only at a 2×
change with 8+ messages and 2 in each half.

523 tests in 88 suites pass (494 on main + 29 new).
<!-- SECTION:NOTES:END -->
