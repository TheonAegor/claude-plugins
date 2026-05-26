# Per-scenario script template

For flows that need behavioural assertions (keyboard shortcuts, drag-to-select, multi-step interactions), copy this template into `tests/your-scenario.mjs` and customise.

The bundled `screenshot-spa.mjs` is fine for "open the page and screenshot it". For "press T and verify the calendar scrolled", you want a script with `check()` assertions.

```js
// tests/your-scenario.mjs
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL || 'http://localhost:5173';

const fixtures = {
    properties: { properties: [/* ... */] },
    bookings: { bookings: [] },
};

const fallbackBody = {
    channels: [], sources: [], properties: [], bookings: [], items: [],
    data: [], count: 0, error: null,
};

let failures = 0;
async function check(name, fn) {
    try { await fn(); console.log('  ✓', name); }
    catch (e) { failures++; console.error('  ✗', name, '—', e.message); }
}
const json = (route, body) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });

(async () => {
    const browser = await chromium.launch();
    const context = await browser.newContext({ viewport: { width: 1400, height: 900 } });

    await context.addInitScript(() => {
        localStorage.setItem('access_token', 'x');
        localStorage.setItem('refresh_token', 'y');
        localStorage.setItem('token_expiry', String(Date.now() + 86_400_000));
        // Suppress onboarding tour overlay
        localStorage.setItem('app_onboarding_skipped', 'true');
    });

    const page = await context.newPage();
    page.on('pageerror', (e) => console.error('  ! pageerror:', e.message));

    await page.route('**/*', async (route) => {
        const url = route.request().url();
        const isApi = /\/api\/v\d+\//.test(url);
        if (!isApi) return route.continue();
        if (/\/api\/v2\/properties/.test(url)) return json(route, fixtures.properties);
        if (/\/api\/v1\/bookings/.test(url)) return json(route, fixtures.bookings);
        return json(route, fallbackBody);
    });

    await page.goto(`${BASE}/your-route`, { waitUntil: 'networkidle' });
    await page.waitForSelector('h1:has-text("...")', { timeout: 10_000 });

    console.log('▶ Your scenario');

    await check('the thing renders', async () => {
        // ...assertion...
    });

    await check('keyboard shortcut works', async () => {
        await page.keyboard.press('KeyT');
        await page.waitForTimeout(600);
        // ...assertion...
    });

    await browser.close();
    console.log(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) failed.`);
    process.exit(failures === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
```

## Why this shape

- **Tiny `check()` harness** instead of pulling in `@playwright/test`. Avoids a dev dependency and a runner config file just for smoke. The package only needs `playwright` as a peer.
- **`json(route, body)` helper** keeps the route handler readable.
- **`page.on('pageerror', ...)`** prints unhandled exceptions to stderr without aborting the whole run.
- **Exit non-zero on `failures > 0`** so CI can wire it up.
- **`BASE_URL` env override** lets you point at a deployed preview, not just `localhost`.

## Anti-patterns

- Don't use `@playwright/test` for a 5-assertion smoke. The overhead of `playwright.config.ts` + fixtures + reporters isn't worth it.
- Don't call `await page.waitForLoadState('networkidle')` and assume the UI is done. React commits after networkidle. Always pair with `waitForSelector`.
- Don't put `expect(...).toBeVisible()` in the `check()` body — `expect` from `@playwright/test` isn't imported here. Throw an `Error` instead.
