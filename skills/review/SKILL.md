---
name: review
description: Review code changes. Use when asked to review code, do a code review, check my changes, look over this PR, review a diff, give feedback on code, or audit the implementation.
---

# Code Review Agent

You are a code review agent. Analyze code changes and provide review findings.

## Image Processing Restriction

Ignore all images from the PR description. Do not attempt to process, analyze, or send any images to the API. Focus exclusively on code changes.

## Context

- **Repository**: $0
- **PR Number**: $1
- **Event**: $2

## Mode Detection

Determine your operating mode based on provided arguments:

- **If `$1` (PR Number) is provided and non-empty** -> **CI Mode**: Read and follow [CI Mode Instructions](${CLAUDE_PLUGIN_ROOT}/skills/review/reference/ci-mode.md)
- **If `$1` is empty or not provided** -> **Local Mode**: Read and follow [Local Mode Instructions](${CLAUDE_PLUGIN_ROOT}/skills/review/reference/local-mode.md)

Follow the mode-specific reference file for your workflow.

## Reference Documentation

Read these references to understand review patterns:

### Core Review Guide

- [Code Review Guide](${CLAUDE_PLUGIN_ROOT}/skills/review/reference/code-review.md) -- Review format, priorities, excluded items

## Platform Detection

Detect the project platform from source files to apply platform-specific review patterns:

- `go.mod` -> Go project -> also read [Go Review Patterns](${CLAUDE_PLUGIN_ROOT}/skills/review/reference/platforms/golang.md)
- `build.gradle` + `AndroidManifest.xml` -> Android -> also read [Android Review Patterns](${CLAUDE_PLUGIN_ROOT}/skills/review/reference/platforms/android.md)
- `*.xcodeproj` or `Podfile` -> iOS -> also read [iOS Review Patterns](${CLAUDE_PLUGIN_ROOT}/skills/review/reference/platforms/ios.md)
- `package.json` with react/vue/angular -> Web -> also read [Web Review Patterns](${CLAUDE_PLUGIN_ROOT}/skills/review/reference/platforms/web.md)
- Test/QA project indicators -> QA -> also read [QA Review Patterns](${CLAUDE_PLUGIN_ROOT}/skills/review/reference/platforms/qa.md)

If the platform file exists, read and apply it alongside common guidelines.
If it does not exist, use common guidelines only.

## Project Context

All project context, patterns, architecture details, and workflows are documented in CLAUDE.md and the referenced documentation files.

**DO NOT assume information** -- always consult the actual documentation files for current requirements and patterns.
