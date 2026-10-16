import { test, expect } from '@playwright/test'
import { installGalleryMocks, seedAuth, FILES } from './helpers/mockApi.js'

/** Keep in sync with web/src/api/preview.js THUMBNAIL_VERSION and server THUMBNAIL_VERSION. */
const EXPECTED_TV = '2'

/**
 * Web UI E2E：确认画廊仍走客户端缩略图缓存 + `tv=`，
 * 且请求契约与服务端磁盘持久化（`.thumb` 镜像）兼容。
 * 服务端落盘行为由 server/tests/thumbnail_persist_api 覆盖。
 */
test.describe('Gallery thumbnail persist contract', () => {
  test('gallery keeps local cache path and sends tv= for server thumb API', async ({ page }) => {
    await seedAuth(page)
    const calls = { move: [], delete: [], thumbs: [] }
    await installGalleryMocks(page, calls)

    await page.goto('/gallery')
    await expect(page.getByTestId(`file-card-${FILES[0].uuid}`)).toBeVisible()

    await expect.poll(() => calls.thumbs.length).toBeGreaterThan(0)
    for (const url of calls.thumbs) {
      expect(url).toContain('/api/preview/thumbnail')
      expect(url).toContain(`tv=${EXPECTED_TV}`)
      // Client cache keying still uses full URL (IndexedDB); server may hit .thumb on disk.
      expect(url).toMatch(/uuid=|path=/)
    }
  })
})
