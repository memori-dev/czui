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

### TUIS
zig https://github.com/rockorager/libvaxis
zig https://github.com/akarpovskii/tuile
zig https://git.sr.ht/~leon_plickat/zig-spoon
go https://github.com/charmbracelet/bubbletea
	components https://github.com/charmbracelet/bubbles
https://zig.news/lhp/want-to-create-a-tui-application-the-basics-of-uncooked-terminal-io-17gm

### UNICODE
zig https://codeberg.org/atman/zg
https://lik.ai/guides/unicode-guide/

### ANSI
https://stackoverflow.com/questions/5966903/how-can-i-get-mousemove-and-mouseclick-in-bash/58390575#58390575
https://en.wikipedia.org/wiki/ANSI_escape_code

### RESOURCES
https://sw.kovidgoyal.net/kitty/keyboard-protocol/
https://kevroletin.github.io/terminal/2021/12/11/how-terminal-works-in.html
https://vt100.net/
https://vt100.net/docs/vt510-rm/RM.html
