Output demo/compose.mp4

Set FontFamily "Maple Mono NF"
Set FontSize 24
Set Width 1920
Set Height 1080
Set PlaybackSpeed 0.5
Set Theme "Builtin Dark"

Hide
Type "nvim -u demo/init.lua"
Enter
Type ":Himalaya"
Enter
Sleep 1s
Type@0ms ":Msg Compose a new email with gw"
Enter
Sleep 100ms
Show
Sleep 2s

# Compose a new email (cursor starts in insert mode at To: field)
Type "gw"
Sleep 2s

# Type the recipient (already in insert mode at To:)
Type@50ms "recipient@example.com"
Escape
Sleep 500ms

# Fill in Subject (next header line)
Type "jA"
Type@50ms "Hello from himalaya"
Escape
Sleep 500ms

# Go to body and type
Type "jjo"
Type@50ms "This is a demo email composed in himalaya."
Escape
Sleep 1s

# Send the email
Hide
Type@0ms ":Msg Send with :w"
Enter
Sleep 100ms
Show
Sleep 2s

Type ":w"
Enter
Sleep 2s

# Close the sent buffer — back to listing
Type ":q"
Enter
Sleep 2s
