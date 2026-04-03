<template>
  <div
    class="relative h-full w-full overflow-hidden"
    :class="bgClass"
    @keydown="onKeydown"
    tabindex="0"
  >
    <!-- Zoomable content container -->
    <div
      ref="contentArea"
      class="absolute inset-0 flex items-center justify-center overflow-hidden"
      @wheel.prevent="onWheel"
      @pointerdown="onPointerDown"
      @pointermove="onPointerMove"
      @pointerup="onPointerUp"
      @pointerleave="onPointerUp"
    >
      <div
        :style="contentTransform"
        class="will-change-transform"
      >
        <!-- Image / GIF -->
        <img
          v-if="type === 'image' || type === 'gif'"
          :src="src"
          :alt="fileName"
          class="max-w-[100vw] max-h-[100vh] object-contain select-none"
          draggable="false"
        />

        <!-- PDF -->
        <iframe
          v-else-if="type === 'pdf'"
          :src="src"
          class="border-0"
          :style="{ width: '100vw', height: '100vh' }"
        />

        <!-- Video -->
        <video
          v-else-if="type === 'video'"
          ref="videoEl"
          :src="src"
          class="max-w-[100vw] max-h-[100vh] object-contain"
          preload="metadata"
          playsinline
          @loadedmetadata="onMetadata"
          @timeupdate="onTimeUpdate"
          @play="playing = true"
          @pause="playing = false"
          @ended="playing = false"
          @volumechange="onVolumeChange"
        />

        <!-- Audio -->
        <template v-else-if="type === 'audio'">
          <audio
            ref="videoEl"
            :src="src"
            preload="metadata"
            @loadedmetadata="onMetadata"
            @timeupdate="onTimeUpdate"
            @play="playing = true"
            @pause="playing = false"
            @ended="playing = false"
            @volumechange="onVolumeChange"
          />
          <div class="flex flex-col items-center gap-2 text-base-content/20">
            <Music :size="48" />
            <span class="text-sm">{{ fileName }}</span>
          </div>
        </template>

        <!-- Other -->
        <div v-else class="text-base-content/20 text-sm">{{ fileName }}</div>
      </div>
    </div>

    <!-- Floating controls overlay (unaffected by zoom) -->
    <transition name="fade">
      <div
        v-if="controlsVisible && (hasControls || showNav)"
        class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/70 to-transparent pt-10 pb-3 px-4 z-10"
        @click.stop
      >
        <div v-if="hasControls" class="mb-2">
          <input
            type="range" min="0" :max="duration || 0" :value="currentTime" step="0.1"
            class="range range-xs w-full" style="--range-shdw: transparent;" @input="onSeek"
          />
        </div>
        <div class="flex items-center gap-2">
          <button v-if="showNav" class="btn btn-ghost btn-xs btn-square text-white" @click="$emit('prev')" :disabled="!hasPrev">
            <SkipBack :size="16" />
          </button>
          <button v-if="hasControls" class="btn btn-ghost btn-sm btn-square text-white" @click="togglePlay">
            <Pause v-if="playing" :size="20" />
            <Play v-else :size="20" />
          </button>
          <button v-if="showNav" class="btn btn-ghost btn-xs btn-square text-white" @click="$emit('next')" :disabled="!hasNext">
            <SkipForward :size="16" />
          </button>
          <template v-if="hasControls">
            <span class="text-xs text-white/60 tabular-nums ml-1">{{ formatTime(currentTime) }} / {{ formatTime(duration) }}</span>
          </template>
          <div class="flex-1"></div>
          <!-- Reset zoom -->
          <button v-if="scale !== 1" class="btn btn-ghost btn-xs text-white" @click="resetZoom">
            {{ Math.round(scale * 100) }}%
          </button>
          <div v-if="hasControls" class="flex items-center gap-1">
            <button class="btn btn-ghost btn-xs btn-square text-white" @click="toggleMute">
              <VolumeX v-if="muted || volume === 0" :size="16" />
              <Volume1 v-else-if="volume < 0.5" :size="16" />
              <Volume2 v-else :size="16" />
            </button>
            <input
              type="range" min="0" max="1" :value="muted ? 0 : volume" step="0.01"
              class="range range-xs w-20" style="--range-shdw: transparent;" @input="onVolume"
            />
          </div>
        </div>
      </div>
    </transition>
  </div>
