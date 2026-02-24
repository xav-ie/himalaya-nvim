Output demo/himalaya.svg
Output demo/himalaya.mp4

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
Sleep 1s
Type ":Himalaya"
Enter
Sleep 1s
Show

# Flat listing
Sleep 4s

# Navigate to Alice's email and read it
Type "j"
Sleep 500ms

Enter
Sleep 5s

# Reply
Type "gr"
Sleep 2s

# Type reply instantly, then reveal
Hide
Type@0ms "jjo"
Type@0ms "Yes! It's great — I manage all my email in Neovim now. You should try it!"
Escape
Sleep 200ms
Show
Sleep 3s

# Send the reply
Type@0ms ":w"
Sleep 200ms
Enter
Sleep 3s

# Done
Sleep 1.5s
