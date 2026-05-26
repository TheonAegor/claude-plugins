# The pattern in detail

The skill's whole job is to run a real browser against the dev server and convince the SPA that the backend is up. The four steps below are non-negotiable.

## 1. Boot the dev server

Whatever the project uses. Common cases:

```bash
pnpm dev    # Vite — port 5173
npm start   # CRA — port 3000
next dev    # Next — port 3000
```

The smoke script must NOT start the dev server itself — it depends on hot reload being managed by the developer. Just check it's reachable:

```bash
curl -sI http://localhost:5173/ | head -1
# HTTP/1.1 200 OK
```

If you start it from the script, killing the script kills the server, and re-runs become slow.

## 2. Seed auth — via addInitScript, not page.evaluate

Most SPAs check authentication synchronously during render: `if (!isAuthenticated()) redirect('/login')`. By the time `page.goto` resolves, the redirect has already happened.

`addInitScript` runs **before any page script**, including the SPA's bootstrap:

```js
await context.addInitScript((entries) => {
    for (const [k, v] of entries) localStorage.setItem(k, v);
}, [
    ['access_token', 'x'],
    ['refresh_token', 'y'],
    ['token_expiry', String(Date.now() + 86_400_000)],
]);
```

Common pitfall: doing this with `page.evaluate` *after* `page.goto`. By then the SPA has already redirected to `/login` and your auth seeding is too late.

Also seed any "onboarding tour completed" flags. Many apps use `react-joyride` which renders a full-page overlay that intercepts clicks until dismissed. You won't be able to click anything otherwise.

## 3. Route-mock the API — carefully

Naïve filtering of "what's an API call" gets agents in trouble:

```js
// WRONG — this also matches Vite source paths like /src/core/api/apiHooks.ts
const isApi = url.includes('/api/');
```

Use a stricter pattern:

```js
const isApi = /\/api\/v\d+\//.test(url) || url.includes(':8081') || url.includes(':8085');
```

Or match the backend's actual origin if it's a separate process.

Return a **fallback body** for unmatched but-API URLs, not 404. Many React hooks set an `error` state on non-2xx and render an error UI you weren't aiming for. The fallback should be a kitchen-sink shape — empty arrays/objects for every field the app's hooks touch:

```js
const fallback = {
    channels: [], sources: [], properties: [], bookings: [],
    items: [], data: [], count: 0, error: null,
    config: { support: { telegram: { link: '' } } },
};
```

## 4. Drive the page and wait for what you actually need

`page.goto(url, { waitUntil: 'networkidle' })` is necessary but not sufficient. React often commits a second render after networkidle. Wait for a specific selector that proves the UI you want to screenshot is in the DOM:

```js
await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForSelector('h1:has-text("Календарь")', { timeout: 10_000 });
await page.waitForSelector('tbody tr:nth-child(3)', { timeout: 10_000 });
await page.waitForTimeout(800);  // optional: let any auto-scroll settle
```

Then perform whatever click/keyboard actions the scenario needs, and screenshot.

## Failure modes to catch

The script should fail loudly on:

- `pageerror` event — an unhandled exception bubbled up from React.
- Unexpected `console.error` — but allow a per-project ignore-list for known library warnings (e.g. `<div> cannot be a child of <tr>` if that's an existing project-level issue).
- A `waitForSelector` timeout — means either the API mock is wrong, the auth seed didn't take, or the selector is stale.

When `screenshot-spa.mjs` exits with code 3 (`hadFatal`), don't trust the screenshot.