</template>

<script setup>
import { ref, computed, watch, nextTick } from 'vue'
import { Play, Pause, SkipBack, SkipForward, Volume2, Volume1, VolumeX, Music } from 'lucide-vue-next'
import { effectiveTheme } from '../../composables/useTheme'

const props = defineProps({
  src: { type: String, default: '' },
  type: { type: String, default: 'other' },
  fileName: { type: String, default: '' },
  showNav: { type: Boolean, default: false },
  hasPrev: { type: Boolean, default: false },
  hasNext: { type: Boolean, default: false },
  autoplay: { type: Boolean, default: true },
})

const emit = defineEmits(['prev', 'next'])

const videoEl = ref(null)
const contentArea = ref(null)
const playing = ref(false)
const currentTime = ref(0)
const duration = ref(0)
const volume = ref(1)
const muted = ref(false)
const controlsVisible = ref(true) // always visible for now; will be toggled via keyboard shortcut later

// Zoom & pan state
const scale = ref(1)
const panX = ref(0)
const panY = ref(0)
const dragging = ref(false)
let dragStartX = 0, dragStartY = 0, panStartX = 0, panStartY = 0

const hasControls = computed(() => ['video', 'audio'].includes(props.type))
const zoomable = computed(() => ['image', 'gif', 'video', 'pdf'].includes(props.type))

const bgClass = computed(() => effectiveTheme.value === 'dark' ? 'bg-black' : 'bg-white')

const contentTransform = computed(() => ({
  transform: `translate(${panX.value}px, ${panY.value}px) scale(${scale.value})`,
  transformOrigin: 'center center',
}))

// Reset on src change
watch(() => props.src, async () => {
  playing.value = false
  currentTime.value = 0
  duration.value = 0
  controlsVisible.value = true
  resetZoom()
  if (hasControls.value && props.autoplay) {
    await nextTick()
    videoEl.value?.play()?.catch(() => {})
  }
}, { immediate: true })

function onWheel(e) {
  if (!zoomable.value) return
  const delta = -e.deltaY * 0.01
  const newScale = Math.min(10, Math.max(0.1, scale.value + delta * scale.value))
  scale.value = newScale

  // Reset pan if back to 1x
  if (Math.abs(newScale - 1) < 0.05) {
    scale.value = 1
    panX.value = 0
    panY.value = 0
  }
}

// Pan via drag (only when zoomed in)
function onPointerDown(e) {
  if (!zoomable.value || scale.value <= 1) return
  dragging.value = true
  dragStartX = e.clientX
  dragStartY = e.clientY
  panStartX = panX.value
  panStartY = panY.value
  ;(e.target).setPointerCapture?.(e.pointerId)
}

function onPointerMove(e) {
  if (!dragging.value) return
  panX.value = panStartX + (e.clientX - dragStartX)
  panY.value = panStartY + (e.clientY - dragStartY)
}

function onPointerUp() {
  dragging.value = false
}

function resetZoom() {
  scale.value = 1
  panX.value = 0
  panY.value = 0
}



function onMetadata() { duration.value = videoEl.value?.duration || 0 }
function onTimeUpdate() { currentTime.value = videoEl.value?.currentTime || 0 }
function onVolumeChange() {
  volume.value = videoEl.value?.volume || 0
  muted.value = videoEl.value?.muted || false
}

function togglePlay() {
  if (!videoEl.value) return
  if (videoEl.value.paused) videoEl.value.play()
  else videoEl.value.pause()
}

function onSeek(e) {
  if (!videoEl.value) return
  videoEl.value.currentTime = parseFloat(e.target.value)
}

function onVolume(e) {
  if (!videoEl.value) return
  const v = parseFloat(e.target.value)
  videoEl.value.volume = v
  videoEl.value.muted = v === 0
}

function toggleMute() {
  if (!videoEl.value) return
  videoEl.value.muted = !videoEl.value.muted
}

function onKeydown(e) {
  if (e.key === ' ' && hasControls.value) { e.preventDefault(); togglePlay() }
  if (e.key === '0') resetZoom()
}

function formatTime(s) {
  if (!s || !isFinite(s)) return '0:00'
  const m = Math.floor(s / 60)
  const sec = Math.floor(s % 60)
  return `${m}:${sec.toString().padStart(2, '0')}`
}
</script>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.3s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
