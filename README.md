# claude-ai-onboarding

Claude Code plugin with code review, unit test generation, and documentation writing skills. Automatically detects your project's platform (Go, Android, iOS, Web, QA) and applies platform-specific patterns.

## Installation

```bash
# Add marketplace (once)
/plugin marketplace add TheonAegor/claude-plugins

# Install plugin
/plugin install claude-plugin@theonaegor-claude-plugins
```

## Skills

| Skill | Trigger | What it does |
|---|---|---|
| `/review` | "review code", "do a code review" | Reviews code changes (CI mode for PRs, local mode for git diff) |
| `/write-unit-tests` | "write tests", "add test coverage" | Generates unit tests file-by-file with coverage targets |
| `/doc-write` | "write docs", "update README" | Writes/updates documentation following reader-first approach |

## Rules

Two always-on rules included:

- `common.md` -- safe-by-default agent behavior (confirm destructive actions, read before answering)
- `writing-style.md` -- prose-first documentation style (no bullet-point hell)

## Platform Detection

Each skill automatically detects the project platform and loads platform-specific guidelines:

- `go.mod` -> Go patterns (testify, table-driven tests, goroutine safety, error wrapping)
- `build.gradle` + `AndroidManifest.xml` -> Android patterns
- `*.xcodeproj` / `Podfile` -> iOS patterns
- `package.json` with react/vue/angular -> Web patterns
- QA project indicators -> QA patterns

Platform files live in `skills/*/reference/platforms/`. Add your platform's patterns there.

## Updating the plugin (adding a new skill)

When you add a new skill to the repo, follow these steps so users get it on the next `/plugin update`:

1. Create the skill folder: `skills/{skill-name}/SKILL.md` (with optional `reference/`, `scripts/`, `templates/` subfolders).
2. Bump the version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (use semver -- minor bump for a new skill, patch for fixes).
3. Update the Skills table in this README with the new skill's trigger and description.
4. Commit and push to `master`:
   ```bash
   git add skills/{skill-name} .claude-plugin/ README.md
   git commit -m "add {skill-name} skill"
   git push
   ```
5. Users pull the update with:
   ```bash
   /plugin marketplace update theonaegor-claude-plugins
   /plugin update claude-plugins@theonaegor-claude-plugins
   ```

## Contributing

Add platform-specific patterns by editing files in `skills/*/reference/platforms/`. Each platform file is independent -- you can add content without touching common files.

Structure:
```
skills/{skill-name}/reference/platforms/{platform}.md
```

Currently populated: `golang.md`. Other platforms are stubs waiting for content.
