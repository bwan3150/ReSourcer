import { test, expect } from '@playwright/test'
import { installGalleryMocks, seedAuth, FILES } from './helpers/mockApi.js'

/** Keep in sync with web/src/api/preview.js THUMBNAIL_VERSION and server THUMBNAIL_VERSION. */
const EXPECTED_TV = '2'

test.describe('Gallery thumbnail cache version', () => {
  test('gallery thumbnail requests include tv= bump', async ({ page }) => {
    await seedAuth(page)
    const calls = { move: [], delete: [], thumbs: [] }
    await installGalleryMocks(page, calls)

    await page.goto('/gallery')
    await expect(page.getByTestId(`file-card-${FILES[0].uuid}`)).toBeVisible()

    await expect.poll(() => calls.thumbs.length).toBeGreaterThan(0)
    for (const url of calls.thumbs) {
      expect(url).toContain(`tv=${EXPECTED_TV}`)
    }
  })
})
