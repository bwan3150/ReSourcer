import { test, expect } from '@playwright/test'
import { installGalleryMocks, seedAuth, FILES } from './helpers/mockApi.js'

test.describe('Gallery batch select', () => {
  test.beforeEach(async ({ page }) => {
    await seedAuth(page)
  })

  test('enters select mode, selects files, bulk moves', async ({ page }) => {
    const calls = { move: [], delete: [] }
    await installGalleryMocks(page, calls)

    await page.goto('/gallery')
    await expect(page.getByTestId(`file-card-${FILES[0].uuid}`)).toBeVisible()

    await page.getByTestId('batch-select-toggle').click()
    await expect(page.getByTestId('batch-action-bar')).toBeVisible()
    await expect(page.getByTestId('batch-selected-count')).toContainText('0')

    await page.getByTestId(`file-card-${FILES[0].uuid}`).click()
    await page.getByTestId(`file-card-${FILES[1].uuid}`).click()
    await expect(page.getByTestId('batch-selected-count')).toContainText('2')
    await expect(page.getByTestId(`file-card-${FILES[0].uuid}`)).toHaveAttribute(
      'data-selected',
      'true',
    )

    await page.getByTestId('batch-move-btn').click()
    await expect(page.getByTestId('move-dialog')).toBeVisible()
    await page.getByTestId('move-here-btn').click()
    await page.getByTestId('move-confirm-btn').click()

    await expect.poll(() => calls.move.length).toBe(1)
    // Axios converts request keys to snake_case before send
    const moveBody = calls.move[0]
    expect(moveBody.uuids.sort()).toEqual(['uuid-alpha', 'uuid-beta'].sort())
    const target = moveBody.target_folder || moveBody.targetFolder
    expect(target).toBeTruthy()
    expect(target).toContain('source')
  })

  test('select all then bulk deletes to recycle', async ({ page }) => {
    const calls = { move: [], delete: [] }
    await installGalleryMocks(page, calls)

    await page.goto('/gallery')
    await expect(page.getByTestId(`file-card-${FILES[0].uuid}`)).toBeVisible()

    await page.getByTestId('batch-select-toggle').click()
    await page.getByTestId('batch-select-all').click()
    await expect(page.getByTestId('batch-selected-count')).toContainText('3')

    await page.getByTestId('batch-delete-btn').click()
    await expect(page.getByTestId('confirm-dialog')).toBeVisible()
    await expect(page.getByTestId('confirm-title')).toContainText('3')
    await page.getByTestId('confirm-ok').click()

    await expect.poll(() => calls.delete.length).toBe(1)
    expect(calls.delete[0].uuids.sort()).toEqual(
      ['uuid-alpha', 'uuid-beta', 'uuid-gamma'].sort(),
    )
    await expect(page.getByTestId('batch-action-bar')).toHaveCount(0)
  })

  test('cancel exits select mode without calling APIs', async ({ page }) => {
    const calls = { move: [], delete: [] }
    await installGalleryMocks(page, calls)

    await page.goto('/gallery')
    await page.getByTestId('batch-select-toggle').click()
    await page.getByTestId(`file-card-${FILES[0].uuid}`).click()
    await page.getByTestId('batch-cancel-btn').click()

    await expect(page.getByTestId('batch-action-bar')).toHaveCount(0)
    expect(calls.move).toHaveLength(0)
    expect(calls.delete).toHaveLength(0)
  })
})
