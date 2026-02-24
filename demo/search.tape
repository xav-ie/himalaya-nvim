Output demo/search.svg
Output demo/search.mp4

Set FontFamily "Maple Mono NF"
Set FontSize 20
Set Width 1024
Set Height 576
Set Theme "Builtin Dark"
Set Padding 0
Set CursorBlink false

Hide
Type "nvim -u demo/init.lua"
Enter
Type ":Himalaya"
Enter
Sleep 1s
Type@0ms ":echo ''"
Enter
Sleep 100ms
Show
Sleep 500ms

Hide
Type@0ms ":Msg Search by subject with <g/>"
Enter
Sleep 100ms
Show
Sleep 2.5s

# First search: subject only
Hide
Type "g/"
Sleep 200ms
Show
Sleep 1.5s

# Type subject search
Hide
Type@0ms "alpha"
Sleep 200ms
Show
Sleep 1s

# Submit
Hide
Enter
Sleep 200ms
Show
Sleep 2s

# Show filtered results (only Alpha thread emails)
Sleep 1s

# Explain that g/ resumes previous query
Hide
Type@0ms ":Msg <g/> resumes previous query for further refinement"
Enter
Sleep 100ms
Show
Sleep 2.5s

Hide
Type "g/"
Sleep 200ms
Show
Sleep 1s

# Tab past body to from field (subject → body → from)
Tab
Sleep 300ms
Tab
Sleep 300ms

# Type from filter
Hide
Type@0ms "bob"
Sleep 200ms
Show
Sleep 1s

# Submit
Hide
Enter
Sleep 200ms
Show
Sleep 2s

# Show narrowed results (only Bob's Alpha emails)
Sleep 2s
