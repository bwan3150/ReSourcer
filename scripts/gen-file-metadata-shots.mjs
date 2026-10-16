/**
 * Aesthetic preview screenshots for file-metadata feature.
 * iOS = Apple Photos info sheet + action row
 * Web = desktop side info panel
 * Video = playback controls only (no action toolbar)
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

const css = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif; background: #0b0b0c; color: #111; }
  .phone {
    width: 390px; height: 844px; border-radius: 44px; overflow: hidden;
    background: #000; position: relative; box-shadow: 0 30px 80px rgba(0,0,0,.55);
  }
  .phone-bg {
    position: absolute; inset: 0;
    background: linear-gradient(160deg, #1a1a1e 0%, #0a0a0c 40%, #12141a 100%);
  }
  .photo {
    position: absolute; left: 0; right: 0; top: 80px; bottom: 0;
    background:
      radial-gradient(ellipse at 30% 35%, #6b8cae 0%, transparent 55%),
      radial-gradient(ellipse at 70% 60%, #c4a574 0%, transparent 50%),
      linear-gradient(180deg, #2a3340, #1a1512);
  }
  .sheet {
    position: absolute; left: 0; right: 0; bottom: 0;
    background: rgba(242,242,247,.92); backdrop-filter: blur(28px);
    border-radius: 16px 16px 0 0; padding: 12px 16px 28px;
    color: #111;
  }
  .grab { width: 36px; height: 5px; border-radius: 99px; background: #c7c7cc; margin: 0 auto 14px; }
  .card {
    background: rgba(255,255,255,.72); border-radius: 14px; padding: 14px; margin-bottom: 10px;
  }
  .date { font-size: 17px; font-weight: 650; letter-spacing: -0.2px; }
  .fname { margin-top: 6px; font-size: 13px; color: #6c6c70; display: flex; align-items: center; gap: 6px; }
  .device-row { display: flex; align-items: baseline; justify-content: space-between; gap: 8px; }
  .device { font-size: 14px; font-weight: 600; }
  .pill {
    font-size: 11px; font-weight: 650; background: rgba(60,60,67,.12);
    padding: 3px 8px; border-radius: 999px;
  }
  .muted { font-size: 13px; color: #6c6c70; margin-top: 6px; }
  .strip {
    display: flex; margin-top: 10px; align-items: center;
    font-size: 12px; font-variant-numeric: tabular-nums; font-weight: 550;
  }
  .strip span { flex: 1; text-align: center; }
  .strip .div { width: 1px; height: 16px; background: rgba(60,60,67,.28); flex: 0 0 1px; }
  .map {
    height: 110px; border-radius: 10px;
    background:
      linear-gradient(135deg, #d7e6d2, #b7c9df 55%, #e8d9c0);
    position: relative; overflow: hidden;
  }
  .map::after {
    content: ''; position: absolute; left: 50%; top: 48%; width: 14px; height: 14px;
    margin: -7px 0 0 -7px; border-radius: 50% 50% 50% 0; transform: rotate(-45deg);
    background: #ff3b30; box-shadow: 0 0 0 3px rgba(255,59,48,.25);
  }
  .coords { margin-top: 8px; font-size: 13px; color: #6c6c70; }
  .actions { display: flex; gap: 8px; margin-top: 6px; }
  .btn {
    flex: 1; border: 0; border-radius: 12px; padding: 11px 8px;
    background: rgba(120,120,128,.16); font-size: 12px; font-weight: 600; color: #111;
  }
  .btn.danger { background: rgba(255,59,48,.12); color: #d70015; width: 100%; margin-top: 8px; flex: none; }
  .status {
    position: absolute; top: 0; left: 0; right: 0; height: 54px;
    color: #fff; display: flex; align-items: flex-end; justify-content: space-between;
    padding: 0 28px 8px; font-size: 14px; font-weight: 600;
  }
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
    background: #2a2a2e; color: #ddd; font-size: 12px;
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
  .fn { font-size: 15px; font-weight: 600; margin-bottom: 4px; }
  .sub { font-size: 12px; color: #9a9aa0; margin-bottom: 14px; }
  .row { display: flex; justify-content: space-between; gap: 12px; padding: 6px 0; }
  .row .k { color: #8b8b93; }
  .row .v { text-align: right; color: #e8e8ea; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; margin: 12px 0; }
  .chip {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 11px; background: #2a2a30; border-radius: 999px; padding: 4px 8px; color: #d4d4d8;
  }
  .gpsbox {
    border: 1px solid #333; border-radius: 10px; overflow: hidden; margin-top: 8px;
  }
  .gpsmap {
    height: 96px;
    background: linear-gradient(135deg, #2d3b2f, #2a3548 55%, #3a3228);
  }
  .gpslabel { padding: 8px 10px; font-size: 12px; color: #9a9aa0; }
  .side-actions {
    border-top: 1px solid #2a2a2e; padding: 12px; display: grid; gap: 8px;
  }
  .side-actions .rowbtns { display: flex; gap: 8px; }
  .sbtn {
    flex: 1; border: 0; border-radius: 8px; padding: 9px 6px;
    background: #2a2a30; color: #e8e8ea; font-size: 12px; font-weight: 600;
  }
  .sbtn.danger { background: rgba(239,68,68,.15); color: #f87171; width: 100%; }
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
  .vbtns { display: flex; align-items: center; justify-content: center; gap: 28px; font-size: 22px; }
  .vmeta { display: flex; justify-content: space-between; font-size: 12px; opacity: .85; }
  .label { position: absolute; top: 16px; left: 16px; color: #fff; font-size: 11px; opacity: .5; }
`

function iosHTML({ rich }) {
  const body = rich
    ? `
      <div class="card">
        <div class="date">星期六 • 6月15日 • 14:32</div>
        <div class="fname">🖼 IMG_4821.HEIC · 1 / 12</div>
      </div>
      <div class="card">
        <div class="device-row"><div class="device">Apple iPhone 15 Pro</div><div class="pill">HEIC</div></div>
        <div class="muted">Main Camera — 24 mm ƒ1.78</div>
        <div class="muted">24.5 MP • 5712 × 4284 • 2.9 KB</div>
        <div class="strip">
          <span>ISO50</span><div class="div"></div>
          <span>24mm</span><div class="div"></div>
          <span>0ev</span><div class="div"></div>
          <span>ƒ1.8</span><div class="div"></div>
          <span>1/144s</span>
        </div>
      </div>
      <div class="card">
        <div class="map"></div>
        <div class="coords">33.86880° S, 151.20930° E</div>
      </div>`
    : `
      <div class="card">
        <div class="date">plain.png</div>
        <div class="fname">🖼 plain.png · 2 / 12</div>
      </div>
      <div class="card">
        <div class="device-row"><div class="device">PNG 图像</div><div class="pill">PNG</div></div>
        <div class="muted">640 × 480 • 1.9 KB</div>
      </div>`
  return `<!doctype html><html><head><meta charset="utf-8"><style>${css}
    body { display:flex; align-items:center; justify-content:center; min-height:100vh; background:#1c1c1e; }
  </style></head><body>
    <div class="phone">
      <div class="phone-bg"></div>
      <div class="photo"></div>
      <div class="status"><span>9:41</span><span>●●● Wi-Fi</span></div>
      <div class="sheet">
        <div class="grab"></div>
        ${body}
        <div class="actions">
          <button class="btn">重命名</button>
          <button class="btn">移动</button>
          <button class="btn">下载</button>
        </div>
        <button class="btn danger">删除</button>
      </div>
    </div>
  </body></html>`
}

function webHTML({ rich }) {
  const rows = rich
    ? `
      <div class="fn">IMG_4821.HEIC</div>
      <div class="sub">Saturday, Jun 15 · 14:32</div>
      <div class="row"><span class="k">Format</span><span class="v">HEIC</span></div>
      <div class="row"><span class="k">Size</span><span class="v">2.9 KB</span></div>
      <div class="row"><span class="k">Dimensions</span><span class="v">5712 × 4284</span></div>
      <div class="row"><span class="k">MP</span><span class="v">24.5</span></div>
      <div class="row"><span class="k">Device</span><span class="v">Apple iPhone 15 Pro</span></div>
      <div class="row"><span class="k">Lens</span><span class="v">Main Camera 24mm ƒ1.78</span></div>
      <div class="row"><span class="k">Captured</span><span class="v">2024-06-15 14:32:01</span></div>
      <div class="chips">
        <span class="chip">ISO50</span><span class="chip">24mm</span><span class="chip">0ev</span>
        <span class="chip">ƒ1.8</span><span class="chip">1/144s</span>
      </div>
      <div class="gpsbox"><div class="gpsmap"></div><div class="gpslabel">33.86880° S, 151.20930° E</div></div>`
    : `
      <div class="fn">plain.png</div>
      <div class="sub">PNG · no EXIF / GPS</div>
      <div class="row"><span class="k">Format</span><span class="v">PNG</span></div>
      <div class="row"><span class="k">Size</span><span class="v">1.9 KB</span></div>
      <div class="row"><span class="k">Dimensions</span><span class="v">640 × 480</span></div>
      <div class="row"><span class="k">Created</span><span class="v">2026-10-16 06:21:36</span></div>`
  return `<!doctype html><html><head><meta charset="utf-8"><style>${css}
    body { display:flex; align-items:center; justify-content:center; min-height:100vh; background:#0a0a0b; }
  </style></head><body>
    <div class="desktop">
      <div class="topbar">
        <button class="iconbtn">✕</button>
        <div class="title">${rich ? 'IMG_4821.HEIC' : 'plain.png'}</div>
        <div style="font-size:11px;opacity:.45">1 / 12</div>
        <button class="iconbtn active">ℹ</button>
      </div>
      <div class="stage">
        <div class="media"><div class="label">Preview</div></div>
        <aside class="side">
          <div class="side-h">File info <span class="kbd">I</span></div>
          <div class="side-body">${rows}</div>
          <div class="side-actions">
            <div class="rowbtns">
              <button class="sbtn">Rename</button>
              <button class="sbtn">Move</button>
              <button class="sbtn">Download</button>
            </div>
            <button class="sbtn danger">Delete</button>
          </div>
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
          <div class="vbtns"><span>⏮</span><span>⏸</span><span>⏭</span></div>
        </div>
      </div>
    </body></html>`
  }
  return `<!doctype html><html><head><meta charset="utf-8"><style>${css}
    body { display:flex; align-items:center; justify-content:center; min-height:100vh; background:#0a0a0b; }
  </style></head><body>
    <div class="desktop">
      <div class="topbar">
        <button class="iconbtn">✕</button>
        <div class="title">clip.mp4</div>
        <div style="font-size:11px;opacity:.45">3 / 12</div>
        <button class="iconbtn">ℹ</button>
      </div>
      <div class="stage">
        <div class="media">
          <div class="vchrome" style="left:48px;right:48px;bottom:36px">
            <div class="vmeta"><span>0:12</span><span>0:32</span></div>
            <div class="scrub"></div>
            <div class="vbtns"><span>⏮</span><span>⏸</span><span>⏭</span></div>
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

- iOS: Apple Photos–style info sheet; **actions inside the sheet** (rename/move/download/delete).
- Web: **desktop side panel** (not phone Photos chrome); same fields + actions; \`I\` toggles.
- Video: playback controls only — **no** bottom action toolbar.

Updated for UX override (actions in info panel) + web desktop-native addendum.
`,
)
console.log('done')
