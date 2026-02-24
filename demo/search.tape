Output demo/search.svg
Output demo/search.mp4

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
Type@0ms ":Msg Search by subject with <g/>"
Enter
Sleep 100ms
Show
Sleep 2s

# First search: subject only
Type "g/"
Sleep 1.5s

# Type subject search
Type "alpha"
Sleep 1s

# Submit
Enter
Sleep 2s

# Show filtered results (only Alpha thread emails)
Sleep 1s

# Explain that g/ resumes previous query
Hide
Type@0ms ":Msg <g/> again resumes previous query for further refinement"
Enter
Sleep 100ms
Show
Sleep 2.5s

Type "g/"
Sleep 1s

# Tab past body to from field (subject → body → from)
Tab
Sleep 300ms
Tab
Sleep 300ms

# Type from filter
Type "bob"
Sleep 1s

# Submit
Enter
Sleep 2s

# Show narrowed results (only Bob's Alpha emails)
Sleep 2s
