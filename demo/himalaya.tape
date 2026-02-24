Output demo/himalaya.svg
Output demo/himalaya.mp4

Set FontFamily "Maple Mono NF"
Set FontSize 20
Set Width 1280
Set Height 720
Set Theme "Builtin Dark"
Set Padding 0

Hide
Type "nvim -u demo/init.lua"
Enter
Sleep 1s
Show

# Open himalaya — flat listing
Hide
Type@0ms ":Msg Open the email listing with <:Himalaya>"
Enter
Sleep 100ms
Show
Sleep 1.5s

Type ":Himalaya"
Enter
Sleep 2s

# Help overlay — show keybinds first
Hide
Type@0ms ":Msg Press <?> for keybind help"
Enter
Sleep 100ms
Show
Sleep 1.5s

Type "?"
Sleep 3s
Escape
Sleep 1s

# Navigate and read
Hide
Type@0ms ":Msg Navigate with <j>/<k> — read with <Enter>"
Enter
Sleep 100ms
Show
Sleep 1.5s

Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms

Enter
Sleep 2s

Type ":q"
Enter
Sleep 1s

# Sort toggle
Hide
Type@0ms ":Msg Toggle sort order with <go>"
Enter
Sleep 100ms
Show
Sleep 1.5s

Type "go"
Sleep 2s
Type "j"
Sleep 1s
Enter
Sleep 2s

# Search
Hide
Type@0ms ":Msg Search emails with <g/>"
Enter
Sleep 100ms
Show
Sleep 2s

Type "g/"
Sleep 1.5s

Type "alpha"
Sleep 1s
Enter
Sleep 2s

# Change folder
Hide
Type@0ms ":Msg Switch mailbox with <gm>"
Enter
Sleep 100ms
Show
Sleep 1.5s

Type "gm"
Sleep 1s
Type "Sent"
Sleep 500ms
Enter
Sleep 2s

# Switch to thread view (go back to INBOX first)
Hide
Type@0ms "gm"
Sleep 500ms
Type@0ms "INBOX"
Sleep 500ms
Enter
Sleep 500ms
Type@0ms ":lua require('himalaya.config').set('thread_view', true)"
Enter
Type@0ms ":Himalaya"
Enter
Sleep 1s
Type@0ms ":Msg Thread view with tree connectors"
Enter
Sleep 100ms
Show
Sleep 2s

# Navigate threads
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms

# Read from thread view
Enter
Sleep 2s

Type ":q"
Enter
Sleep 1s

# Compose a new email
Hide
Type@0ms ":Msg Compose a new email with <gw>"
Enter
Sleep 100ms
Show
Sleep 1.5s

Type "gw"
Sleep 2s

# Fill in To: (cursor starts in insert mode at To:)
Type@40ms "alice@example.com"
Escape
Sleep 300ms

# Fill in Subject
Type "jA"
Type@40ms "Meeting notes"
Escape
Sleep 300ms

# Body
Type "jjo"
Type@40ms "Hi Alice, attaching the notes from today."
Escape
Sleep 1s

# Discard compose
Type ":q!"
Enter
Sleep 500ms

# Done
Sleep 2s
