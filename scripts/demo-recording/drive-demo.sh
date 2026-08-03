#!/bin/bash
# Drives Nevermore's demo mode through the storyboard while something records
# the window. Timings are deliberately slower than a human would work: the
# footage has to be readable, and captions need somewhere to sit.
set -uo pipefail

TABLE='outline 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1'

# Every keystroke re-activates the app first. Without it a stray focus change
# sends the keystroke to whatever is frontmost, and the demo silently skips a
# step — which is exactly how two scenes went missing from the first takes.
key() { osascript -e 'tell application "Nevermore" to activate' -e "tell application \"System Events\" to keystroke \"$1\"" >/dev/null 2>&1; }
cmd() { osascript -e 'tell application "Nevermore" to activate' -e "tell application \"System Events\" to keystroke \"$1\" using command down" >/dev/null 2>&1; }
ret() { osascript -e 'tell application "Nevermore" to activate' -e 'tell application "System Events" to key code 36' >/dev/null 2>&1; }
# Command-Delete, the Trash shortcut.
cmddel() { osascript -e 'tell application "Nevermore" to activate' -e 'tell application "System Events" to key code 51 using command down' >/dev/null 2>&1; }

# Select a sender by name and take keyboard focus in one step.
#
# Addressing rows by index breaks as soon as anything acts on the list —
# unsubscribing or ignoring removes the row and everything below shifts up.
# Setting focus without also setting the selection doesn't stick after a sheet
# closes, which silently swallows every following keystroke: the first cut of
# this script "worked" while quietly doing nothing for two of its six scenes.
select_named() {
  osascript <<EOF
tell application "System Events" to tell process "Nevermore"
  set o to $TABLE
  repeat with i from 1 to (count of rows of o)
    set r to row i of o
    set txt to ""
    try
      set txt to ((value of every static text of every group of every UI element of r) as string)
      if txt contains "$1" then
        set selected of r to true
        set value of attribute "AXFocused" of o to true
        return "OK: " & i
      end if
    end try
  end repeat
  return "MISS"
end tell
EOF
}

# Scene timings are written out so captions can be placed against the real
# recording instead of guessed at from the script.
SCENE_LOG=${SCENE_LOG:-/dev/null}
: > "$SCENE_LOG"
START=$(python3 -c 'import time; print(time.time())')
mark() { python3 -c "import time; print(f'{time.time()-$START:.2f}\t$1')" >> "$SCENE_LOG"; }

osascript -e 'tell application "Nevermore" to activate' >/dev/null 2>&1
sleep 1

# --- Scene 1: what the app is looking at ---------------------------------
cmd 1
mark list
sleep 2.5
select_named "Vellum Weekly"
sleep 2.5

# --- Scene 2: move down the list, inspector following --------------------
key j; sleep 1.0
mark navigate
key j; sleep 1.0
key j; sleep 2.2          # Harbourview Fitness — 5 messages, 100% unread

# --- Scene 3: one keystroke to unsubscribe -------------------------------
key u
mark unsubscribe
sleep 2.6                 # let the confirmation be read
ret
sleep 3.4                 # the result sheet earns its screen time: it says the
                          # request was sent, and that a sender who keeps
                          # mailing will turn up under Reappeared — which is
                          # exactly where this demo ends up.
ret                       # Done — dismiss it, or it covers the next two scenes
sleep 1.6

# --- Scene 4: keep the ones you actually want ----------------------------
select_named "Ferndale Public Library"
mark keep
sleep 2.2                 # 0% unread, but it's the library — you want this
# Menu shortcut, not the single-key "i": after a sheet closes the table can
# lose keyboard focus, and a bare letter key then goes nowhere. Menu commands
# act on the selection regardless of what is focused.
cmd i
sleep 2.6

# --- Scene 5: and clear out the ones you never read ----------------------
select_named "Halcyon Travel Deals"
mark trash
sleep 2.0                 # 9 messages, 89% unread
cmddel
sleep 2.6
ret
sleep 2.4

# --- Scene 6: the payoff -------------------------------------------------
cmd 2                     # Reappeared
mark reappeared
sleep 5.5
