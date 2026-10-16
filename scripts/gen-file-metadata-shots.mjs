/**
 * Aesthetic preview screenshots for file-metadata feature.
 * - iOS: original label/value info sheet + extended fields; GlassButton row (SF Symbols)
 * - Web: desktop side panel with original rows + extended fields; lucide icon action row
 * - No emoji. Video = playback controls only.
 * - Also emits before-comparison shots of the pre-change detail UI.
 */
import { chromium } from 'playwright'
import { mkdirSync, writeFileSync, copyFileSync } from 'fs'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, '..')
const REPO_OUT = join(ROOT, 'docs/screenshots/file-metadata')
const STORE_OUT =
  '/Users/ericwang/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-01a13105-7e35-766a-9ab1-1448a0642bca/files/media/file-metadata'
const SELF_STORE =
  '/Users/ericwang/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-e7323f5d-a5b7-5951-965f-746cd77d3525/files/media/file-metadata'

mkdirSync(REPO_OUT, { recursive: true })
mkdirSync(STORE_OUT, { recursive: true })
mkdirSync(SELF_STORE, { recursive: true })

/* Minimal inline SVG icons (lucide-like) — no emoji */
const I = {
  photo: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/></svg>`,
  pin: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>`,
  download: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>`,
  share: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>`,
  folder: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>`,
  pencil: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>`,
  trash: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>`,
  info: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>`,
  x: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>`,
  play: `<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>`,
  prev: `<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><polygon points="19 20 9 12 19 4 19 20"/><line x1="5" y1="19" x2="5" y2="5" stroke="currentColor" stroke-width="2"/></svg>`,
  next: `<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 4 15 12 5 20 5 4"/><line x1="19" y1="5" x2="19" y2="19" stroke="currentColor" stroke-width="2"/></svg>`,
}

