---
name: web-visual-verify
description: Visually verify a single-page web app change by driving the browser with Playwright, mocking auth in localStorage, and mocking REST API responses. Use when asked to verify a UI change, screenshot the app, smoke-test the UI without a real backend, take a Playwright screenshot, or visually check a frontend PR.
---

# Web Visual Verify

The fastest way to confirm a UI change actually works the way the PR description claims, without spinning up the real backend.

Type-check and unit tests verify *code* correctness. They do not verify that an empty-state actually appears, that a popover opens, or that a colour matches a swatch. This skill closes that gap.

## When this skill applies

- The user asks to verify a frontend change, screenshot the app, or smoke-test a UI flow.
- The app is a JavaScript SPA (React, Vue, Svelte, Angular, vanilla) served by a dev server.
- The page needs auth (token in localStorage or cookies) and backend data, but you don't want to (or can't) run the real backend.

If the user just wants to run the type checker or unit tests, this is the wrong skill — use `/write-unit-tests` or run `tsc` directly.

## The pattern

Four steps. Each one is a place agents commonly get wrong; the reference docs in this skill cover the gotchas.

1. **Boot the dev server** on a known port (commonly `5173` for Vite, `3000` for CRA/Next).
2. **Seed auth** via Playwright `addInitScript` so the SPA's `isAuthenticated()` check passes before any code runs.
3. **Route-mock the API** with `page.route('**/*', handler)`. Only return canned JSON for paths that are actually backend calls — don't match Vite source paths like `/src/core/api/apiHooks.ts`.
4. **Drive the page** (`page.goto` → wait for a known selector → optional `page.keyboard` / `page.click`) and `page.screenshot()`.

Each step is detailed in [reference/pattern.md](reference/pattern.md). Read it before writing the smoke script.

## Two ways to use the skill

### A. Run the bundled config-driven script

For simple "load the page, wait for stuff, screenshot" flows. The script takes a JSON config describing the fixtures and shotlist.

```bash
node ${CLAUDE_PLUGIN_ROOT}/skills/web-visual-verify/scripts/screenshot-spa.mjs \
    --config ./my-app.shotlist.json \
    --out /tmp/shot.png
```

A working example config lives at [templates/luvento.shotlist.json](templates/luvento.shotlist.json). Copy it next to your project and customise the four sections: `localStorage`, `apiMatch`, `fixtures`, `wait`.

### B. Write a per-scenario `.mjs` script

For anything beyond a simple screenshot — keyboard shortcuts, drag-to-select, multi-step flows — write a standalone Playwright script. The bundled script is essentially a reference implementation you can copy.

See [reference/scenario-template.md](reference/scenario-template.md) for a ready-to-copy template, and [reference/cookbook.md](reference/cookbook.md) for solutions to common annoyances (CORS preflights, file uploads, drag, hydration mismatches).

## Hard-won details

These appear in [reference/pattern.md](reference/pattern.md) but call them out because agents miss them:

- **Auth seeding must run *before* the app boots.** Use `context.addInitScript`, not `page.evaluate` after `goto` — the SPA's auth gate runs synchronously during render.
- **Distinguish API requests from source-file requests.** The naive `url.includes('/api/')` also matches Vite source paths like `/src/core/api/apiHooks.ts`. Use a stricter match: `/api/v\d+/` or the backend's actual port (`:8081`).
- **Return a fallback body for unmocked endpoints**, not a 404. A 404 makes hooks set `error` and changes what's rendered. The fallback should be a kitchen-sink JSON shape (`{channels:[], properties:[], items:[], ...}`) that satisfies whatever the unmocked hook expects.
- **Suppress onboarding tours.** Many SPAs render a react-joyride overlay on first visit that intercepts clicks. Seed the tour-completed flag in localStorage too.
- **Wait for a specific selector after `goto`**, not `waitUntil: 'networkidle'` alone. Networkidle can fire before React commits the second render.

## Quality gate

Before reporting "verified":

- [ ] Screenshot exists at the expected path and the user can `Read` it.
- [ ] No `pageerror` event was logged during the run (script prints `! pageerror:` to stderr).
- [ ] No `console.error` was logged unexpectedly (warnings about `<div> in <tr>` etc. are project-specific noise; check against `origin/main` if unsure whether you introduced them).
- [ ] If the smoke test makes behavioural assertions (e.g. "Esc closes the form"), every assertion passed — `check()` failures should fail the script's exit code, not just log.
