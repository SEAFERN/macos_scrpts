#!/bin/bash

SESSION="dev"

# If session exists, attach immediately
tmux has-session -t "$SESSION" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "Session '$SESSION' already exists. Attaching..."
    tmux attach-session -t "$SESSION"
    exit 0
fi

# -------------------------
# Create new session
# -------------------------
tmux new-session -d -s "$SESSION" -n "do_deploy" -c "/Users/tli/Downloads/do_deploy"

# -------------------------
# Create windows
# -------------------------
tmux new-window -t "$SESSION:" -n "scripts"       -c "/Users/tli/Downloads/scripts"
tmux new-window -t "$SESSION:" -n "TOOLS-dev"     -c "/Users/tli/Downloads/CODE_LOCAL/tools_the_lords"
tmux new-window -t "$SESSION:" -n "BM-dev"        -c "/Users/tli/Downloads/CODE_LOCAL/2025-0922_BoutiqueMatch"
tmux new-window -t "$SESSION:" -n "PIM-dev"       -c "/Users/tli/Downloads/CODE_LOCAL/Pim"
tmux new-window -t "$SESSION:" -n "KYL-dev"       -c "/Users/tli/Downloads/CODE_LOCAL/KongORG"
tmux new-window -t "$SESSION:" -n "NOTEKEEPER-dev" -c "/Users/tli/Downloads/CODE_LOCAL/notekeeper"

# Optional: Select first window
tmux select-window -t "$SESSION:1"

# Attach
tmux attach-session -t "$SESSION"
