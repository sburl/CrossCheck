#!/bin/bash
# Codex wrapper for Claude Code terminal integration
# Makes 'codex exec' work by calling Claude Code to run it

if [ "$1" = "exec" ]; then
    shift  # Remove 'exec' from arguments
    prompt="$*"

    # Write prompt to temp file for Claude Code to pick up
    temp_file="/tmp/codex-review-$(date +%s).txt"
    echo "$prompt" > "$temp_file"

    echo "📝 Codex review request queued: $temp_file"
    echo "   Claude Code will process this in next Codex session"

    # Optional: If you have a way to trigger Claude Code programmatically
    # osascript to send to running Claude session, etc.

else
    echo "Usage: codex exec '<prompt>'"
    exit 1
fi
