// Optional browser-only layout/interaction smoke test. Requires local Chrome and `npm run build`.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const cwd = fileURLToPath(new URL('..', import.meta.url));
const candidates = process.platform === 'win32'
  ? ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe']
  : ['/usr/bin/google-chrome', '/usr/bin/chromium'];
const executablePath = process.env.CHROME_PATH ?? candidates.find(existsSync);
if (!executablePath) throw new Error('Set CHROME_PATH to a Chromium executable to run this optional UI test');

const port = 1427;
const server = spawn(process.execPath, [join(cwd, 'node_modules/vite/bin/vite.js'), 'preview', '--host', '127.0.0.1', '--port', String(port), '--strictPort'], { cwd, stdio: 'ignore' });
let browser;
try {
  let ready = false;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/`);
      if (response.ok) { ready = true; break; }
    } catch { /* wait for Vite */ }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  assert.ok(ready, 'Vite preview did not start');
  browser = await chromium.launch({ executablePath, headless: true });
  const page = await browser.newPage({ viewport: { width: 360, height: 550 }, deviceScaleFactor: 1 });
  await page.goto(`http://127.0.0.1:${port}/`);
  await page.locator('.zone-row').first().waitFor();
  assert.equal(await page.locator('.zone-row').count(), 5);
  assert.equal(await page.locator('.zone-time').count(), 5);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  assert.ok(overflow <= 0, `the 360px popup overflows by ${overflow}px`);
  if (process.env.SCREENSHOT_PATH) await page.screenshot({ path: process.env.SCREENSHOT_PATH });
  for (const selector of ['.hero', '.zone-row', '.window-footer']) {
    const rect = await page.locator(selector).first().boundingBox();
    assert.ok(rect && rect.x >= 0 && rect.x + rect.width <= 360, `${selector} is clipped`);
  }
  await page.getByRole('button', { name: '设置' }).click();
  assert.ok(await page.getByText('登录时启动').isVisible());
  await page.getByRole('button', { name: '返回' }).click();
  await page.getByRole('button', { name: '添加时区' }).first().click();
  await page.getByPlaceholder('搜索城市或时区').fill('Europe/Paris');
  await page.getByRole('button', { name: /Paris/ }).click();
  assert.equal(await page.locator('.zone-row').count(), 6);
  await page.getByRole('button', { name: /Paris.*设为托盘时间/ }).click();
  assert.ok((await page.locator('.hero-zone').innerText()).includes('Paris'));
  await page.reload();
  assert.equal(await page.locator('.zone-row').count(), 6);
  assert.ok((await page.locator('.hero-zone').innerText()).includes('Paris'));
  console.log('UI smoke passed: 360px layout, settings, search, pin and persistence');
} finally {
  await browser?.close();
  server.kill();
}
