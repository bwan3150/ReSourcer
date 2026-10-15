/** Shared API mocks for Gallery batch-select E2E tests. */

export const SOURCE = '/data/source'
export const ALBUM = '/data/source/Album'

export const FILES = [
  {
    uuid: 'uuid-alpha',
    fileName: 'alpha.png',
    fileType: 'image',
    extension: '.png',
    fileSize: 1024,
    folderPath: SOURCE,
    createdAt: '2026-01-01T00:00:00Z',
    modifiedAt: '2026-01-01T00:00:00Z',
  },
  {
    uuid: 'uuid-beta',
    fileName: 'beta.jpg',
    fileType: 'image',
    extension: '.jpg',
    fileSize: 2048,
    folderPath: SOURCE,
    createdAt: '2026-01-01T00:00:00Z',
    modifiedAt: '2026-01-01T00:00:00Z',
  },
  {
    uuid: 'uuid-gamma',
    fileName: 'gamma.gif',
    fileType: 'gif',
    extension: '.gif',
    fileSize: 4096,
    folderPath: SOURCE,
    createdAt: '2026-01-01T00:00:00Z',
    modifiedAt: '2026-01-01T00:00:00Z',
  },
]

/**
 * Install route mocks for auth + gallery + batch endpoints.
 * Tracks batch move/delete payloads on `calls`.
 */
export async function installGalleryMocks(page, calls = { move: [], delete: [], thumbs: [] }) {
  if (!calls.thumbs) calls.thumbs = []
  await page.route('**/api/**', async (route) => {
    const req = route.request()
    const url = new URL(req.url())
    const path = url.pathname
    const method = req.method()

    const json = (status, body) =>
      route.fulfill({
        status,
        contentType: 'application/json',
        body: JSON.stringify(body),
      })

    if (path === '/api/auth/verify' && method === 'POST') {
      return json(200, { valid: true })
    }
    if (path === '/api/auth/check') {
      return json(200, { valid: true })
    }
    if (path === '/api/config/sources') {
      return json(200, { current: SOURCE, backups: [] })
    }
    if (path === '/api/config/state') {
      return json(200, { sourceFolder: SOURCE, backupSourceFolders: [] })
    }
    if (path === '/api/indexer/folders') {
      const parent = url.searchParams.get('parent_path') || SOURCE
      if (parent === SOURCE) {
        return json(200, [{ name: 'Album', path: ALBUM, fileCount: 0, subfolderCount: 0 }])
      }
      return json(200, [])
    }
    if (path === '/api/indexer/breadcrumb') {
      const folder = url.searchParams.get('folder_path') || SOURCE
      if (folder === ALBUM) {
        return json(200, [
          { name: 'source', path: SOURCE },
          { name: 'Album', path: ALBUM },
        ])
      }
      return json(200, [{ name: 'source', path: SOURCE }])
    }
    if (path === '/api/indexer/files') {
      return json(200, {
        files: FILES,
        total: FILES.length,
        offset: 0,
        limit: 50,
        hasMore: false,
      })
    }
    if (path === '/api/indexer/status') {
      return json(200, { isScanning: false })
    }
    if (path === '/api/tag/list') {
      return json(200, [])
    }
    if (path === '/api/preview/thumbnail') {
      calls.thumbs.push(req.url())
      // Minimal JPEG so <img> decode does not error
      return route.fulfill({
        status: 200,
        contentType: 'image/jpeg',
        body: Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
      })
    }
    if (path.startsWith('/api/preview/')) {
      return route.fulfill({ status: 204, body: '' })
    }
    if (path === '/api/file/batch/move' && method === 'POST') {
      const body = req.postDataJSON()
      calls.move.push(body)
      const uuids = body.uuids || []
      const target = body.target_folder || body.targetFolder || ALBUM
      if (!uuids.length) return json(400, { error: 'uuids 不能为空' })
      // Respond in snake_case; axios client converts to camelCase
      return json(200, {
        status: 'success',
        success_count: uuids.length,
        failure_count: 0,
        succeeded: uuids.map((uuid) => ({ uuid, new_path: `${target}/x` })),
        failed: [],
      })
    }
    if (path === '/api/file/batch/delete' && method === 'POST') {
      const body = req.postDataJSON()
      calls.delete.push(body)
      const uuids = body.uuids || []
      if (!uuids.length) return json(400, { error: 'uuids 不能为空' })
      return json(200, {
        status: 'success',
        success_count: uuids.length,
        failure_count: 0,
        succeeded: uuids.map((uuid) => ({ uuid, new_path: `${SOURCE}/_Recycle/x` })),
        failed: [],
      })
    }

    // Default: empty success for unhandled reads
    if (method === 'GET') return json(200, {})
    return json(200, { status: 'ok' })
  })

  return calls
}

/** Authenticate by seeding localStorage before first navigation. */
export async function seedAuth(page) {
  await page.addInitScript(() => {
    localStorage.setItem('api_key', 'e2e-test-key')
    localStorage.setItem('server_url', '')
  })
}
