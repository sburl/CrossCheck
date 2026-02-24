---
name: setup-statusline
description: Customize Codex statusline for better context awareness
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-00-00

# Setup Statusline

Customize your Codex statusline to show context usage, git branch, and PR counter.

> "For easier Codex-juggling, use /statusline to customize your status bar to always show context usage and current git branch." - Codex team

## Why Customize Statusline?

**Problems it solves:**
- ❌ Don't know when context is getting full
- ❌ Forget which branch you're on
- ❌ Lost track of PR count (when to assess?)
- ❌ Hard to tell worktrees apart

**What statusline shows:**
- ✅ Context usage percentage
- ✅ Current git branch
- ✅ PR counter (optional)
- ✅ Worktree name (optional)

**Especially useful with:**
- Multiple worktrees (3-5 Codex sessions)
- Long coding sessions
- Frequent branch switching

## Basic Setup

### Step 1: Use Built-in Statusline Command

```bash
/statusline set-format "{{context}}% | {{branch}}"
```

**Result:**
```
45% | feature-auth
```

### Step 2: Customize Format

**Available variables:**
- `{{context}}` - Context usage percentage
- `{{branch}}` - Current git branch
- `{{repo}}` - Repository name
- `{{user}}` - Current user
- `{{cwd}}` - Current working directory

**Example formats:**

**Minimal:**
```bash
/statusline set-format "{{context}}% | {{branch}}"
# Output: 45% | feature-auth
```

**Detailed:**
```bash
/statusline set-format "{{repo}} | {{branch}} | {{context}}%"
# Output: my-app | feature-auth | 45%
```

**With worktree:**
```bash
/statusline set-format "{{branch}} ({{context}}%)"
# Output: feature-auth (45%)
```

## Advanced Customization

### For Multiple Worktrees

When running 3-5 Codex sessions, you need to quickly identify which is which:

**Option 1: Branch Name Prominent**
```bash
/statusline set-format "🔷 {{branch}} | {{context}}%"
```

**Terminal tabs:**
```
🔷 main | 25%
🔷 feature-auth | 45%
🔷 feature-ui | 62%
🔷 bugfix-login | 38%
```

**Option 2: Include Repo Name** (if same worktree used across projects)
```bash
/statusline set-format "{{repo}}/{{branch}} | {{context}}%"
```

**Output:**
```
my-app/feature-auth | 45%
other-app/feature-ui | 30%
```

### Add PR Counter

If you've integrated PR counter tracking:

```bash
/statusline set-format "{{branch}} | {{context}}% | PR:{{pr_counter}}/3"
```

**Output:**
```
feature-auth | 45% | PR:1/3
```

Shows you're 1 PR into the cycle (need 2 more before assessment).

**Note:** This requires custom integration. The PR counter is tracked by the `post-merge` git hook at `$(git rev-parse --git-common-dir)/hooks-pr-counter`.

### Color Coding (Terminal-Dependent)

Some terminals support ANSI color codes:

```bash
# Context < 50%: Green
# Context 50-80%: Yellow
# Context > 80%: Red

/statusline set-format "\033[{{context_color}}m{{context}}%\033[0m | {{branch}}"
```

Check your terminal's documentation for color support.

## Terminal-Specific Setup

### Ghostty (Team Favorite)

**Why Ghostty:**
- Synchronized rendering
- 24-bit color support
- Proper unicode support
- Fast performance

**Statusline in Ghostty:**
```bash
# Full unicode support
/statusline set-format "{{context}}% • {{branch}}"
# Output: 45% • feature-auth
```

### tmux Integration

If using tmux for multiple worktrees:

```bash
# Set tmux window name to match branch
tmux rename-window "{{branch}}"

# Or in statusline:
/statusline set-format "[{{tmux_session}}] {{branch}} | {{context}}%"
```

### iTerm2

iTerm2 can show badges with statusline info:

```bash
# Use iTerm2 badges feature
# statusline can update badge text
```

## Context Awareness Best Practices

### Understand Context Levels

**0-50% (🟢 Green - Safe)**
- Work normally
- No need to compact

**50-80% (🟡 Yellow - Monitor)**
- Watch for degradation
- Consider `/compact`
- Plan when to compact

**80-100% (🔴 Red - Action Needed)**
- Run `/compact` to compress context
- Or start fresh session
- Don't continue without action

### Automated Alerts

Set up alerts based on context:

```bash
# If statusline shows >80%
# Automatically suggest: "Consider running /compact"

# If statusline shows >90%
# Automatically suggest: "Start fresh session with /compact"
```

## Workflow Integration

### With Worktrees

**Terminal tab naming strategy:**

