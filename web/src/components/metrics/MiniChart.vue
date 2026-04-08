<template>
  <div class="relative" :style="{ height: height + 'px' }">
    <canvas ref="canvas" class="w-full h-full"
      @mousemove="onMouseMove"
      @mouseleave="onMouseLeave"
    ></canvas>
    <!-- Tooltip -->
    <div v-if="tooltip" class="absolute pointer-events-none bg-black/80 text-white text-xs rounded-lg px-3 py-1.5 whitespace-nowrap z-10"
      :style="{ left: tooltip.x + 'px', top: tooltip.y + 'px', transform: 'translate(-50%, -100%)' }">
      <div class="tabular-nums font-mono">{{ tooltip.value }}</div>
      <div class="text-white/50">{{ tooltip.time }}</div>
    </div>
  </div>
</template>

<script setup>
import { ref, watch, onMounted, onUnmounted, reactive } from 'vue'
import { effectiveTheme } from '../../composables/useTheme'

const props = defineProps({
  data: { type: Array, default: () => [] },
  height: { type: Number, default: 120 },
  color: { type: String, default: '#888' },
  fillOpacity: { type: Number, default: 0.15 },
  min: { type: Number, default: undefined },
  max: { type: Number, default: undefined },
  unit: { type: String, default: '' },
  rangeMinutes: { type: Number, default: 60 },
})

const canvas = ref(null)
const tooltip = ref(null)
let resizeObserver = null

// Cache layout for hover lookups
let layoutCache = null

function draw() {
  const el = canvas.value
  if (!el) return

  const dpr = window.devicePixelRatio || 1
  const rect = el.getBoundingClientRect()
  el.width = rect.width * dpr
  el.height = rect.height * dpr

  const ctx = el.getContext('2d')
  ctx.scale(dpr, dpr)

  const w = rect.width
  const h = rect.height
  const pad = { top: 12, bottom: 24, left: 44, right: 8 }
  const plotW = w - pad.left - pad.right
  const plotH = h - pad.top - pad.bottom

  const isDark = effectiveTheme.value === 'dark'
  const gridColor = isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)'
  const textColor = isDark ? 'rgba(255,255,255,0.3)' : 'rgba(0,0,0,0.3)'

  ctx.clearRect(0, 0, w, h)

  const hasTimestamps = props.data.length > 0 && typeof props.data[0] === 'object' && props.data[0].t !== undefined
  const points = hasTimestamps ? props.data : props.data.map((v, i) => ({ t: i, v }))
  const values = points.map(p => p.v)

  const minVal = props.min !== undefined ? props.min : (values.length ? Math.min(...values) : 0)
  const maxVal = props.max !== undefined ? props.max : (values.length ? Math.max(...values) : 100)
  const range = maxVal - minVal || 1

  const now = Date.now()
  const rangeMs = props.rangeMinutes * 60 * 1000
  const timeStart = now - rangeMs
  const timeEnd = now

  // Grid lines (3 horizontal)
  ctx.strokeStyle = gridColor
  ctx.lineWidth = 1
  for (let i = 0; i <= 2; i++) {
    const y = pad.top + (plotH * i) / 2
    ctx.beginPath()
    ctx.moveTo(pad.left, y)
    ctx.lineTo(w - pad.right, y)
    ctx.stroke()
  }

  // Y axis labels (left side)
  ctx.fillStyle = textColor
  ctx.font = '10px sans-serif'
  ctx.textAlign = 'right'
  ctx.textBaseline = 'middle'
  ctx.fillText(fmtVal(maxVal), pad.left - 6, pad.top)
  ctx.fillText(fmtVal((maxVal + minVal) / 2), pad.left - 6, pad.top + plotH / 2)
  ctx.fillText(fmtVal(minVal), pad.left - 6, pad.top + plotH)

  // X axis time labels (bottom)
  ctx.textAlign = 'center'
  ctx.textBaseline = 'top'
  const tickCount = 4
  for (let i = 0; i <= tickCount; i++) {
    const t = timeStart + (rangeMs * i) / tickCount
    const x = pad.left + (plotW * i) / tickCount
    const d = new Date(t)
    const label = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
    ctx.fillText(label, x, h - pad.bottom + 8)
  }

  // Data
  const getX = (t) => pad.left + ((t - timeStart) / (timeEnd - timeStart)) * plotW
  const getY = (v) => pad.top + plotH - ((v - minVal) / range) * plotH

  const visiblePoints = hasTimestamps
    ? points.filter(p => p.t >= timeStart && p.t <= timeEnd)
    : points

  // Cache for hover
  layoutCache = { pad, plotW, plotH, timeStart, timeEnd, minVal, maxVal, range, visiblePoints, hasTimestamps, getX, getY }

  if (!visiblePoints.length) return

  // Fill
  ctx.beginPath()
  ctx.moveTo(getX(visiblePoints[0].t), pad.top + plotH)
  for (const p of visiblePoints) ctx.lineTo(getX(p.t), getY(p.v))
  ctx.lineTo(getX(visiblePoints[visiblePoints.length - 1].t), pad.top + plotH)
  ctx.closePath()
  ctx.fillStyle = hexToRgba(props.color, props.fillOpacity)
  ctx.fill()

  // Line
  ctx.beginPath()
  for (let i = 0; i < visiblePoints.length; i++) {
    const x = getX(visiblePoints[i].t)
    const y = getY(visiblePoints[i].v)
    if (i === 0) ctx.moveTo(x, y)
    else ctx.lineTo(x, y)
  }
  ctx.strokeStyle = props.color
  ctx.lineWidth = 1.5
  ctx.stroke()
}

