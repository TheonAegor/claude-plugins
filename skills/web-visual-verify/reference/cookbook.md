# Cookbook

Solutions to the annoyances you'll hit once you go past a simple screenshot.

## CORS preflights flood the route handler

Playwright fires the `route` callback for every request, including OPTIONS preflights. If your handler doesn't acknowledge them, the browser sees CORS rejection and the real request never goes out.

```js
await page.route('**/*', async (route) => {
    const req = route.request();
    if (req.method() === 'OPTIONS') {
        return route.fulfill({
            status: 204,
            headers: {
                'access-control-allow-origin': '*',
                'access-control-allow-methods': 'GET,POST,PUT,DELETE,PATCH,OPTIONS',
                'access-control-allow-headers': 'content-type,authorization',
            },
        });
    }
    // ... rest of routing
});
```

## Drag-to-select fires too fast for React

`page.mouse.down() / move / up()` runs at machine speed. React state updates are batched, and a fast drag can end before the `onMouseEnter` of the middle cells fires.

```js
const start = await page.locator('td:nth-child(3)').boundingBox();
const end = await page.locator('td:nth-child(10)').boundingBox();
await page.mouse.move(start.x + 10, start.y + 10);
await page.mouse.down();
// Move in steps so onMouseEnter fires on every cell in between.
for (let x = start.x; x <= end.x; x += 20) {
    await page.mouse.move(x, start.y + 10);
}
await page.mouse.up();
```

## File upload without a real file picker

```js
const fileInput = page.locator('input[type="file"]');
await fileInput.setInputFiles({
    name: 'test.png',
    mimeType: 'image/png',
    buffer: Buffer.from('iVBORw0KGgo...', 'base64'),
});
```

## Hydration mismatch warnings on first render

React 18+ logs hydration warnings as `console.error`. They're noise for visual verification. Filter them in the page listener:

```js
const IGNORE = [
    /<div> cannot be a child of <tr>/,
    /Hydration failed because/,
    /Text content did not match/,
];

page.on('console', (m) => {
    if (m.type() !== 'error') return;
    if (IGNORE.some((re) => re.test(m.text()))) return;
    console.error('! console.error:', m.text());
});
```

Better: fix the warning in the SPA. But for unrelated visual verification, filter and move on.

## Toast notifications poison subsequent screenshots

If the SPA shows a toast on a backend response (success, error), it stays on screen for ~3s and ruins the next screenshot. Either:

1. Wait it out: `await page.waitForTimeout(3500)` (slow).
2. Hide it via CSS in `addStyleTag`:

```js
await page.addStyleTag({ content: '[data-sonner-toaster] { display: none !important }' });
```

## Date-dependent UI

The calendar example highlights "today" based on `new Date()`. If your screenshots are checked in for visual regression, this is non-deterministic. Freeze the clock:

```js
await context.addInitScript(() => {
    const fixed = new Date('2026-05-26T12:00:00').valueOf();
    const RealDate = Date;
    globalThis.Date = class extends RealDate {
        constructor(...args) {
            if (args.length === 0) return new RealDate(fixed);
            return new RealDate(...args);
        }
        static now() { return fixed; }
    };
});
```

## Port conflicts when re-running

Vite picks the next free port if 5173 is in use, so a stale dev server elsewhere makes your `BASE_URL` wrong. Kill before starting:

```bash
pkill -f "vite$" 2>/dev/null
sleep 1
pnpm dev > /tmp/vite.log 2>&1 &
until curl -sI http://localhost:5173/ | grep -q "200 OK"; do sleep 0.5; done
```

## Headed mode for debugging

When a smoke test fails and the stack trace doesn't help, watch it run:

```js
const browser = await chromium.launch({ headless: false, slowMo: 300 });
```

Don't commit this — it'll hang any CI that has no display.
