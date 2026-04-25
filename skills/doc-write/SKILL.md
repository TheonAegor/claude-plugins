---
name: doc-write
description: Write or edit documentation. Use when asked to write docs, update README, create documentation, edit markdown files, or document code.
---

# Write Documentation

Write or update documentation following project conventions.

Read the [Writing Documentation Guide](${CLAUDE_PLUGIN_ROOT}/skills/doc-write/reference/doc-write.md) before making changes.

## Platform Detection

Detect the project platform for language-specific doc conventions:

- `go.mod` -> Go project -> also read [Go Doc Conventions](${CLAUDE_PLUGIN_ROOT}/skills/doc-write/reference/platforms/golang.md)

If the platform file exists, read and apply it alongside common guidelines.

## Intent

- Write clear, reader-first documentation.
- Self-documenting code is preferred -- only write docs when behaviour is not obvious.

## Mandatory Rules

- Read existing documentation in the target area before writing.
- Do NOT duplicate information that already exists elsewhere.
- Always specify language in code blocks.
- Run `markdownlint --fix path/to/file.md` after editing any `.md` file (if markdownlint is available).

## Step-by-step

1. Identify the scope: what needs to be documented and where it belongs.
2. Check existing docs for overlap -- avoid duplicating content.
3. Write documentation following the guide:
   - Focus on "why" and "how", not obvious "what"
   - Provide minimal working examples
   - Use real types and code from the project
4. Run markdown linting if available.
5. Verify all internal links resolve to existing files.

## Quality Gate

Before reporting completion, verify:

- [ ] No broken internal links
- [ ] No duplicated content with existing docs
- [ ] Code blocks specify language

## Completion

When finished, output:

```text
SKILL COMPLETE: /doc-write
|- Files created: <count>
|- Files updated: <count>
|- Links verified: all | <N broken>
|- Status: PASS | NEEDS_ATTENTION
```
