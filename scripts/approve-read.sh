#!/bin/bash
# PermissionRequest hook: auto-approve reading plugin files and project manifests.
# Reads JSON from stdin; outputs allow decision for safe read operations.

INPUT=$(cat)

# Plugin's own files (skills, rules, reference, platforms)
if echo "$INPUT" | grep -qF "\"$CLAUDE_PLUGIN_ROOT/"; then
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    exit 0
fi

# Project manifest files for platform detection
if echo "$INPUT" | grep -qE '"(go\.mod|go\.sum|package\.json|build\.gradle|settings\.gradle|AndroidManifest\.xml|Podfile|.*\.xcodeproj|Cargo\.toml|pom\.xml|Makefile|Dockerfile|\.tool-versions|pubspec\.yaml|Gemfile|requirements\.txt|pyproject\.toml)"'; then
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    exit 0
fi
