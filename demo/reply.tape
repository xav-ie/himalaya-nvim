Output demo/reply.svg
Output demo/reply.mp4

Set FontFamily "Maple Mono NF"
Set FontSize 20
Set Width 1024
Set Height 576
Set Theme "Builtin Dark"
Set Padding 0
Set CursorBlink false
Set ProgressBar "#9B79FF"

Hide
Type "nvim -u demo/init.lua"
Enter
Type ":Himalaya"
Enter
Sleep 1s
Type@0ms ":Msg Read an email"
Enter
Sleep 100ms
Show
Sleep 2s

# Navigate to an email
Type "jjj"
Sleep 300ms

# Read it
Enter
Sleep 2s

# Reply from the reading view
Hide
Type@0ms ":Msg Reply with <gr>"
Enter
Sleep 100ms
Show
Sleep 2s

Type "gr"
Sleep 2s

# Write the reply body (cursor is at body area after headers)
Type "jjo"
Hide
Type@0ms "Thanks for the update, looks good to me!"
Sleep 200ms
Escape
Show
Sleep 1s

# Send the reply
Hide
Type@0ms ":Msg Send reply with <:w>"
Enter
Sleep 100ms
Show
Sleep 2s

Type ":w"
Hide
Enter
Sleep 200ms
Show
Sleep 2s

Sleep 1s
