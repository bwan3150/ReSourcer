/**
 * Capture gallery previews for orient6 HEIC/JPG + grid (heic-live e2e server).
 * Usage: node capture-heic-previews.mjs
 */
import { chromium } from 'playwright'
import { mkdirSync } from 'fs'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const OUT = join(__dirname, '../docs/screenshots/heic-live-photo')
mkdirSync(OUT, { recursive: true })

const BASE = process.env.E2E_WEB_URL || 'http://127.0.0.1:1234'
const KEY = process.env.E2E_API_KEY || 'b4d38fc1-6dc0-41aa-bf20-48dc7f470a68'
const SOURCE =
  process.env.E2E_SOURCE_FOLDER || '/private/tmp/resourcer-heic-live-e2e/src'

async function main() {
  const browser = await chromium.launch({ headless: true })
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 } })
  await page.addInitScript(
    ({ key, source }) => {
      localStorage.setItem('api_key', key)
      document.cookie = `api_key=${key};path=/;max-age=2592000`
      localStorage.setItem('server_url', location.origin)
      localStorage.setItem('source_folder', source)
    },
    { key: KEY, source: SOURCE },
  )
  await page.goto(`${BASE}/gallery`, { waitUntil: 'networkidle', timeout: 60000 })
  await page.waitForTimeout(2000)
  await page.screenshot({ path: join(OUT, 'web-gallery-grid.png'), fullPage: false })

  async function openAndShot(name, file) {
    const card = page.locator('[data-testid^="file-card-"]').filter({ hasText: name })
    await card.first().click({ timeout: 20000 })
    await page.waitForTimeout(1500)
    // Prefer media player pane only — excludes sidebar so L/R margins are honest
    const pane = page.locator('.relative.h-full.w-full.overflow-hidden').first()
    if (await pane.count()) {
      await pane.screenshot({ path: join(OUT, file) })
    } else {
      await page.screenshot({ path: join(OUT, file), fullPage: false })
    }
    // close preview
    const close = page.getByRole('button', { name: /close|关闭|×/i }).first()
    if (await close.count()) await close.click({ timeout: 3000 }).catch(() => {})
    else await page.keyboard.press('Escape')
    await page.waitForTimeout(600)
  }

  await openAndShot('orient6.HEIC', 'web-orient6-heic-preview.png')
  await openAndShot('orient6.jpg', 'web-orient6-jpg-preview.png')
  const live = page.locator('[data-testid^="file-card-"]').filter({ hasText: 'IMG_LIVE' })
  if (await live.count()) {
    await openAndShot('IMG_LIVE', 'web-img-live-preview.png')
  }
  await browser.close()
  console.log('captured web previews →', OUT)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
