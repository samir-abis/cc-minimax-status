---
description: Show the live MiniMax 5h quota line.
---

Run the bundled statusline script and print its output. Useful when you want a fresh fetch rather than the value the system prompt was last seeded with.

!`bash ~/.claude/statusline.sh`

Format the output as a single line `MiniMax: <X>% / 5h (<reset>)` and surface it to the user verbatim. If the script fails, surface the error too.
