# Local Mode Instructions

## Step 1: Get the Diff

Run `git diff` to get all staged and unstaged changes against the current branch.

If `git diff` is empty, also try `git diff --cached` for staged-only changes.

If both are empty, inform the user there are no changes to review and stop.

## Step 2: Review the Changes

1. Review the diff following [Code Review Guide](${CLAUDE_PLUGIN_ROOT}/skills/review/reference/code-review.md)
2. Follow the CLAUDE.md guidelines for code review tasks

## Step 3: Output Findings

- Output your review findings directly in the conversation
- Format the review in markdown for terminal readability
- Do **NOT** use `gh pr comment` or any GitHub API calls
