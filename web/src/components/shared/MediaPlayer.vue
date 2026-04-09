<template>
  <div
    class="relative h-full w-full overflow-hidden"
    :class="bgClass"
    tabindex="0"
  >
    <!-- PDF viewer (own scroll, no zoom transform) -->
    <PdfViewer
      v-if="type === 'pdf'"
      ref="pdfViewer"
      :src="src"
      class="absolute inset-0"
    />

    <!-- Zoomable content container (non-PDF) -->
    <div
      v-else
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

        <!-- Video -->
        <video
          v-else-if="type === 'video'"
          ref="videoEl"
          :src="src"
          class="max-w-[100vw] max-h-[100vh] object-contain"
          preload="auto"
          playsinline
          @loadedmetadata="onMetadata"
          @timeupdate="onTimeUpdate"
          @progress="onProgress"
          @play="playing = true"
          @pause="playing = false"
          @ended="playing = false; emit('ended')"
          @volumechange="onVolumeChange"
          @waiting="buffering = true"
          @playing="buffering = false"
          @canplay="buffering = false"
        />

        <!-- Audio -->
        <template v-else-if="type === 'audio'">
          <audio
            ref="videoEl"
            :src="src"
            preload="auto"
            @loadedmetadata="onMetadata"
            @timeupdate="onTimeUpdate"
            @progress="onProgress"
            @play="playing = true"
            @pause="playing = false"
            @ended="playing = false; emit('ended')"
            @volumechange="onVolumeChange"
            @waiting="buffering = true"
            @playing="buffering = false"
            @canplay="buffering = false"
          />
          <div class="flex flex-col items-center gap-3">
            <img v-if="audioCover" :src="audioCover" class="max-w-[300px] max-h-[300px] rounded-lg shadow-lg object-contain" draggable="false" />
            <component v-else :is="fileIconData.icon" :size="56" :style="{ color: fileIconData.color }" />
            <span class="text-sm text-base-content/30">{{ fileName }}</span>
          </div>
        </template>

        <!-- Other -->
        <div v-else class="flex flex-col items-center gap-3">
          <component :is="fileIconData.icon" :size="56" :style="{ color: fileIconData.color }" />
          <span class="text-sm text-base-content/30">{{ fileName }}</span>
        </div>
      </div>
    </div>

    <!-- Buffering spinner -->
    <transition name="fade">
      <div v-if="buffering && hasControls" class="absolute inset-0 flex items-center justify-center z-5 pointer-events-none">
        <span class="loading loading-spinner loading-lg text-white/60"></span>
      </div>
    </transition>

    <!-- Floating controls overlay (unaffected by zoom) -->
    <transition name="fade">
      <div
        v-if="controlsVisible && (hasControls || showNav)"
        class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/70 to-transparent pt-10 pb-3 px-4 z-10"
        @click.stop
      >
        <div v-if="hasControls" class="mb-2 relative h-4 flex items-center group cursor-pointer" @click="onSeekClick">
          <!-- Buffer bar (gray) -->
          <div class="absolute left-0 top-1/2 -translate-y-1/2 h-1 rounded-full bg-white/20 w-full">
            <div class="h-full rounded-full bg-white/30 transition-all duration-300"
              :style="{ width: (duration ? (bufferedEnd / duration) * 100 : 0) + '%' }"></div>
          </div>
          <!-- Progress bar (white) -->
          <div class="absolute left-0 top-1/2 -translate-y-1/2 h-1 group-hover:h-1.5 rounded-full bg-white/80 transition-all"
            :style="{ width: (duration ? (currentTime / duration) * 100 : 0) + '%' }"></div>
          <!-- Seek thumb (visible on hover) -->
          <div class="absolute top-1/2 -translate-y-1/2 w-3 h-3 rounded-full bg-white opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none"
            :style="{ left: (duration ? (currentTime / duration) * 100 : 0) + '%', transform: 'translate(-50%, -50%)' }"></div>
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
          <!-- Playback mode toggle -->
          <button v-if="showNav" class="btn btn-ghost btn-xs btn-square text-white" @click="emit('cycle-mode')">
            <component :is="modeIcon" :size="16" />
          </button>
          <!-- Playlist toggle -->
          <button v-if="showNav" class="btn btn-ghost btn-xs btn-square text-white" @click="emit('toggle-playlist')">
            <ListMusic :size="16" />
          </button>
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
import { Play, Pause, SkipBack, SkipForward, Volume2, Volume1, VolumeX, Music, ListMusic, Repeat, Repeat1, Shuffle } from 'lucide-vue-next'
import { effectiveTheme } from '../../composables/useTheme'
import { getFileIcon } from '../../composables/useFileIcon'
import PdfViewer from './PdfViewer.vue'

