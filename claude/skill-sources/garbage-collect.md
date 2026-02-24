---
name: garbage-collect
description: Manage files in /garbage folder for deletion
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-00-00

# Garbage Collection for File Deletion

When you lack permissions to delete files directly, move them to `/garbage` folder. This command helps manage that folder.

## Moving Files to Garbage

When you want to delete a file but can't:

```bash
# Create garbage folder if it doesn't exist
mkdir -p garbage

# Move file to garbage
mv path/to/file.ext garbage/

# Or move entire directory
mv path/to/directory garbage/
```

**Important:** All files should be preserved in git history before moving to garbage.

## Verify Files in Git History

Before moving files to garbage:

```bash
# Check if file is in git history
git log -- path/to/file.ext

# If not in git history, commit first
git add path/to/file.ext
git commit -m "Archive: [file.ext] before deletion"

# Then move to garbage
mv path/to/file.ext garbage/
```

## Check Garbage Folder

```bash
# List files in garbage
ls -lh garbage/

# Show disk space used
du -sh garbage/
```

## Add to .gitignore

Ensure garbage folder is ignored:

```bash
# Add to .gitignore if not already there
grep -q "^garbage/$" .gitignore || echo "garbage/" >> .gitignore
```

## User Cleanup

The user will periodically run:

```bash
# Review garbage contents
ls -la garbage/

# Permanently delete garbage contents
rm -rf garbage/*

# Or delete entire garbage folder
rm -rf garbage/
```

## Pre-Garbage Checklist

Before moving anything to garbage:

- [ ] File is committed to git history
- [ ] File is truly no longer needed (not just temporarily)
- [ ] No active code references this file
- [ ] grep for file references: `git grep "filename"`
- [ ] Check import statements if applicable

## Example Workflow

```bash
# 1. Verify file is in git
git log -- old-component.tsx

# 2. Search for references
git grep "old-component"

# 3. If no references and in git, move to garbage
mkdir -p garbage
mv src/components/old-component.tsx garbage/

# 4. Commit the deletion
git add -A
git commit -m "Remove old-component.tsx (moved to garbage)"
```

## Bulk Garbage Collection

When moving many files:

```bash
# Create timestamped garbage subdirectory
GARBAGE_DATE=$(date +%Y%m%d-%H%M)
mkdir -p "garbage/${GARBAGE_DATE}"

# Move files with context
mv path/to/old-files/* "garbage/${GARBAGE_DATE}/"

# Create manifest
cat > "garbage/${GARBAGE_DATE}/MANIFEST.md" <<EOF
# Garbage Collection

**Date:** $(date +"%Y-%m-%d-%H-%M")
**Reason:** [Why these files were removed]

## Files Removed
$(ls -1 "garbage/${GARBAGE_DATE}/")

## Git References
These files are preserved in git history before this commit:
$(git log -1 --oneline)
EOF
```

This helps user understand what's in garbage when they review it.
