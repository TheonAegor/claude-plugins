# Writing Documentation Guide

Documentation follows a reader-first approach: the goal is to speed up the search for a simple working answer, not to document everything possible.

## When to Write Documentation

Write documentation only when behaviour is not clear from the interface and code itself. Self-documenting code is preferred over comments.

Bad example -- redundant, adds no value:

```text
# Example: Creating a new service instance
function createService(repo, publisher) {
    return new Service(repo, publisher)
}
```

Good example -- explains something not obvious from the code:

```text
# ProcessEntity retries up to 3 times with exponential backoff.
# On permanent failure, it publishes a dead-letter event instead of returning error.
```

## Documentation Locations

```text
<package>/README.md      -- package/module overview (only if the module needs explanation)
docs/                    -- consumer docs, integration guides, API references
.agents/                 -- agent guidance docs
```

## Code Documentation Guidelines

Document public API only when the behaviour is non-obvious. Always use real types from the codebase.

## Writing Principles

- Write documentation only when behaviour is not clear from the interface and code
- Focus on real usage and observable behavior
- Provide minimal working code examples
- Document non-obvious behavior and edge cases
- State undefined or unspecified behavior explicitly
