Output demo/listing.svg
Output demo/listing.mp4

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
Sleep 1s
Type ":Himalaya"
Enter
Sleep 1s
Type@0ms ":Msg Flat listing with adaptive columns"
Enter
Sleep 100ms
Show
Sleep 2s

# Navigate
Hide
Type@0ms ":Msg Navigate: <j>/<k> — jump to unread with <]u>"
Enter
Sleep 100ms
Show
Sleep 2s

Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms

Type "k"
Sleep 300ms
Type "k"
Sleep 300ms

# Jump to next unread
Type "]u"
Sleep 500ms

# Read email
Hide
Type@0ms ":Msg Read email in split view with <Enter>"
Enter
Sleep 100ms
Show
Sleep 2s

Enter
Sleep 2s

# Back to listing
Type ":q"
Enter
Sleep 1s

# Pagination
Hide
Type@0ms ":Msg Paginate with <]]> and <[[>"
Enter
Sleep 100ms
Show
Sleep 2s

Type "]]"
Sleep 2s

Type "[["
Sleep 2s

# Switch to thread view
Hide
Type@0ms ":Msg Switch to thread view with <gt>"
Enter
Sleep 100ms
Show
Sleep 2s

Type "gt"
Sleep 2s

# Navigate through threads
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms
Type "j"
Sleep 300ms

# Toggle reverse order
Hide
Type@0ms ":Msg Reverse thread order with <gT>"
Enter
Sleep 100ms
Show
Sleep 2s

Type "gT"
Sleep 2s

# Toggle back
Type "gT"
Sleep 2s

Sleep 1s