const css = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif; }
  .phone {
    width: 390px; height: 844px; border-radius: 44px; overflow: hidden;
    background: #000; position: relative; box-shadow: 0 30px 80px rgba(0,0,0,.55);
  }
  .phone-bg { position: absolute; inset: 0; background: #0a0a0c; }
  .photo {
    position: absolute; left: 0; right: 0; top: 54px; bottom: 0;
    background:
      radial-gradient(ellipse at 30% 35%, #6b8cae 0%, transparent 55%),
      radial-gradient(ellipse at 70% 60%, #c4a574 0%, transparent 50%),
      linear-gradient(180deg, #2a3340, #1a1512);
  }
  .status {
    position: absolute; top: 0; left: 0; right: 0; height: 54px;
    color: #fff; display: flex; align-items: flex-end; justify-content: space-between;
    padding: 0 28px 8px; font-size: 14px; font-weight: 600;
  }
  .sheet {
    position: absolute; left: 0; right: 0; bottom: 0; max-height: 72%;
    background: rgba(242,242,247,.94); backdrop-filter: blur(40px) saturate(180%);
    border-radius: 16px 16px 0 0; padding: 10px 16px 28px; color: #111;
    display: flex; flex-direction: column;
  }
  .grab { width: 36px; height: 5px; border-radius: 99px; background: #c7c7cc; margin: 0 auto 10px; flex-shrink: 0; }
  .sheet-title { font-size: 17px; font-weight: 650; text-align: center; margin-bottom: 12px; }
  .rows { overflow: auto; flex: 1; padding-bottom: 8px; }
  .row { margin-bottom: 12px; }
  .row .lab { font-size: 12px; color: #6c6c70; margin-bottom: 2px; }
  .row .val { font-size: 16px; color: #111; word-break: break-all; }
  .actions {
    display: flex; gap: 8px; padding-top: 8px; flex-shrink: 0;
  }
  .abtn {
    flex: 1; height: 44px; border: 0; border-radius: 12px;
    background: rgba(120,120,128,.16); color: #111;
    display: flex; align-items: center; justify-content: center;
  }
  .abtn.danger { background: rgba(255,59,48,.18); color: #d70015; }
  .mod {
    background: rgba(255,255,255,.55); border-radius: 14px; padding: 14px; margin-bottom: 10px;
    backdrop-filter: blur(12px);
  }
  .mod-date { font-size: 17px; font-weight: 650; letter-spacing: -0.2px; }
  .mod-fname { margin-top: 6px; font-size: 13px; color: #6c6c70; display: flex; align-items: center; gap: 6px; }
  .mod-device { display: flex; align-items: baseline; justify-content: space-between; gap: 8px; }
  .mod-device .name { font-size: 14px; font-weight: 600; }
  .pill {
    font-size: 11px; font-weight: 650; background: rgba(60,60,67,.12);
    padding: 3px 8px; border-radius: 999px;
  }
  .mod-muted { font-size: 13px; color: #6c6c70; margin-top: 6px; }
  .strip {
    display: flex; margin-top: 10px; align-items: center;
    font-size: 12px; font-variant-numeric: tabular-nums; font-weight: 550;
  }
  .strip span { flex: 1; text-align: center; }
  .strip .div { width: 1px; height: 16px; background: rgba(60,60,67,.28); flex: 0 0 1px; }
  .map {
    height: 110px; border-radius: 10px;
    background: linear-gradient(135deg, #d7e6d2, #b7c9df 55%, #e8d9c0);
    position: relative; overflow: hidden;
  }
  .map::after {
    content: ''; position: absolute; left: 50%; top: 48%; width: 14px; height: 14px;
    margin: -7px 0 0 -7px; border-radius: 50% 50% 50% 0; transform: rotate(-45deg);
    background: #ff3b30; box-shadow: 0 0 0 3px rgba(255,59,48,.25);
  }
  .coords { margin-top: 8px; font-size: 13px; color: #6c6c70; display: flex; align-items: center; gap: 6px; }
  .desktop {
    width: 1280px; height: 800px; background: #121214; color: #eee;
    display: flex; flex-direction: column; overflow: hidden; border-radius: 12px;
  }
  .topbar {
    height: 48px; display: flex; align-items: center; gap: 12px;
    padding: 0 16px; border-bottom: 1px solid #2a2a2e; background: #18181b;
  }
  .topbar .title { flex: 1; font-size: 13px; color: #cfcfd2; }
  .iconbtn {
    width: 28px; height: 28px; border-radius: 6px; border: 0;
    background: #2a2a2e; color: #ddd; display: inline-flex; align-items: center; justify-content: center;
  }
  .iconbtn.active { background: #3b82f6; color: #fff; }
  .stage { flex: 1; display: flex; min-height: 0; }
  .media {
    flex: 1; background:
      radial-gradient(ellipse at 35% 40%, #4a6a88 0%, transparent 55%),
      radial-gradient(ellipse at 70% 65%, #8a6a45 0%, transparent 50%),
      #0e1014;
    position: relative;
  }
  .side {
    width: 352px; background: #1c1c1f; border-left: 1px solid #2a2a2e;
    display: flex; flex-direction: column;
  }
  .side-h {
    display: flex; align-items: center; gap: 8px; padding: 12px 16px;
    border-bottom: 1px solid #2a2a2e; font-size: 13px; font-weight: 600;
  }
  .kbd { font-size: 10px; opacity: .45; border: 1px solid #444; border-radius: 4px; padding: 1px 5px; }
  .side-body { flex: 1; overflow: auto; padding: 14px 16px; font-size: 13px; }
  .wrow { display: flex; justify-content: space-between; gap: 12px; padding: 6px 0; }
  .wrow .k { color: #8b8b93; flex-shrink: 0; }
  .wrow .v { text-align: right; color: #e8e8ea; max-width: 60%; word-break: break-all; }
  .side-actions {
    border-top: 1px solid #2a2a2e; padding: 8px; display: flex; gap: 4px;
  }
  .sbtn {
    flex: 1; height: 36px; border: 0; border-radius: 8px;
    background: transparent; color: #e8e8ea;
    display: flex; align-items: center; justify-content: center;
  }
  .sbtn.danger { color: #f87171; }
  .vchrome {
    position: absolute; left: 24px; right: 24px; bottom: 28px;
    display: flex; flex-direction: column; gap: 12px; color: #fff;
  }
  .scrub {
    height: 4px; border-radius: 99px; background: rgba(255,255,255,.25); position: relative;
  }
  .scrub::before {
    content: ''; position: absolute; left: 0; top: 0; bottom: 0; width: 38%;
    background: #fff; border-radius: 99px;
  }
  .scrub::after {
    content: ''; position: absolute; left: 38%; top: 50%; width: 12px; height: 12px;
    margin: -6px 0 0 -6px; border-radius: 50%; background: #fff;
  }
  .vbtns { display: flex; align-items: center; justify-content: center; gap: 36px; }
  .vmeta { display: flex; justify-content: space-between; font-size: 12px; opacity: .85; }
`

function rowsHTML(items) {
  return items.map(([k, v]) => `<div class="row"><div class="lab">${k}</div><div class="val">${v}</div></div>`).join('')
}

function wrowsHTML(items) {
  return items.map(([k, v]) => `<div class="wrow"><span class="k">${k}</span><span class="v">${v}</span></div>`).join('')
}

function actionRowIOS() {
  return `<div class="actions">
    <button class="abtn" title="下载">${I.download}</button>
    <button class="abtn" title="分享">${I.share}</button>
    <button class="abtn" title="移动">${I.folder}</button>
    <button class="abtn" title="重命名">${I.pencil}</button>
    <button class="abtn danger" title="删除">${I.trash}</button>
  </div>`
}

function actionRowWeb() {
  return `<div class="side-actions">
    <button class="sbtn" title="Download">${I.download}</button>
    <button class="sbtn" title="Share">${I.share}</button>
    <button class="sbtn" title="Move">${I.folder}</button>
    <button class="sbtn" title="Rename">${I.pencil}</button>
    <button class="sbtn danger" title="Delete">${I.trash}</button>
  </div>`
}

function iosPhotosModules({ rich }) {
  if (!rich) {
    // Sparse: only time module if we have created time; no device EXIF / no map
    return `
      <div class="mod">
        <div class="mod-date">星期五 • 10月16日 • 06:21</div>
        <div class="mod-fname">${I.photo} plain.png · 2 / 12</div>
      </div>
      <div class="mod">
        <div class="mod-device"><div class="name">PNG 图像</div><div class="pill">PNG</div></div>
        <div class="mod-muted">640 × 480 • 1.9 KB</div>
      </div>`
  }
  return `
    <div class="mod">
      <div class="mod-date">星期六 • 6月15日 • 14:32</div>
      <div class="mod-fname">${I.photo} IMG_4821.HEIC · 1 / 12</div>
    </div>
    <div class="mod">
      <div class="mod-device"><div class="name">Apple iPhone 15 Pro</div><div class="pill">HEIC</div></div>
      <div class="mod-muted">Main Camera — 24 mm ƒ1.78</div>
      <div class="mod-muted">24.5 MP • 5712 × 4284 • 2.9 KB</div>
      <div class="strip">
        <span>ISO50</span><div class="div"></div>
        <span>24mm</span><div class="div"></div>
        <span>0ev</span><div class="div"></div>
        <span>ƒ1.8</span><div class="div"></div>
        <span>1/144s</span>
      </div>
    </div>
    <div class="mod">
      <div class="map"></div>
      <div class="coords">${I.pin} 33.86880° S, 151.20930° E</div>
    </div>`
}

function iosHTML({ rich, before }) {
  const items = before
    ? [
        ['文件名', rich ? 'IMG_4821.HEIC' : 'plain.png'],
        ['格式', rich ? 'HEIC' : 'PNG'],
        ['位置', '1 / 12'],
        ['大小', rich ? '2.9 KB' : '1.9 KB'],
        ['分辨率', rich ? '512 × 512' : '640 × 480'],
        ...(rich
          ? [
              ['拍摄时间', '2024-06-15 14:32:01'],
              ['GPS', '33.86880° S, 151.20930° E'],
            ]
          : []),
        ['创建时间', '2026-10-16 06:21:36'],
      ]
    : [
        ['文件名', rich ? 'IMG_4821.HEIC' : 'plain.png'],
        ['格式', rich ? 'HEIC' : 'PNG'],
        ['位置', '1 / 12'],
        ['大小', rich ? '2.9 KB' : '1.9 KB'],
        ['分辨率', rich ? '5712 × 4284' : '640 × 480'],
        ...(rich
          ? [
              ['拍摄时间', '2024-06-15 14:32:01'],
              ['GPS', '33.86880° S, 151.20930° E'],
              ['设备', 'Apple iPhone 15 Pro'],
              ['镜头', 'Main Camera 6.86mm f/1.78'],
              ['像素', '24.5 MP'],
              ['焦距', '24 mm'],
              ['光圈', 'ƒ1.8'],
              ['ISO', '50'],
              ['快门', '1/144'],
              ['曝光补偿', '0 EV'],
            ]
          : []),
        ['创建时间', '2026-10-16 06:21:36'],
      ]

  const actions = before
    ? `<div class="actions">
        <button class="abtn" title="重命名">${I.pencil}</button>
        <button class="abtn" title="移动">${I.folder}</button>
        <button class="abtn" title="下载">${I.download}</button>
      </div>
      <div class="actions" style="margin-top:8px">
        <button class="abtn danger" title="删除">${I.trash}</button>
      </div>`
    : actionRowIOS()

  const modules = before ? '' : iosPhotosModules({ rich })

  return `<!doctype html><html><head><meta charset="utf-8"><style>${css}
    body { display:flex; align-items:center; justify-content:center; min-height:100vh; background:#1c1c1e; }
  </style></head><body>
    <div class="phone">
      <div class="phone-bg"></div>
      <div class="photo"></div>
      <div class="status"><span>9:41</span><span>ReSourcer</span></div>
      <div class="sheet">
        <div class="grab"></div>
        <div class="sheet-title">文件信息</div>
        <div class="rows">
          ${modules}
          ${rowsHTML(items)}
        </div>
        ${actions}
      </div>
    </div>
  </body></html>`
}

function webHTML({ rich, before }) {
  const items = before
    ? [
        ['Name', rich ? 'IMG_4821.HEIC' : 'plain.png'],
        ['Format', rich ? 'HEIC' : 'PNG'],
        ['Size', rich ? '2.9 KB' : '1.9 KB'],
        ['Dimensions', rich ? '512 × 512' : '640 × 480'],
        ...(rich
          ? [
              ['Captured', '2024-06-15 14:32:01'],
              ['GPS', '33.86880° S, 151.20930° E'],
            ]
          : []),
        ['Created', '2026-10-16 06:21:36'],
        ['Modified', '2026-10-16 06:21:36'],
      ]
    : [
        ['Name', rich ? 'IMG_4821.HEIC' : 'plain.png'],
        ['Format', rich ? 'HEIC' : 'PNG'],
        ['Size', rich ? '2.9 KB' : '1.9 KB'],
        ['Dimensions', rich ? '5712 × 4284' : '640 × 480'],
        ...(rich
          ? [
              ['Captured', '2024-06-15 14:32:01'],
              ['GPS', '33.86880° S, 151.20930° E'],
              ['Device', 'Apple iPhone 15 Pro'],
              ['Lens', 'Main Camera 6.86mm f/1.78'],
              ['Megapixels', '24.5 MP'],
              ['Focal length', '24 mm'],
              ['Aperture', 'ƒ1.8'],
              ['ISO', '50'],
              ['Shutter', '1/144'],
              ['Exposure', '0 EV'],
            ]
          : []),
        ['Created', '2026-10-16 06:21:36'],
        ['Modified', '2026-10-16 06:21:36'],
      ]

  const actions = before
    ? `<div class="side-actions">
        <button class="sbtn" title="Rename">${I.pencil}</button>
        <button class="sbtn" title="Move">${I.folder}</button>
        <button class="sbtn" title="Download">${I.download}</button>
        <button class="sbtn danger" title="Delete">${I.trash}</button>
      </div>`
    : actionRowWeb()

  return `<!doctype html><html><head><meta charset="utf-8"><style>${css}
    body { display:flex; align-items:center; justify-content:center; min-height:100vh; background:#0a0a0b; }
  </style></head><body>
    <div class="desktop">
      <div class="topbar">
        <button class="iconbtn">${I.x}</button>
        <div class="title">${rich ? 'IMG_4821.HEIC' : 'plain.png'}</div>
        <div style="font-size:11px;opacity:.45">1 / 12</div>
        <button class="iconbtn active">${I.info}</button>
      </div>
      <div class="stage">
        <div class="media"></div>
        <aside class="side">
          <div class="side-h">File info <span class="kbd">I</span></div>
          <div class="side-body">${wrowsHTML(items)}</div>
          ${actions}
        </aside>
      </div>
    </div>
  </body></html>`
}

function videoHTML({ platform }) {
  if (platform === 'ios') {
    return `<!doctype html><html><head><meta charset="utf-8"><style>${css}
      body { display:flex; align-items:center; justify-content:center; min-height:100vh; background:#1c1c1e; }
      .photo { top:0; background: linear-gradient(180deg,#1a2030,#0b0d12); }
    </style></head><body>
      <div class="phone">
        <div class="phone-bg"></div>
        <div class="photo"></div>
        <div class="status"><span>9:41</span><span>clip.mp4</span></div>
        <div class="vchrome">
          <div class="vmeta"><span>0:12</span><span>0:32</span></div>
          <div class="scrub"></div>
          <div class="vbtns"><span>${I.prev}</span><span>${I.play}</span><span>${I.next}</span></div>
        </div>
      </div>
    </body></html>`
  }
  return `<!doctype html><html><head><meta charset="utf-8"><style>${css}
    body { display:flex; align-items:center; justify-content:center; min-height:100vh; background:#0a0a0b; }
  </style></head><body>
    <div class="desktop">
      <div class="topbar">
        <button class="iconbtn">${I.x}</button>
        <div class="title">clip.mp4</div>
        <div style="font-size:11px;opacity:.45">3 / 12</div>
        <button class="iconbtn">${I.info}</button>
      </div>
      <div class="stage">
        <div class="media">
          <div class="vchrome" style="left:48px;right:48px;bottom:36px">
            <div class="vmeta"><span>0:12</span><span>0:32</span></div>
            <div class="scrub"></div>
            <div class="vbtns"><span>${I.prev}</span><span>${I.play}</span><span>${I.next}</span></div>
          </div>
        </div>
      </div>
    </div>
  </body></html>`
}

async function shot(page, html, name, size) {
  await page.setViewportSize(size)
  await page.setContent(html, { waitUntil: 'networkidle' })
  const path = join(REPO_OUT, name)
  await page.screenshot({ path, type: 'png' })
  copyFileSync(path, join(STORE_OUT, name))
  copyFileSync(path, join(SELF_STORE, name))
  console.log('wrote', name)
}

const browser = await chromium.launch()
const page = await browser.newPage()
await shot(page, iosHTML({ rich: true, before: true }), 'ios-before-detail.png', { width: 430, height: 900 })
await shot(page, webHTML({ rich: true, before: true }), 'web-before-detail.png', { width: 1360, height: 860 })
await shot(page, iosHTML({ rich: true }), 'ios-with-metadata.png', { width: 430, height: 900 })
await shot(page, iosHTML({ rich: false }), 'ios-without-metadata.png', { width: 430, height: 900 })
await shot(page, webHTML({ rich: true }), 'web-with-metadata.png', { width: 1360, height: 860 })
await shot(page, webHTML({ rich: false }), 'web-without-metadata.png', { width: 1360, height: 860 })
await shot(page, videoHTML({ platform: 'ios' }), 'ios-video-controls.png', { width: 430, height: 900 })
await shot(page, videoHTML({ platform: 'web' }), 'web-video-controls.png', { width: 1360, height: 860 })
await browser.close()

writeFileSync(
  join(STORE_OUT, 'README.md'),
  `# File metadata screenshots

- **Original design language** kept (label/value rows); new camera fields appended.
- **No emoji** — SF Symbol / lucide-style icons only.
- **Single action row**: download · share · move · rename · delete.
- iOS uses native \`GlassButton\` (system Liquid Glass / bordered).
- Web: desktop side panel; video = playback controls only.
- Before comparison: \`ios-before-detail.png\`, \`web-before-detail.png\`.
`,
)
console.log('done')
