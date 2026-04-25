---
name: sync-toolkit
description: Sync plugin skills and rules into the current project. Use when asked to sync toolkit, update skills, or install onboarding files.
---

# Sync Toolkit

Copy the latest skills, rules, and references from this plugin into the current project's `.agents/` directory.

## What This Does

1. Copies skill files from the plugin to `.agents/skills/` in the project
2. Copies rules to `.agents/rules/`
3. Reports what was created or updated

## Steps

1. Create directories if they don't exist:
   - `.agents/skills/review/reference/platforms/`
   - `.agents/skills/write-unit-tests/reference/platforms/`
   - `.agents/skills/doc-write/reference/platforms/`
   - `.agents/rules/`

2. Copy all skill files from `${CLAUDE_PLUGIN_ROOT}/skills/` to `.agents/skills/`

3. Copy all rule files from `${CLAUDE_PLUGIN_ROOT}/rules/` to `.agents/rules/`

4. Report results:
   ```text
   SKILL COMPLETE: /sync-toolkit
   |- Files synced: <count>
   |- New files: <count>
   |- Updated files: <count>
   |- Status: DONE
   ```

## Notes

- This overwrites existing files with the latest versions from the plugin
- Platform-specific files (platforms/*.md) are included
- Project-specific customizations in .agents/ will be overwritten -- back up first if needed
