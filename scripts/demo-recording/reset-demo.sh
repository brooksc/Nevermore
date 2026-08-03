#!/bin/bash
# Put the app back to a clean demo mailbox and frame the window for capture.
# Leaving and re-entering demo mode rebuilds the database, which is what makes
# takes repeatable.
set -uo pipefail

click() { osascript -e "tell application \"System Events\" to click at {$1, $2}" >/dev/null 2>&1; }

osascript -e 'tell application "Nevermore" to activate' -e 'delay 0.3' \
  -e 'tell application "System Events" to key code 53' >/dev/null 2>&1   # dismiss any sheet
sleep 1
osascript -e 'tell application "System Events" to keystroke "," using command down' >/dev/null 2>&1
sleep 3
osascript -e 'tell application "System Events" to tell process "Nevermore" to click button "Advanced" of toolbar 1 of window 1' >/dev/null 2>&1
sleep 2

# Same coordinates for both: in demo the button reads "Leave Demo Mode", out of
# it "Switch to Demo Mode…". Clicking twice lands back in a freshly built demo
# whichever state we started in.
click 724 645
sleep 3
click 724 645
sleep 9

osascript -e 'tell application "System Events" to tell process "Nevermore" to click button 1 of window "Advanced"' >/dev/null 2>&1
sleep 2
osascript -e 'tell application "Nevermore" to activate' \
  -e 'tell application "System Events" to tell process "Nevermore" to set position of window 1 to {55, 100}' \
  -e 'tell application "System Events" to tell process "Nevermore" to set size of window 1 to {1600, 900}' >/dev/null 2>&1
sleep 3
