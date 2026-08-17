<template>
  <dialog ref="dialogEl" class="modal" @close="onClose">
    <div class="modal-box max-w-xs flex flex-col items-center gap-4">
      <h3 class="font-bold text-base">{{ titleText }}</h3>
      <p class="text-sm min-h-5" :class="isError ? 'text-error' : 'text-base-content/50'">
        {{ message || ' ' }}
      </p>

      <!-- 九宫格 -->
      <svg
        ref="gridEl"
        :width="gridSize"
        :height="gridSize"
        class="touch-none select-none"
        :class="{ 'animate-shake': shaking }"
        @mousedown.prevent="onDown"
        @mousemove.prevent="onMove"
        @mouseup.prevent="onUp"
        @mouseleave.prevent="onUp"
        @touchstart.prevent="onTouchStart"
        @touchmove.prevent="onTouchMove"
        @touchend.prevent="onUp"
      >
        <!-- 已连线 -->
        <polyline
          v-if="selected.length"
          :points="linePoints"
          fill="none"
          :stroke="isError ? '#ef4444' : '#3b82f6'"
          stroke-width="4"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <!-- 到指针的临时连线 -->
        <line
          v-if="selected.length && pointer"
          :x1="dotCenter(selected[selected.length - 1]).x"
          :y1="dotCenter(selected[selected.length - 1]).y"
          :x2="pointer.x"
          :y2="pointer.y"
          :stroke="isError ? '#ef4444' : '#3b82f6'"
          stroke-width="4"
          stroke-linecap="round"
        />
        <!-- 9 个圆点 -->
        <circle
          v-for="i in 9"
          :key="i - 1"
          :cx="dotCenter(i - 1).x"
          :cy="dotCenter(i - 1).y"
          :r="selected.includes(i - 1) ? 12 : 10"
          :fill="selected.includes(i - 1) ? (isError ? '#ef4444' : '#3b82f6') : '#9ca3af40'"
          stroke="#9ca3af"
          stroke-width="1.5"
        />
      </svg>

      <button class="btn btn-ghost btn-sm w-32" @click="close">{{ $t('common.cancel') }}</button>
    </div>
    <form method="dialog" class="modal-backdrop"><button>close</button></form>
  </dialog>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { usePrivacy } from '../../composables/usePrivacy'

const { t } = useI18n()
const { verifyPattern, setPattern } = usePrivacy()

const props = defineProps({
  // 'verify' 校验已有图案 / 'setNew' 设置新图案
  purpose: { type: String, default: 'verify' },
})
const emit = defineEmits(['success', 'cancel'])

const gridSize = 240
const minDots = 4

const dialogEl = ref(null)
const gridEl = ref(null)
const selected = ref([])
const pointer = ref(null)
const drawing = ref(false)
const firstPass = ref(null) // setNew 第一次绘制
const message = ref('')
const isError = ref(false)
const shaking = ref(false)

const titleText = computed(() => {
  if (props.purpose === 'verify') return t('privacy.drawToUnlock')
  return firstPass.value == null ? t('privacy.drawNew') : t('privacy.drawConfirm')
})

// 点中心坐标（index = row*3 + col）
function dotCenter(index) {
  const cell = gridSize / 3
  const col = index % 3
  const row = Math.floor(index / 3)
  return { x: (col + 0.5) * cell, y: (row + 0.5) * cell }
}

const linePoints = computed(() =>
  selected.value.map(i => { const c = dotCenter(i); return `${c.x},${c.y}` }).join(' ')
)

function localPoint(clientX, clientY) {
  const rect = gridEl.value.getBoundingClientRect()
  return { x: clientX - rect.left, y: clientY - rect.top }
}

function hitTest(pt) {
  const threshold = (gridSize / 3) * 0.34
  for (let i = 0; i < 9; i++) {
    if (selected.value.includes(i)) continue
    const c = dotCenter(i)
    if (Math.hypot(pt.x - c.x, pt.y - c.y) < threshold) {
      selected.value.push(i)
    }
  }
}

function beginAt(pt) {
  if (isError.value) resetCurrent()
  drawing.value = true
  pointer.value = pt
  hitTest(pt)
}

function onDown(e) { beginAt(localPoint(e.clientX, e.clientY)) }
function onMove(e) {
  if (!drawing.value) return
  const pt = localPoint(e.clientX, e.clientY)
  pointer.value = pt
  hitTest(pt)
}
function onTouchStart(e) {
  const t0 = e.touches[0]
  beginAt(localPoint(t0.clientX, t0.clientY))
}
function onTouchMove(e) {
  if (!drawing.value) return
  const t0 = e.touches[0]
  const pt = localPoint(t0.clientX, t0.clientY)
  pointer.value = pt
  hitTest(pt)
}

async function onUp() {
  if (!drawing.value) return
  drawing.value = false
  pointer.value = null
  await finish()
}

function resetCurrent() {
  selected.value = []
  isError.value = false
  message.value = firstPass.value != null ? t('privacy.drawConfirm') : ''
}

function triggerShake() {
  shaking.value = true
  setTimeout(() => { shaking.value = false }, 400)
}

async function finish() {
  if (selected.value.length < minDots) {
    if (selected.value.length > 0) {
      message.value = t('privacy.minDots', { n: minDots })
      isError.value = true
      triggerShake()
    }
    selected.value = []
    return
  }

  const dots = [...selected.value]

  if (props.purpose === 'verify') {
    if (await verifyPattern(dots)) {
      emit('success')
      close()
    } else {
      message.value = t('privacy.wrongPattern')
      isError.value = true
      triggerShake()
    }
    return
  }

  // setNew
  if (firstPass.value == null) {
    firstPass.value = dots
    selected.value = []
    message.value = t('privacy.drawConfirm')
  } else if (JSON.stringify(firstPass.value) === JSON.stringify(dots)) {
    await setPattern(dots)
    emit('success')
    close()
  } else {
    message.value = t('privacy.mismatch')
    isError.value = true
    firstPass.value = null
    triggerShake()
  }
}

function resetAll() {
  selected.value = []
  pointer.value = null
  drawing.value = false
  firstPass.value = null
  message.value = ''
  isError.value = false
}

function show() {
  resetAll()
  dialogEl.value?.showModal()
}
function close() {
  dialogEl.value?.close()
}
function onClose() {
  emit('cancel')
}

defineExpose({ show, close })
</script>

<style scoped>
@keyframes shake {
  0%, 100% { transform: translateX(0); }
  20%, 60% { transform: translateX(-8px); }
  40%, 80% { transform: translateX(8px); }
}
.animate-shake { animation: shake 0.4s ease; }
</style>
