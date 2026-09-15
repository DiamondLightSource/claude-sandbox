#!/usr/bin/env node
// Exercise the real browser in the agent jail, using only a loopback fixture.
const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const fs = require('node:fs/promises');

async function main() {
  assert.equal(process.env.IS_SANDBOX, '1', 'Run the smoke check inside the sandbox');
  process.env.PLAYWRIGHT_BROWSERS_PATH ||= '/cache/ms-playwright';
  // Explicit standalone import: project test suites should use their own package.
  const { chromium } = require('/opt/claude-sandbox-browser/node_modules/playwright');
  const output = path.resolve(process.argv[2] || 'browser-smoke');
  await fs.mkdir(output, { recursive: true });
  const errors = [];
  const server = http.createServer((_req, res) => {
    res.setHeader('Content-Type', 'text/html');
    res.end('<!doctype html><title>Sandbox browser check</title>' +
      '<h1>Browser smoke test</h1><button onclick="this.textContent=\'Clicked\'">Click me</button>');
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  let browser;
  try {
    browser = await chromium.launch({
      headless: process.env.BROWSER_HEADED !== '1',
      chromiumSandbox: false,
    });
    const context = await browser.newContext({ viewport: { width: 1000, height: 700 } });
    await context.tracing.start({ screenshots: true, snapshots: true });
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    page.on('requestfailed', request => errors.push(request.url()));
    page.setDefaultTimeout(10000);
    await page.goto(`http://127.0.0.1:${server.address().port}`, { waitUntil: 'load' });
    await page.getByRole('button', { name: 'Click me', exact: true }).click();
    await page.getByRole('button', { name: 'Clicked', exact: true }).waitFor();
    assert.equal(await page.title(), 'Sandbox browser check');
    await page.screenshot({ path: path.join(output, 'page.png'), fullPage: true });
    await context.tracing.stop({ path: path.join(output, 'trace.zip') });
    assert.deepEqual(errors, [], 'Browser errors');
    console.log(`PASS: ${await browser.version()} loaded a local page, handled a click and saved screenshot/trace to ${output}`);
  } finally {
    try { if (browser) await browser.close(); }
    finally { await new Promise(resolve => server.close(resolve)); }
  }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
