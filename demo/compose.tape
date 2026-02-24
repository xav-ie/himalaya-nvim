Output demo/compose.svg
Output demo/compose.mp4

Set FontFamily "Maple Mono NF"
Set FontSize 20
Set Width 1024
Set Height 576
Set Theme "Builtin Dark"
Set Padding 0
Set PlaybackSpeed 0.5
Set CursorBlink false

Hide
Type "nvim -u demo/init.lua"
Enter
Type ":Himalaya"
Enter
Sleep 1s
Type@0ms ":Msg Compose a new email with <gw>"
Enter
Sleep 100ms
Show
Sleep 2s

# Compose a new email (cursor starts in insert mode at To: field)
Type "gw"
Sleep 2s

# Type the recipient (already in insert mode at To:)
Hide
Type@0ms "recipient@example.com"
Escape
Sleep 100ms
Type@0ms "jA"
Sleep 200ms
Show
Sleep 1s

# Fill in Subject
Hide
Type@0ms "Hello from himalaya"
Escape
Sleep 100ms
Type@0ms "jjo"
Sleep 200ms
Show
Sleep 1s

# Type body
Hide
Type@0ms "This is a demo email composed in himalaya."
Sleep 200ms
Show
Escape
Sleep 1s

# Send the email
Hide
Type@0ms ":Msg Send with <:w>"
Enter
Sleep 100ms
Show
Sleep 2s

Type ":w"
Enter
Sleep 2s

Sleep 1s
