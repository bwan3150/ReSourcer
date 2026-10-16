/**
 * File metadata info dialog — Web E2E (route-mocked API for show/hide).
 */
import { test, expect } from '@playwright/test'
import { installGalleryMocks, seedAuth, FILES } from './helpers/mockApi.js'

const RICH = {
  path: '/data/source/IMG_4821.HEIC',
  filename: 'IMG_4821.HEIC',
  format: 'HEIC',
  size: 2996,
  file_type: 'image',
  width: 512,
  height: 512,
  capture_time: '2024-06-15 14:32:01',
  gps: { lat: -33.8688, lon: 151.2093 },
  make: 'Apple',
  model: 'iPhone 15 Pro',
  lens: 'iPhone 15 Pro back triple camera 6.86mm f/1.78',
  focal_length_mm: 24,
  focal_length_35mm: 24,
  aperture: 1.78,
  iso: 50,
  shutter_speed: '1/144',
  exposure_compensation: 0,
  megapixels: 0.3,
  created: '2026-10-16 06:21:36',
  modified: '2026-10-16 06:21:36',
}

const SPARSE = {
  path: '/data/source/plain.png',
  filename: 'plain.png',
  format: 'PNG',
  size: 1947,
  file_type: 'image',
  width: 640,
  height: 480,
  created: '2026-10-16 06:21:36',
  modified: '2026-10-16 06:21:36',
}

async function installMetadataMocks(page) {
  await installGalleryMocks(page)

  await page.route('**/api/file/metadata**', async (route) => {
    const url = new URL(route.request().url())
    const path = url.searchParams.get('path') || ''
    const body = path.includes('plain') ? SPARSE : RICH
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(body),
    })
  })

  await page.route('**/api/playlist**', async (route) => {
    const items = FILES.map((f) => ({
      ...f,
      currentPath: f.uuid === FILES[0].uuid ? RICH.path : SPARSE.path,
      current_path: f.uuid === FILES[0].uuid ? RICH.path : SPARSE.path,
    }))
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        items,
        current_index: 0,
        at_start: true,
        at_end: false,
      }),
    })
  })

  await page.route('**/api/preview/**', async (route) => {
    const png = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      'base64',
    )
    await route.fulfill({ status: 200, contentType: 'image/png', body: png })
  })

  await page.route('**/api/tag/file**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ tags: [] }),
    })
  })
}

test.describe('file metadata info dialog', () => {
  test('rich metadata shows capture/GPS rows', async ({ page }) => {
    await seedAuth(page)
    await installMetadataMocks(page)

    await page.goto('/gallery')
    await expect(page.getByTestId(`file-card-${FILES[0].uuid}`)).toBeVisible()
    await page.getByTestId(`file-card-${FILES[0].uuid}`).click()
    await expect(page.getByTestId('file-info-btn')).toBeVisible({ timeout: 10000 })
    await page.getByTestId('file-info-btn').click()

    await expect(page.getByTestId('file-metadata-panel')).toBeVisible()
    await expect(page.getByTestId('meta-format')).toContainText('HEIC')
    await expect(page.getByTestId('meta-capture-time')).toContainText('2024-06-15')
    await expect(page.getByTestId('meta-gps')).toBeVisible()
    await expect(page.getByTestId('meta-dimensions')).toContainText('512')
  })

  test('sparse metadata hides capture/GPS rows', async ({ page }) => {
    await seedAuth(page)
    await installMetadataMocks(page)

    // Force sparse path on all metadata calls
    await page.route('**/api/file/metadata**', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(SPARSE),
      })
    })

    await page.goto('/gallery')
    await page.getByTestId(`file-card-${FILES[0].uuid}`).click()
    await page.getByTestId('file-info-btn').click()

    await expect(page.getByTestId('file-metadata-panel')).toBeVisible()
    await expect(page.getByTestId('meta-format')).toContainText('PNG')
    await expect(page.getByTestId('meta-capture-time')).toHaveCount(0)
    await expect(page.getByTestId('meta-gps')).toHaveCount(0)
    await expect(page.getByTestId('meta-filename')).toContainText('plain.png')
  })

  test('info side panel exposes download/share/move/rename/delete on one row', async ({ page }) => {
    await seedAuth(page)
    await installMetadataMocks(page)

    await page.goto('/gallery')
    await page.getByTestId(`file-card-${FILES[0].uuid}`).click()
    await page.getByTestId('file-info-btn').click()

    const actions = page.getByTestId('file-info-actions')
    await expect(actions).toBeVisible()
    await expect(actions.getByTestId('file-info-download')).toBeVisible()
    await expect(actions.getByTestId('file-info-share')).toBeVisible()
    await expect(actions.getByTestId('file-info-delete')).toBeVisible()
    // Single row: all action controls are direct children (no nested wrap rows)
    const kids = actions.locator(':scope > a, :scope > button')
    await expect(kids).toHaveCount(5)
  })
})