const props = defineProps({
  src: { type: String, default: '' },
  type: { type: String, default: 'other' },
  fileName: { type: String, default: '' },
  showNav: { type: Boolean, default: false },
  hasPrev: { type: Boolean, default: false },
  hasNext: { type: Boolean, default: false },
  autoplay: { type: Boolean, default: true },
  coverUrl: { type: String, default: '' },
  playbackMode: { type: String, default: 'sequential' },
})

const emit = defineEmits(['prev', 'next', 'ended', 'toggle-playlist', 'cycle-mode'])

const videoEl = ref(null)
const contentArea = ref(null)
const pdfViewer = ref(null)
const playing = ref(false)
const currentTime = ref(0)
const duration = ref(0)
const volume = ref(parseFloat(localStorage.getItem('player_volume') ?? '1'))
const muted = ref(localStorage.getItem('player_muted') === 'true')
const controlsVisible = ref(true)
const buffering = ref(false)
const bufferedEnd = ref(0)
const audioCover = ref(null)

// Zoom & pan state
const scale = ref(1)
const panX = ref(0)
const panY = ref(0)
const dragging = ref(false)
let dragStartX = 0, dragStartY = 0, panStartX = 0, panStartY = 0

const hasControls = computed(() => ['video', 'audio'].includes(props.type))
const zoomable = computed(() => ['image', 'gif', 'video'].includes(props.type))

const bgClass = computed(() => effectiveTheme.value === 'dark' ? 'bg-black' : 'bg-white')
const modeIcon = computed(() => {
  if (props.playbackMode === 'repeat') return Repeat1
  if (props.playbackMode === 'shuffle') return Shuffle
  return Repeat
})
const fileIconData = computed(() => getFileIcon(props.type, props.fileName?.split('.').pop() || ''))

const contentTransform = computed(() => ({
  transform: `translate(${panX.value}px, ${panY.value}px) scale(${scale.value})`,
  transformOrigin: 'center center',
}))

// Reset on src change
watch(() => props.src, async () => {
  playing.value = false
  currentTime.value = 0
  duration.value = 0
  bufferedEnd.value = 0
  buffering.value = false
  audioCover.value = null
  controlsVisible.value = true
  resetZoom()
  // Load audio cover
  if (props.type === 'audio' && props.coverUrl) {
    const img = new window.Image()
    img.onload = () => { audioCover.value = props.coverUrl }
    img.onerror = () => { audioCover.value = null }
    img.src = props.coverUrl
  }
  if (hasControls.value && props.autoplay) {
    await nextTick()
    // Apply persisted volume/mute to new media element
    if (videoEl.value) {
      videoEl.value.volume = volume.value
      videoEl.value.muted = muted.value
    }
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



function onMetadata() {
  duration.value = videoEl.value?.duration || 0
  if (videoEl.value) {
    videoEl.value.volume = volume.value
    videoEl.value.muted = muted.value
  }
}
function onTimeUpdate() { currentTime.value = videoEl.value?.currentTime || 0 }
function onProgress() {
  if (!videoEl.value) return
  const buf = videoEl.value.buffered
  if (buf.length > 0) {
    bufferedEnd.value = buf.end(buf.length - 1)
  }
}
function onVolumeChange() {
  volume.value = videoEl.value?.volume || 0
  muted.value = videoEl.value?.muted || false
  localStorage.setItem('player_volume', String(volume.value))
  localStorage.setItem('player_muted', String(muted.value))
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

function onSeekClick(e) {
  if (!videoEl.value || !duration.value) return
  const rect = e.currentTarget.getBoundingClientRect()
  const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width))
  videoEl.value.currentTime = ratio * duration.value
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

function seekBy(seconds) {
  if (!videoEl.value) return
  videoEl.value.currentTime = Math.max(0, Math.min(videoEl.value.duration || 0, videoEl.value.currentTime + seconds))
}

function changeVolume(delta) {
  if (!videoEl.value) return
  const v = Math.max(0, Math.min(1, videoEl.value.volume + delta))
  videoEl.value.volume = v
  videoEl.value.muted = v === 0
}

function zoomBy(delta) {
  if (!zoomable.value) return
  const newScale = Math.min(10, Math.max(0.1, scale.value + delta))
  scale.value = newScale
  if (Math.abs(newScale - 1) < 0.05) { scale.value = 1; panX.value = 0; panY.value = 0 }
}

function panBy(dx, dy) {
  if (!zoomable.value) return
  panX.value += dx
  panY.value += dy
}

function pdfToggleFitMode() { pdfViewer.value?.toggleFitMode() }
function pdfScrollBy(dx, dy) { pdfViewer.value?.scrollBy(dx, dy) }

function formatTime(s) {
  if (!s || !isFinite(s)) return '0:00'
  const m = Math.floor(s / 60)
  const sec = Math.floor(s % 60)
  return `${m}:${sec.toString().padStart(2, '0')}`
}

defineExpose({
  togglePlay, seekBy, changeVolume, toggleMute, zoomBy, panBy, resetZoom,
  pdfToggleFitMode, pdfScrollBy,
  playing, muted, volume, controlsVisible,
})
</script>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.3s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
