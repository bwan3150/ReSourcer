import { test, expect } from '@playwright/test'
import { installGalleryMocks, seedAuth, FILES } from './helpers/mockApi.js'

/**
 * Playback-mode redesign E2E (Web):
 * - one chrome mode button: tap toggles advance; long-press opens queue panel
 * - queue panel: independent shuffle / list-loop / same-type switches
 * - entering shuffle omits current_queue (true shuffle)
 */

async function installPlaybackMocks(page, calls) {
  await installGalleryMocks(page, calls)

  // Overlay playlist + preview content routes on top of gallery mocks
  await page.route('**/api/playlist**', async (route) => {
    const url = new URL(route.request().url())
    const mode = url.searchParams.get('mode') || 'sequential'
    const uuid = url.searchParams.get('uuid') || FILES[0].uuid
    const currentQueue = url.searchParams.get('current_queue')
    calls.playlist.push({
      mode,
      uuid,
      currentQueue: currentQueue || null,
    })

    const ordered = [...FILES]
    let items
    if (mode === 'shuffle' && !currentQueue) {
      // Fresh shuffle: reverse-ish order so it differs from sequential neighbors
      items = [ordered[2], ordered[0], ordered.find((f) => f.uuid === uuid) || ordered[1]].filter(
        (v, i, a) => a.findIndex((x) => x.uuid === v.uuid) === i,
      )
      // Ensure current is present
      if (!items.find((f) => f.uuid === uuid)) items.splice(1, 0, ordered.find((f) => f.uuid === uuid))
    } else if (mode === 'shuffle' && currentQueue) {
      const ids = currentQueue.split(',').filter(Boolean)
      items = ids.map((id) => ordered.find((f) => f.uuid === id)).filter(Boolean)
    } else {
      items = ordered
    }

    const currentIndex = Math.max(0, items.findIndex((f) => f.uuid === uuid))
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        items,
        current_index: currentIndex,
        at_start: currentIndex === 0,
        at_end: currentIndex === items.length - 1,
      }),
    })
  })

  await page.route('**/api/preview/**', async (route) => {
    // Tiny 1x1 PNG
    const png = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      'base64',
    )
    return route.fulfill({ status: 200, contentType: 'image/png', body: png })
  })

  await page.route('**/api/tag/file**', async (route) => {
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ tags: [] }),
    })
  })
}

async function openFirstPreview(page) {
  await page.goto('/gallery')
  await expect(page.getByTestId(`file-card-${FILES[0].uuid}`)).toBeVisible()
  await page.getByTestId(`file-card-${FILES[0].uuid}`).click()
  await expect(page.getByTestId('playback-mode-btn')).toBeVisible({ timeout: 10000 })
}

test.describe('Playback mode redesign', () => {
  test.beforeEach(async ({ page }) => {
    await seedAuth(page)
    await page.addInitScript(() => {
      localStorage.removeItem('playback_advanceMode')
      localStorage.removeItem('playback_shuffle')
      localStorage.removeItem('playback_listLoop')
      localStorage.removeItem('playlist_filterByType')
    })
  })

  test('tap mode button toggles advance mode and persists', async ({ page }) => {
    const calls = { move: [], delete: [], playlist: [] }
    await installPlaybackMocks(page, calls)
    await openFirstPreview(page)

    const btn = page.getByTestId('playback-mode-btn')
    await expect(btn).toHaveAttribute('aria-label', '单曲循环')

    await btn.click()
    await expect(btn).toHaveAttribute('aria-label', '自动下一个')

    const stored = await page.evaluate(() => localStorage.getItem('playback_advanceMode'))
    expect(stored).toBe('autoNext')
  })

  test('long-press opens queue panel with three independent switches', async ({ page }) => {
    const calls = { move: [], delete: [], playlist: [] }
    await installPlaybackMocks(page, calls)
    await openFirstPreview(page)

    const btn = page.getByTestId('playback-mode-btn')
    await btn.dispatchEvent('pointerdown', { button: 0 })
    await page.waitForTimeout(500)
    await btn.dispatchEvent('pointerup', { button: 0 })

    const panel = page.getByTestId('queue-panel')
    await expect(panel).toBeVisible()
    await expect(page.getByTestId('queue-shuffle-toggle')).toBeVisible()
    await expect(page.getByTestId('queue-list-loop-toggle')).toBeVisible()
    await expect(page.getByTestId('queue-same-type-toggle')).toBeVisible()
  })

  test('enabling shuffle requests fresh queue without current_queue', async ({ page }) => {
    const calls = { move: [], delete: [], playlist: [] }
    await installPlaybackMocks(page, calls)
    await openFirstPreview(page)

    // Open panel via long-press
    const btn = page.getByTestId('playback-mode-btn')
    await btn.dispatchEvent('pointerdown', { button: 0 })
    await page.waitForTimeout(500)
    await btn.dispatchEvent('pointerup', { button: 0 })
    await expect(page.getByTestId('queue-panel')).toBeVisible()

    const before = calls.playlist.length
    await page.getByTestId('queue-shuffle-toggle').check({ force: true })

    await expect.poll(() => calls.playlist.length).toBeGreaterThan(before)
    const last = calls.playlist[calls.playlist.length - 1]
    expect(last.mode).toBe('shuffle')
    expect(last.currentQueue).toBeNull()

    const shuffleStored = await page.evaluate(() => localStorage.getItem('playback_shuffle'))
    expect(shuffleStored).toBe('true')
  })

  test('list loop and same-type toggles persist independently', async ({ page }) => {
    const calls = { move: [], delete: [], playlist: [] }
    await installPlaybackMocks(page, calls)
    await openFirstPreview(page)

    const btn = page.getByTestId('playback-mode-btn')
    await btn.dispatchEvent('pointerdown', { button: 0 })
    await page.waitForTimeout(500)
    await btn.dispatchEvent('pointerup', { button: 0 })

    // Controlled Vue checkboxes: drive via change events (Playwright check/uncheck is flaky)
    await page.getByTestId('queue-list-loop-toggle').evaluate((el) => {
      el.checked = false
      el.dispatchEvent(new Event('change', { bubbles: true }))
    })
    await page.getByTestId('queue-same-type-toggle').evaluate((el) => {
      el.checked = true
      el.dispatchEvent(new Event('change', { bubbles: true }))
    })

    await expect
      .poll(() => page.evaluate(() => localStorage.getItem('playback_listLoop')))
      .toBe('false')
    await expect
      .poll(() => page.evaluate(() => localStorage.getItem('playlist_filterByType')))
      .toBe('true')

    const last = calls.playlist[calls.playlist.length - 1]
    expect(last.mode).toBe('sequential') // shuffle off + list loop off
  })
})
