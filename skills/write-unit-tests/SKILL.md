---
name: write-unit-tests
description: Generate and run unit tests. Use when asked to write tests, add test coverage, create unit tests, generate tests for a file, or test a module.
---

# Write Unit Tests

Generate business logic unit tests file-by-file with coverage goals.

Create or update unit tests following the [Unit Testing Strategy](${CLAUDE_PLUGIN_ROOT}/skills/write-unit-tests/reference/unit-test.md).

## Platform Detection

Detect the project platform to apply the right testing patterns:

- `go.mod` -> Go project -> also read [Go Testing Patterns](${CLAUDE_PLUGIN_ROOT}/skills/write-unit-tests/reference/platforms/golang.md)
- `build.gradle` + `AndroidManifest.xml` -> Android -> also read [Android Testing](${CLAUDE_PLUGIN_ROOT}/skills/write-unit-tests/reference/platforms/android.md)
- `*.xcodeproj` or `Podfile` -> iOS -> also read [iOS Testing](${CLAUDE_PLUGIN_ROOT}/skills/write-unit-tests/reference/platforms/ios.md)
- `package.json` with react/vue/angular -> Web -> also read [Web Testing](${CLAUDE_PLUGIN_ROOT}/skills/write-unit-tests/reference/platforms/web.md)
- Test/QA project indicators -> QA -> also read [QA Testing](${CLAUDE_PLUGIN_ROOT}/skills/write-unit-tests/reference/platforms/qa.md)

If the platform file exists, read and apply it. If not, determine testing conventions from the project itself.

## Intent

- Generate business logic unit tests strictly one file at a time (sequential).
- Start with documentation (test plan), then implement tests, then run only the written tests.
- DO NOT modify production code without explicit user approval.

## Mandatory Rules

- Work file-by-file only. Do not proceed to the next file until tests are written, compile, and pass.
- Always begin with a short testing plan for the current file (what to cover: happy path, errors, edge cases).
- Verify data structures and interfaces before creating test data.
- Create comprehensive tests: happy path, error cases, edge cases.
- Run only the tests you wrote using test targeting.
- Target 70-80% coverage. If not achieved after 3 attempts, stop and ask the user.
- Provide per-file coverage summary.
- DO NOT modify any non-test files without explicit user permission.

## Step-by-step (per file)

1. Find similar existing tests in the same package to reuse patterns.
2. Verify interfaces and models to prepare correct test fixtures.
3. Write tests (happy, error, edge) following the project's testing patterns:
   - Use table-driven/parameterized tests for multiple scenarios
   - Follow existing test naming conventions in the project
   - Use the project's testing framework and assertion library
4. Run only the written tests for this package.
5. If tests fail, make test-only fixes and rerun until green.
6. Report per-file coverage and short summary.

## Quality Gate

Before reporting completion, verify per file:

- [ ] Tests compile without errors
- [ ] All tests pass
- [ ] Coverage meets target
- [ ] No production code modified without user approval
- [ ] Test names follow project conventions

## Completion

When all files are processed, output:

```text
SKILL COMPLETE: /write-unit-tests
|- Files tested: <count>
|- Tests written: <count>
|- Tests passing: <count>
|- Coverage: <percentage>%
|- Status: PASS | NEEDS_ATTENTION
```