```
Tab 1: Main           | Statusline: 25% | main
Tab 2: Auth Feature   | Statusline: 45% | feature-auth
Tab 3: UI Redesign    | Statusline: 62% | feature-ui  ⚠️ Getting high
Tab 4: Bug Fix        | Statusline: 38% | bugfix-login
```

**Quick glance tells you:**
- Which worktree/branch you're in
- Which sessions need context management
- Easy to juggle 3-5 Claudes

### With Color-Coded Terminals

**Terminal tab colors:**
- **Blue**: Main branch
- **Green**: Features (context < 50%)
- **Yellow**: Features (context 50-80%)
- **Red**: Bug fixes or high context

**Combined with statusline:**
- Color = purpose
- Statusline = status

## Example Configurations

### Minimal (Recommended)

```bash
/statusline set-format "{{context}}% | {{branch}}"
```

**Pros:**
- Clean and simple
- Shows essentials
- Easy to read

**Best for:**
- Single worktree
- Occasional Codex use

### Detailed (For Power Users)

```bash
/statusline set-format "{{repo}}/{{branch}} | Ctx:{{context}}% | PR:{{pr_counter}}/3"
```

**Pros:**
- Maximum information
- Great for multi-worktree
- PR tracking visible

**Best for:**
- Multiple worktrees
- Daily Codex use
- Following Codex automation workflow

### Minimal with Emoji

```bash
/statusline set-format "{{context}}% 📊 {{branch}} 🌿"
```

**Pros:**
- Visual indicators
- Quick recognition
- Fun!

**Best for:**
- Personal preference
- Visual learners

## Common Patterns

### Pattern 1: Context-First

```bash
/statusline set-format "{{context}}% | {{branch}}"
```

**When:** Context management is priority

### Pattern 2: Branch-First

```bash
/statusline set-format "{{branch}} ({{context}}%)"
```

**When:** Multiple branches/worktrees

### Pattern 3: Full Context

```bash
/statusline set-format "{{repo}}/{{branch}} | {{context}}% | {{cwd}}"
```

**When:** Working across multiple repos

## Troubleshooting

### Statusline Not Showing

```bash
# Check if statusline enabled
/statusline status

# Re-enable
/statusline enable

# Reset to default
/statusline reset
```

### Variables Not Expanding

```bash
# Check format string syntax
/statusline get-format

# Ensure variables spelled correctly:
# {{context}} not {context}
# {{branch}} not {branch}
```

### Context Percentage Incorrect

```bash
# Context shown in statusline may update with delay
# For real-time: check Codex's response
# Statusline updates: every few commands
```

## Team Setup Examples

### Team Member 1: Worktree Heavy User

```bash
/statusline set-format "{{branch}} | {{context}}%"

# Uses with 5 tmux sessions:
# [main | 20%]
# [feature-auth | 45%]
# [feature-ui | 60%]
# [feature-api | 35%]
# [bugfix-race | 50%]
```

### Team Member 2: Simple Setup

```bash
/statusline set-format "{{context}}%"

# Just shows context
# Minimal distraction
# Uses terminal tab names for branch info
```

### Team Member 3: Full Details

```bash
/statusline set-format "{{repo}}/{{branch}} ({{context}}%) [{{user}}]"

# Everything visible
# Great for pair programming
# Easy to share screenshots
```

## Advanced: Custom Scripts

If statusline doesn't support something you need, create wrapper:

```bash
# Custom statusline script
#!/bin/bash

CONTEXT=$(codex context-usage)  # Hypothetical
BRANCH=$(git branch --show-current)
PR_COUNT=$(cat "$(git rev-parse --git-common-dir)/hooks-pr-counter" 2>/dev/null || echo 0)

echo "$CONTEXT% | $BRANCH | PR:$PR_COUNT/3"
```

Then integrate with terminal prompt or tmux.

## Related Commands

- `/compact` - Compress context when it gets full
- `/list-worktrees` - See all worktrees (helps with tab naming)
- `CODEX.md` - Workflow auto-loaded (includes statusline recommendations)

## Team Tip from Boris

> "For easier Codex-juggling, use /statusline to customize your status bar to always show context usage and current git branch. Many of us also color-code and name our terminal tabs, sometimes using tmux — one tab per task/worktree."

**Translation:**
- Customize statusline = better awareness
- Name/color terminal tabs = easier navigation
- One tab per worktree = organized parallel work

## Quick Start

**Right now, set up your statusline:**

```bash
/statusline set-format "{{context}}% | {{branch}}"
```

**If using worktrees:**

```bash
# In each worktree terminal:
/statusline set-format "{{branch}} | {{context}}%"

# Name your terminal tabs:
# Main
# Auth Feature
# UI Redesign
# Bug Fix
```

**Start juggling Claudes like a pro!** 🎯