function onMouseMove(e) {
  if (!layoutCache || !layoutCache.visiblePoints.length) { tooltip.value = null; return }
  const rect = canvas.value.getBoundingClientRect()
  const mx = e.clientX - rect.left
  const my = e.clientY - rect.top
  const { pad, visiblePoints, getX, getY } = layoutCache

  // Find nearest point
  let nearest = null
  let minDist = Infinity
  for (const p of visiblePoints) {
    const px = getX(p.t)
    const dist = Math.abs(px - mx)
    if (dist < minDist) { minDist = dist; nearest = p }
  }
  if (!nearest || minDist > 40) { tooltip.value = null; return }

  const px = getX(nearest.t)
  const py = getY(nearest.v)
  const d = new Date(nearest.t)
  const time = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}:${String(d.getSeconds()).padStart(2, '0')}`

  tooltip.value = {
    x: px,
    y: py - 8,
    value: fmtVal(nearest.v),
    time,
  }

  // Draw crosshair + dot
  draw()
  const el = canvas.value
  const dpr = window.devicePixelRatio || 1
  const ctx = el.getContext('2d')
  ctx.scale(dpr, dpr)
  const isDark = effectiveTheme.value === 'dark'

  // Vertical crosshair
  ctx.beginPath()
  ctx.moveTo(px, pad.top)
  ctx.lineTo(px, pad.top + layoutCache.plotH)
  ctx.strokeStyle = isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.1)'
  ctx.lineWidth = 1
  ctx.setLineDash([4, 3])
  ctx.stroke()
  ctx.setLineDash([])

  // Dot
  ctx.beginPath()
  ctx.arc(px, py, 4, 0, Math.PI * 2)
  ctx.fillStyle = props.color
  ctx.fill()
  ctx.strokeStyle = isDark ? '#1e1e1e' : '#fff'
  ctx.lineWidth = 2
  ctx.stroke()
}

function onMouseLeave() {
  tooltip.value = null
  draw()
}

function fmtVal(v) {
  if (props.unit === '%') return Math.round(v) + '%'
  if (props.unit === 'GB') return (v / (1024 * 1024 * 1024)).toFixed(1) + ' GB'
  if (props.unit === 'MB') return (v / (1024 * 1024)).toFixed(0) + ' MB'
  return Number(v).toFixed(2)
}

function hexToRgba(hex, alpha) {
  if (hex.startsWith('#')) {
    const r = parseInt(hex.slice(1, 3), 16)
    const g = parseInt(hex.slice(3, 5), 16)
    const b = parseInt(hex.slice(5, 7), 16)
    return `rgba(${r},${g},${b},${alpha})`
  }
  return hex
}

watch(() => [props.data, props.color, props.rangeMinutes, effectiveTheme.value], draw, { deep: true })

onMounted(() => {
  draw()
  resizeObserver = new ResizeObserver(draw)
  if (canvas.value) resizeObserver.observe(canvas.value)
})

onUnmounted(() => {
  resizeObserver?.disconnect()
})
</script>
