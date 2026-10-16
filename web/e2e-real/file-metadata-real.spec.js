/**
 * Real-backend file-metadata E2E (live server via Vite /api proxy).
 * Requires: E2E_API_KEY, server on :1234, vite on :5173.
 */
import { test, expect } from '@playwright/test'

const KEY = process.env.E2E_API_KEY

test.describe.configure({ mode: 'serial' })
test.beforeEach(async ({ page }) => {
  test.skip(!KEY, 'E2E_API_KEY required')
  await page.addInitScript((key) => {
    localStorage.setItem('api_key', key)
    localStorage.setItem('server_url', '')
  }, KEY)
})

test('rich HEIC shows time/device/GPS modules + 5 action controls', async ({ page }) => {
  await page.goto('/gallery')
  const heic = page.locator('[data-testid^="file-card-"]').filter({ hasText: 'IMG_4821.HEIC' }).first()
  await expect(heic).toBeVisible({ timeout: 25000 })
  await heic.click()
  await page.getByTestId('file-info-btn').click()
  await expect(page.getByTestId('file-metadata-panel')).toBeVisible()
  await expect(page.getByTestId('meta-module-time')).toBeVisible()
  await expect(page.getByTestId('meta-module-device')).toBeVisible()
  await expect(page.getByTestId('meta-gps')).toBeVisible()
  const actions = page.getByTestId('file-info-actions')
  await expect(actions).toBeVisible()
  await expect(actions.locator(':scope > a, :scope > button')).toHaveCount(5)
})

test('sparse PNG hides capture/GPS/device modules', async ({ page }) => {
  await page.goto('/gallery')
  const png = page.locator('[data-testid^="file-card-"]').filter({ hasText: 'plain.png' }).first()
  await expect(png).toBeVisible({ timeout: 25000 })
  await png.click()
  await page.getByTestId('file-info-btn').click()
  await expect(page.getByTestId('file-metadata-panel')).toBeVisible()
  await expect(page.getByTestId('meta-module-time')).toHaveCount(0)
  await expect(page.getByTestId('meta-gps')).toHaveCount(0)
  await expect(page.getByTestId('meta-module-device')).toHaveCount(0)
  await expect(page.getByTestId('meta-module-basics')).toBeVisible()
})

test('video opens with <video> + actions only in info panel', async ({ page }) => {
  await page.goto('/gallery')
  const vid = page.locator('[data-testid^="file-card-"]').filter({ hasText: 'clip.mp4' }).first()
  await expect(vid).toBeVisible({ timeout: 25000 })
  await vid.click()
  await expect(page.locator('video').first()).toBeVisible({ timeout: 20000 })
  await page.getByTestId('file-info-btn').click()
  await expect(page.getByTestId('file-info-actions')).toBeVisible()
  await expect(page.getByTestId('file-info-download')).toBeVisible()
})

test('info-panel download/share/move/rename/delete against live server', async ({ page }) => {
  await page.goto('/gallery')
  const jpg = page.locator('[data-testid^="file-card-"]').filter({ hasText: 'IMG_4821.jpg' }).first()
  await expect(jpg).toBeVisible({ timeout: 25000 })
  await jpg.click()
  await page.getByTestId('file-info-btn').click()
  const actions = page.getByTestId('file-info-actions')

  // DOWNLOAD: href hits live preview content
  const href = await actions.getByTestId('file-info-download').getAttribute('href')
  expect(href).toMatch(/\/api\/preview\/content/)
  const dl = await page.request.get(new URL(href, 'http://127.0.0.1:5173').toString())
  expect(dl.ok()).toBeTruthy()
  expect((await dl.body()).byteLength).toBeGreaterThan(100)

  // SHARE
  await actions.getByTestId('file-info-share').click()

  // MOVE → dialog → cancel (native <dialog>.close — daisyUI may keep element in DOM)
  await actions.getByTitle(/移动|Move/i).click()
  const moveDialog = page.getByTestId('move-dialog')
  await expect(moveDialog).toBeVisible({ timeout: 10000 })
  await moveDialog.locator('.modal-action button').filter({ hasText: /取消|Cancel/i }).click()
  await expect.poll(async () => moveDialog.evaluate((el) => el.open)).toBe(false)

  // RENAME → dialog → cancel
  await page.getByTestId('file-info-btn').click()
  await page.getByTestId('file-info-actions').getByTitle(/重命名|Rename/i).click()
  const renameDialog = page.locator('dialog').filter({ has: page.locator('input.input') }).last()
  await expect(renameDialog).toBeVisible({ timeout: 8000 })
  await renameDialog.locator('.modal-action button').filter({ hasText: /取消|Cancel/i }).click()
  await expect.poll(async () => renameDialog.evaluate((el) => el.open)).toBe(false)

  // DELETE → confirm → cancel (no mutation)
  await page.getByTestId('file-info-btn').click()
  await page.getByTestId('file-info-delete').click()
  await expect(page.getByTestId('confirm-dialog')).toBeVisible({ timeout: 8000 })
  await page.getByTestId('confirm-cancel').click()
  await expect.poll(async () => page.getByTestId('confirm-dialog').evaluate((el) => el.open)).toBe(false)
})
