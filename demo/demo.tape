# slickrails demo GIF — the single most important launch asset.
# Render with vhs (https://github.com/charmbracelet/vhs):
#   brew install vhs
#   sh demo/setup-demo-repo.sh /tmp/slickrails-demo
#   cd /tmp/slickrails-demo && vhs < <kit>/demo/demo.tape
# Story: commit a secret → blocked · push with red tests → blocked · fix → green.
# Quoting rule for this file: no backslashes, no nested quotes — a broken quote
# leaves the recorded shell stuck at a continuation prompt and nothing runs.

Output slickrails-demo.gif
Set FontSize 20
Set Width 1200
Set Height 640
# slickrails brand palette: graphite #0B0F0E, acid lime #A8FF06, ink-white #E8EDEA
Set Theme { "name": "slickrails", "background": "#0B0F0E", "foreground": "#E8EDEA", "cursor": "#A8FF06", "selection": "#26302B", "black": "#121816", "red": "#E5484D", "green": "#A8FF06", "yellow": "#E5A83B", "blue": "#9FB3AA", "magenta": "#A78BFA", "cyan": "#6FE3C5", "white": "#E8EDEA", "brightBlack": "#5E6F68", "brightRed": "#FF7A7E", "brightGreen": "#C6FF5C", "brightYellow": "#F0C674", "brightBlue": "#BFD0C9", "brightMagenta": "#C4B5FD", "brightCyan": "#9FF0DC", "brightWhite": "#FFFFFF" }
Set BorderRadius 12
Set TypingSpeed 40ms

Type "# slickrails: guardrails for AI-built code. Watch it catch the classics."
Enter
Sleep 1.5s

# The fake token is assembled by printf so this tape never matches a secrets
# scanner itself, and the typed line never breaks shell quoting. A ghp_-style
# token is used because both gitleaks and the fallback patterns catch it.
Type `printf 'token = "ghp_%s"' 9fQ2xZ7hLmA4tR8wVbN3cKdY6eGpJ5sUq1Ab > config.js && git add config.js`
Enter
Sleep 800ms
Type "git commit -m add-config"
Enter
Sleep 2.5s

Type "# Blocked. No secrets leave this machine. Now: red tests."
Enter
Sleep 1.5s
Type "git rm --cached config.js -q && rm config.js"
Enter
Sleep 800ms

Type "git push origin main"
Enter
Sleep 4s

Type "# Blocked again. Tests are red. Fix, commit, retry:"
Enter
Sleep 1.5s

Type "npm pkg set scripts.test=true && git commit -qam fix-tests"
Enter
Sleep 1.5s
Type "git push origin main"
Enter
Sleep 5s

Type "# Green before push. Every repo, one command: slickrails init"
Enter
Sleep 3s
