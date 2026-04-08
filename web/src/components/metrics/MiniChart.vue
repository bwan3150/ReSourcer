<template>
  <canvas ref="canvas" class="w-full" :style="{ height: height + 'px' }"></canvas>
</template>

<script setup>
import { ref, watch, onMounted, onUnmounted } from 'vue'
import { effectiveTheme } from '../../composables/useTheme'

const props = defineProps({
  data: { type: Array, default: () => [] },
  height: { type: Number, default: 120 },
  color: { type: String, default: '#888' },
  fillOpacity: { type: Number, default: 0.1 },
  min: { type: Number, default: undefined },
  max: { type: Number, default: undefined },
  unit: { type: String, default: '' },
})

const canvas = ref(null)
let resizeObserver = null

function draw() {
  const el = canvas.value
  if (!el || !props.data.length) return

  const dpr = window.devicePixelRatio || 1
  const rect = el.getBoundingClientRect()
  el.width = rect.width * dpr
  el.height = rect.height * dpr

  const ctx = el.getContext('2d')
  ctx.scale(dpr, dpr)

  const w = rect.width
  const h = rect.height
  const data = props.data
  const pad = { top: 8, bottom: 20, left: 4, right: 4 }

  const plotW = w - pad.left - pad.right
  const plotH = h - pad.top - pad.bottom

  const minVal = props.min !== undefined ? props.min : Math.min(...data)
  const maxVal = props.max !== undefined ? props.max : Math.max(...data)
  const range = maxVal - minVal || 1

  // Clear
  ctx.clearRect(0, 0, w, h)

  // Grid lines
  const isDark = effectiveTheme.value === 'dark'
  const gridColor = isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)'
  const textColor = isDark ? 'rgba(255,255,255,0.3)' : 'rgba(0,0,0,0.3)'

  ctx.strokeStyle = gridColor
  ctx.lineWidth = 1
  for (let i = 0; i <= 2; i++) {
    const y = pad.top + (plotH * i) / 2
    ctx.beginPath()
    ctx.moveTo(pad.left, y)
    ctx.lineTo(w - pad.right, y)
    ctx.stroke()
  }

  // Scale labels
  ctx.fillStyle = textColor
  ctx.font = '10px sans-serif'
  ctx.textAlign = 'right'
  const formatVal = (v) => {
    if (props.unit === '%') return Math.round(v) + '%'
    if (props.unit === 'GB') return (v / (1024 * 1024 * 1024)).toFixed(1) + 'G'
    if (props.unit === 'MB') return (v / (1024 * 1024)).toFixed(0) + 'M'
    return v.toFixed(1)
  }
  ctx.fillText(formatVal(maxVal), w - pad.right, pad.top + 10)
  ctx.fillText(formatVal(minVal), w - pad.right, h - pad.bottom + 12)

  // Data points
  const stepX = data.length > 1 ? plotW / (data.length - 1) : 0

  const getX = (i) => pad.left + i * stepX
  const getY = (v) => pad.top + plotH - ((v - minVal) / range) * plotH

  // Fill
  ctx.beginPath()
  ctx.moveTo(getX(0), pad.top + plotH)
  for (let i = 0; i < data.length; i++) {
    ctx.lineTo(getX(i), getY(data[i]))
  }
  ctx.lineTo(getX(data.length - 1), pad.top + plotH)
  ctx.closePath()
  ctx.fillStyle = props.color.replace(')', `, ${props.fillOpacity})`).replace('rgb(', 'rgba(')
  // Handle hex colors
  if (props.color.startsWith('#')) {
    const r = parseInt(props.color.slice(1, 3), 16)
    const g = parseInt(props.color.slice(3, 5), 16)
    const b = parseInt(props.color.slice(5, 7), 16)
    ctx.fillStyle = `rgba(${r},${g},${b},${props.fillOpacity})`
  }
  ctx.fill()

  // Line
  ctx.beginPath()
  for (let i = 0; i < data.length; i++) {
    if (i === 0) ctx.moveTo(getX(i), getY(data[i]))
    else ctx.lineTo(getX(i), getY(data[i]))
  }
  ctx.strokeStyle = props.color
  ctx.lineWidth = 1.5
  ctx.stroke()
}

watch(() => [props.data, props.color, effectiveTheme.value], draw, { deep: true })

onMounted(() => {
  draw()
  resizeObserver = new ResizeObserver(draw)
  if (canvas.value) resizeObserver.observe(canvas.value)
})

onUnmounted(() => {
  resizeObserver?.disconnect()
})
</script>
