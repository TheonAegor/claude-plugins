#!/usr/bin/env node
// screenshot-spa.mjs — config-driven Playwright screenshotter for SPAs.
//
// Reads a JSON config describing localStorage seeds + API route mocks +
// fixtures + waits + actions, then drives a real browser and saves a
// screenshot.
//
// Usage:
//   node screenshot-spa.mjs --config <config.json> --out <out.png> [--base-url ...]
//
// Exit codes:
//   0  screenshot saved
//   1  bad arguments
//   2  unhandled error during run
//   3  pageerror or unexpected console.error fired
//
// Requires the consumer project to have `playwright` (or `playwright-core`
// + a Chromium browser already on disk) available via NODE_PATH or a local
// install. The script tries `playwright` first, then `playwright-core`.

import { readFile } from 'node:fs/promises';
import { argv, cwd, exit, stderr, stdout } from 'node:process';
import { createRequire } from 'node:module';
import { resolve as pathResolve } from 'node:path';

// ---- CLI -------------------------------------------------------------------

function parseArgs(args) {
    const out = { config: null, out: null, baseUrl: null, action: [] };
    for (let i = 0; i < args.length; i++) {
        const a = args[i];
        if (a === '--config') out.config = args[++i];
        else if (a === '--out') out.out = args[++i];
        else if (a === '--base-url') out.baseUrl = args[++i];
        else if (a === '--action') out.action.push(args[++i]);
        else if (a === '-h' || a === '--help') {
            stdout.write(USAGE);
            exit(0);
        } else {
            stderr.write(`unknown arg: ${a}\n`);
            exit(1);
        }
    }
    if (!out.config || !out.out) {
        stderr.write(USAGE);
        exit(1);
    }
    return out;
}

const USAGE = `Usage: screenshot-spa.mjs --config <config.json> --out <out.png> [options]

Required:
  --config <path>     JSON config (see templates/luvento.shotlist.json).
  --out <path>        Output PNG path.

Optional:
  --base-url <url>    Override config.baseUrl (default http://localhost:5173).
  --action <name>     Run a named action from config.actions (repeatable).
                      Examples: --action openLegend --action emptySearch
  -h, --help          This message.
`;

// ---- Helpers ---------------------------------------------------------------

const NOW_TOKEN = '{{NOW_MS_PLUS_1D}}';

function resolveLocalStorageValue(v) {
    // Limited template: replace {{NOW_MS_PLUS_1D}} with a future expiry.
    if (typeof v === 'string' && v === NOW_TOKEN) {
        return String(Date.now() + 24 * 60 * 60 * 1000);
    }
    if (typeof v === 'string') return v;
    return JSON.stringify(v);
}

async function loadPlaywright() {
    // The script lives in claude-plugins, but the consumer's `playwright`
    // is in their project's node_modules. Resolve from CWD, not from the
    // script's own location.
    const consumerRequire = createRequire(pathResolve(cwd(), 'package.json'));
    for (const name of ['playwright', 'playwright-core']) {
        try {
            const pkg = consumerRequire(name);
            // Playwright is CJS; module.exports has .chromium directly.
            const chromium = pkg.chromium ?? pkg.default?.chromium;
            if (chromium) return chromium;
        } catch { /* try next */ }
    }
    stderr.write(`Playwright not found in ${cwd()}/node_modules.\nInstall: pnpm add -D playwright\n`);
    throw new Error('playwright missing');
}

function compileMatchers(routes) {
    return routes.map((r) => {
        const re = r.match instanceof RegExp ? r.match : new RegExp(r.match);
        return { ...r, re };
    });
}

// ---- Main ------------------------------------------------------------------

async function run() {
    const args = parseArgs(argv.slice(2));
    const configRaw = await readFile(args.config, 'utf8');
    const config = JSON.parse(configRaw);
    const baseUrl = args.baseUrl || config.baseUrl || 'http://localhost:5173';
    const viewport = config.viewport || { width: 1400, height: 800 };
    const apiMatch = new RegExp(config.apiMatch || '/api/v\\d+/');
    const routes = compileMatchers(config.routes || []);
    const fallbackBody = config.fallback ?? {};
    const wantedActions = new Set(args.action);
    const actions = (config.actions || []).filter((a) => wantedActions.has(a.name));

    const chromium = await loadPlaywright();
    const browser = await chromium.launch();
    const context = await browser.newContext({ viewport });

    // Auth + onboarding seeding before app boots.
    const lsEntries = Object.entries(config.localStorage || {}).map(
        ([k, v]) => [k, resolveLocalStorageValue(v)],
    );
    await context.addInitScript((entries) => {
        for (const [k, v] of entries) localStorage.setItem(k, v);
    }, lsEntries);

    let hadFatal = false;
    const page = await context.newPage();
    page.on('pageerror', (e) => {
        stderr.write(`! pageerror: ${e.message}\n`);
        hadFatal = true;
    });
    page.on('console', (m) => {
        if (m.type() !== 'error') return;
        const text = m.text();
        // Filter known noisy warnings from libraries the SPA didn't author.
        const isLibraryNoise = (config.ignoreConsoleErrors || []).some((pat) =>
            new RegExp(pat).test(text),
        );
        if (!isLibraryNoise) stderr.write(`! console.error: ${text}\n`);
    });

    // API mocking.
    await page.route('**/*', async (route) => {
        const url = route.request().url();
        const isApi = apiMatch.test(url);
        if (!isApi) return route.continue();
        for (const r of routes) {
            if (r.re.test(url)) {
                return route.fulfill({
                    status: r.status || 200,
                    contentType: 'application/json',
                    body: JSON.stringify(r.body ?? {}),
                });
            }
        }
        return route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify(fallbackBody),
        });
    });

    const targetUrl = baseUrl.replace(/\/$/, '') + (config.path || '/');
    await page.goto(targetUrl, { waitUntil: 'networkidle' });

    // Waits — sequential. Each entry is { selector, state? }.
    for (const w of config.wait || []) {
        await page.waitForSelector(w.selector, {
            state: w.state || 'visible',
            timeout: w.timeout || 10_000,
        });
    }
    if (typeof config.settleMs === 'number') {
        await page.waitForTimeout(config.settleMs);
    }

    // Named actions — sequential.
    for (const action of actions) {
        for (const step of action.steps || []) {
            if (step.click) {
                await page.locator(step.click).click();
            } else if (step.fill) {
                await page.locator(step.fill.selector).fill(step.fill.value);
            } else if (step.press) {
                await page.keyboard.press(step.press);
            } else if (step.waitForSelector) {
                await page.waitForSelector(step.waitForSelector, {
                    state: 'visible',
                    timeout: 5_000,
                });
            } else if (step.wait) {
                await page.waitForTimeout(step.wait);
            } else {
                stderr.write(`! unknown step in action "${action.name}": ${JSON.stringify(step)}\n`);
            }
        }
    }

    await page.screenshot({ path: args.out, fullPage: !!config.fullPage });
    stdout.write(`saved ${args.out}\n`);

    await browser.close();
    if (hadFatal) exit(3);
}

run().catch((e) => {
    stderr.write(`unhandled error: ${e.stack || e.message}\n`);
    exit(2);
});
