# czui

# terminal emulators being tested
terminator
urxvt
xfce-terminal
xterm

# terminal emulators with issues
gnome-terminal has an issue that causes it to send infinite mouse moves
konsole does not support DECRQM which is required to determine what is supported, also mouse location was more often than not extremely incorrect
ghostty was sending mouse information in incomplete chunks which is incompatible with the input module
