<template>
  <AppLayout>
    <!-- Header (hidden when previewing) -->
    <template v-if="!previewFile" #header>
      <div class="flex items-center gap-0.5 flex-1 min-w-0 overflow-hidden text-sm">
        <template v-for="(crumb, i) in breadcrumbs" :key="crumb.path">
          <ChevronRight v-if="i > 0" :size="14" class="shrink-0 text-base-content/30" />
          <button
            class="btn btn-ghost btn-xs shrink-0"
            :class="{ 'font-bold': i === breadcrumbs.length - 1 }"
            @click="navigateTo(crumb.path)"
          >
            {{ crumb.name }}
          </button>
        </template>
      </div>
      <span class="text-xs text-base-content/40 shrink-0">{{ total }}</span>
      <button class="btn btn-ghost btn-sm btn-square" @click="reindexFolder" :disabled="reindexing" :title="$t('settings.reindex')">
        <span v-if="reindexing" class="loading loading-spinner loading-xs"></span>
        <RefreshCw v-else :size="16" />
      </button>
      <UploadArea ref="uploadArea" :target-folder="currentFolder" @uploaded="refreshFiles" />
    </template>

    <!-- Full-screen preview (covers header + sidebar content area) -->
    <template v-if="previewFile">
      <div class="flex flex-col h-full overflow-hidden">
        <!-- Preview header bar (hidden when UI is hidden via H key) -->
        <div v-show="!previewUIHidden" class="flex items-center gap-2 px-4 py-2 border-b border-base-300 shrink-0">
          <button class="btn btn-ghost btn-sm btn-square" @click="closePreview">
            <X :size="18" />
          </button>
          <span class="text-sm truncate flex-1">{{ previewFile.fileName }}</span>
          <span class="text-xs text-base-content/40">{{ playlistIndex + 1 }} / {{ playlist.length }}</span>
          <button class="btn btn-ghost btn-xs btn-square" @click="fileInfoDialog?.showModal()" :title="$t('gallery.fileInfo')">
            <Info :size="16" />
          </button>
        </div>
        <!-- Player fills remaining space -->
        <div class="flex-1 min-h-0">
          <MediaPlayer
            ref="mediaPlayer"
            :src="contentSrc"
            :type="previewFile.fileType"
            :file-name="previewFile.fileName"
            :cover-url="coverSrc"
            :playback-mode="playbackMode"
            :show-nav="true"
            :has-prev="playlist.length > 1"
            :has-next="playlist.length > 1"
            @prev="prevFile"
            @next="nextFile"
            @ended="onMediaEnded"
            @cycle-mode="cyclePlaybackMode"
            @toggle-playlist="showPlaylistPanel = !showPlaylistPanel"
          />
          <OsdFeedback ref="osd" />
          <!-- Playlist popup -->
          <transition name="slide-up">
            <div v-if="showPlaylistPanel && !previewUIHidden" class="absolute bottom-16 right-4 w-72 bg-black/60 backdrop-blur-md rounded-xl shadow-xl z-20 overflow-hidden">
              <div class="py-1 max-h-64 overflow-y-auto">
                <button
                  v-for="(item, i) in playlist"
                  :key="item.uuid"
                  class="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-left transition-colors"
                  :class="i === playlistIndex ? 'bg-white/15 text-white font-medium' : 'text-white/70 hover:bg-white/10'"
                  @click="jumpToPlaylistItem(item.uuid)"
                >
                  <span class="text-white/30 w-3 text-right shrink-0">{{ i + 1 }}</span>
                  <span class="truncate flex-1">{{ item.fileName }}</span>
                  <span class="text-white/30 uppercase shrink-0">{{ item.extension }}</span>
                </button>
              </div>
            </div>
          </transition>
        </div>
      </div>
    </template>

    <!-- Browse mode (folder sidebar + file grid) -->
    <template v-else>
      <div class="flex h-full">
        <FolderSidebar
          :root-folders="rootFolders"
          :source-folder="sourceFolder"
          :active-path="currentFolder"
          :loading="loadingFolders"
          @navigate="navigateTo"
        />
        <div
          ref="gridScrollContainer"
          class="flex-1 overflow-y-auto relative"
          @dragover.prevent="dragOver = true"
          @dragleave.prevent="dragOver = false"
          @drop.prevent="onDrop"
        >
          <!-- Drop overlay -->
          <div v-if="dragOver" class="absolute inset-0 z-20 flex items-center justify-center bg-base-100/80 border-2 border-dashed border-base-content/20 rounded-lg pointer-events-none">
            <span class="text-base-content/40 text-sm">{{ $t('gallery.dropHere') }}</span>
          </div>
          <FileGrid
            :files="files"
            :loading="switchingFolder"
            :loading-more="loadingMore"
            :has-more="hasMore"
            @preview="openPreview"
            @load-more="loadMore"
          />
        </div>
      </div>
    </template>

    <!-- File Info Dialog -->
    <dialog ref="fileInfoDialog" class="modal">
      <div class="modal-box" v-if="previewFile">
        <h3 class="font-bold text-lg mb-4">{{ $t('gallery.fileInfo') }}</h3>
        <div class="space-y-2 text-sm">
          <div class="flex justify-between">
            <span class="text-base-content/50">{{ $t('gallery.fileName') }}</span>
            <span class="truncate ml-4 text-right max-w-[60%]">{{ previewFile.fileName }}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/50">{{ $t('gallery.fileType') }}</span>
            <span>{{ previewFile.extension?.replace('.', '').toUpperCase() }}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/50">{{ $t('gallery.fileSize') }}</span>
            <span>{{ formatSize(previewFile.fileSize) }}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/50">{{ $t('gallery.created') }}</span>
            <span>{{ formatDate(previewFile.createdAt) }}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/50">{{ $t('gallery.modified') }}</span>
            <span>{{ formatDate(previewFile.modifiedAt) }}</span>
          </div>
          <div v-if="previewFile.sourceUrl" class="flex justify-between">
            <span class="text-base-content/50">{{ $t('gallery.sourceUrl') }}</span>
            <a :href="previewFile.sourceUrl" target="_blank" rel="noopener" class="truncate ml-4 text-right max-w-[60%] underline">{{ previewFile.sourceUrl }}</a>
          </div>
        </div>

        <!-- Tags -->
        <div class="mt-4 pt-4 border-t border-base-300">
          <div class="text-xs text-base-content/50 mb-2">{{ $t('gallery.tags') }}</div>
          <TagEditor
            :file-tags="fileTags"
            :all-tags="allTags"
            @update="onUpdateTags"
            @create="onCreateTag"
          />
        </div>

        <div class="flex gap-2 mt-6">
          <button class="btn btn-ghost btn-sm flex-1 gap-1" @click="fileInfoDialog?.close(); startRename(previewFile)">
            <Pencil :size="14" />
            {{ $t('common.rename') }}
          </button>
          <button class="btn btn-ghost btn-sm flex-1 gap-1" @click="fileInfoDialog?.close(); startMove(previewFile)">
            <FolderInput :size="14" />
            {{ $t('common.move') }}
          </button>
          <a :href="contentSrc" download class="btn btn-ghost btn-sm flex-1 gap-1">
            <Download :size="14" />
            {{ $t('common.download') }}
          </a>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>

    <!-- Rename Dialog -->
    <dialog ref="renameDialog" class="modal">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">{{ $t('common.rename') }}</h3>
        <input v-model="renameValue" class="input input-bordered w-full" @keyup.enter="doRename" />
        <div class="modal-action">
          <button class="btn" @click="renameDialog?.close()">{{ $t('common.cancel') }}</button>
          <button class="btn btn-neutral" @click="doRename" :disabled="!renameValue.trim()">{{ $t('common.confirm') }}</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>

    <!-- Move Dialog (folder browser) -->
    <dialog ref="moveDialog" class="modal">
      <div class="modal-box max-w-sm overflow-hidden">
        <h3 class="font-bold text-lg mb-3">{{ $t('gallery.moveTo') }}</h3>

        <!-- Breadcrumb -->
        <div class="flex items-center gap-0.5 text-xs mb-3 overflow-x-auto scrollbar-none">
          <template v-for="(crumb, i) in moveBreadcrumbs" :key="crumb.path">
            <ChevronRight v-if="i > 0" :size="12" class="shrink-0 text-base-content/30" />
            <button class="btn btn-ghost btn-xs shrink-0" @click="browseMoveTo(crumb.path)">
              {{ crumb.name }}
            </button>
          </template>
        </div>

        <!-- Select current browsed folder -->
        <div class="mb-2">
          <button
            class="btn btn-ghost btn-sm w-full justify-start gap-2 border border-base-300"
            :class="{ 'bg-base-300': moveTarget === moveBrowsePath }"
            @click="moveTarget = moveBrowsePath"
          >
            <Folder :size="16" class="shrink-0" />
            {{ $t('gallery.moveHere') }}
          </button>
        </div>

        <!-- Subfolder list -->
        <div class="space-y-0.5 max-h-52 overflow-y-auto">
          <button
            v-for="f in moveFolders"
            :key="f.path"
            class="btn btn-ghost btn-sm w-full justify-start gap-2 min-w-0"
            :class="{ 'bg-base-300': moveTarget === f.path }"
            @click="moveTarget = f.path"
            @dblclick="browseMoveTo(f.path)"
          >
            <Folder :size="16" class="shrink-0" />
            <span class="truncate flex-1 text-left min-w-0">{{ f.name }}</span>
            <ChevronRight :size="14" class="shrink-0 text-base-content/30" />
          </button>
          <div v-if="!moveFolders.length && !moveLoading" class="text-xs text-base-content/40 text-center py-4">
            {{ $t('gallery.noFolders') }}
          </div>
          <div v-if="moveLoading" class="flex justify-center py-4">
            <span class="loading loading-spinner loading-sm"></span>
          </div>
        </div>

        <div class="modal-action">
          <button class="btn" @click="moveDialog?.close()">{{ $t('common.cancel') }}</button>
          <button class="btn btn-neutral" @click="doMove" :disabled="!moveTarget">{{ $t('common.confirm') }}</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>
  </AppLayout>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import AppLayout from '../components/layout/AppLayout.vue'
import FolderSidebar from '../components/gallery/FolderSidebar.vue'
import FileGrid from '../components/gallery/FileGrid.vue'
import MediaPlayer from '../components/shared/MediaPlayer.vue'
import OsdFeedback from '../components/shared/OsdFeedback.vue'
import { useKeyboardShortcuts } from '../composables/useKeyboardShortcuts'
import { useTheme } from '../composables/useTheme'
import UploadArea from '../components/gallery/UploadArea.vue'
import TagEditor from '../components/gallery/TagEditor.vue'
import { Folder, ChevronRight, X, Pencil, FolderInput, RefreshCw, Info, Download } from 'lucide-vue-next'
import { contentUrl, thumbnailUrl } from '../api/preview'
import { useCurrentFolder } from '../composables/useCurrentFolder'
import * as indexerApi from '../api/indexer'
import * as playlistApi from '../api/playlist'
import * as configApi from '../api/config'
import * as fileApi from '../api/file'
import * as tagApi from '../api/tag'

const { t } = useI18n()
const PAGE_SIZE = 50

const { sourceFolder, currentFolder, setSourceFolder, setCurrentFolder } = useCurrentFolder()
const breadcrumbs = ref([])
const rootFolders = ref([])
const files = ref([])
const total = ref(0)
const offset = ref(0)
const hasMore = ref(false)
const loadingFolders = ref(false)
const switchingFolder = ref(false)
const loadingMore = ref(false)
const reindexing = ref(false)
const dragOver = ref(false)
const uploadArea = ref(null)

const previewFile = ref(null)
const playlist = ref([])
const playlistIndex = ref(0)
const playbackMode = ref('repeat') // repeat | sequential | shuffle
const filterByType = ref(localStorage.getItem('playlist_filterByType') === 'true')
const autoAdvanceSeconds = ref(parseInt(localStorage.getItem('playlist_autoAdvanceSeconds') || '8'))
const showPlaylistPanel = ref(false)
let autoAdvanceTimer = null
const contentSrc = computed(() => previewFile.value ? contentUrl(previewFile.value) : '')
const coverSrc = computed(() => previewFile.value ? thumbnailUrl(previewFile.value, 600) : '')
const mediaPlayer = ref(null)
function isMediaType() {
  return ['video', 'audio'].includes(previewFile.value?.fileType)
}
function isPdfType() {
  return previewFile.value?.fileType === 'pdf'
}
const osd = ref(null)
const previewUIHidden = ref(false)
const { mode: themeMode, cycle: cycleTheme } = useTheme()

// Preview keyboard shortcuts
useKeyboardShortcuts({
  prevFile: () => { prevFile(); osd.value?.show('SkipBack') },
  nextFile: () => { nextFile(); osd.value?.show('SkipForward') },
  seekForward: () => {
    if (isMediaType()) { mediaPlayer.value?.seekBy(1); osd.value?.show('FastForward') }
    else if (isPdfType()) { mediaPlayer.value?.pdfScrollBy(80, 0) }
    else { mediaPlayer.value?.panBy(-50, 0) }
  },
  seekBackward: () => {
    if (isMediaType()) { mediaPlayer.value?.seekBy(-1); osd.value?.show('Rewind') }
    else if (isPdfType()) { mediaPlayer.value?.pdfScrollBy(-80, 0) }
    else { mediaPlayer.value?.panBy(50, 0) }
  },
  playPause: () => {
    if (!isMediaType()) return
    const wasPlaying = mediaPlayer.value?.playing?.value ?? mediaPlayer.value?.playing
    mediaPlayer.value?.togglePlay()
    osd.value?.show(wasPlaying ? 'Pause' : 'Play')
  },
  volumeUp: () => {
    if (isMediaType()) { mediaPlayer.value?.changeVolume(0.05); osd.value?.show('Volume2') }
    else if (isPdfType()) { mediaPlayer.value?.pdfScrollBy(0, -120) }
    else { mediaPlayer.value?.panBy(0, 50) }
  },
  volumeDown: () => {
    if (isMediaType()) { mediaPlayer.value?.changeVolume(-0.05); osd.value?.show('Volume1') }
    else if (isPdfType()) { mediaPlayer.value?.pdfScrollBy(0, 120) }
    else { mediaPlayer.value?.panBy(0, -50) }
  },
  toggleMute: () => {
    if (!isMediaType()) return
    const wasMuted = mediaPlayer.value?.muted?.value ?? mediaPlayer.value?.muted
    mediaPlayer.value?.toggleMute()
    osd.value?.show(wasMuted ? 'Volume2' : 'VolumeX')
  },
  fileInfo: () => {
    const dialog = fileInfoDialog.value
    if (dialog?.open) {
      dialog.close()
    } else {
      dialog?.showModal()
      osd.value?.show('Info')
    }
  },
  exitPreview: () => { closePreview() },
  zoomIn: () => { mediaPlayer.value?.zoomBy(0.2); osd.value?.show('ZoomIn') },
  zoomOut: () => { mediaPlayer.value?.zoomBy(-0.2); osd.value?.show('ZoomOut') },
  pdfFitMode: () => { mediaPlayer.value?.pdfToggleFitMode(); osd.value?.show('Columns') },
  panUp: () => { if (isMediaType()) mediaPlayer.value?.panBy(0, 50) },
  panDown: () => { if (isMediaType()) mediaPlayer.value?.panBy(0, -50) },
  panLeft: () => { if (isMediaType()) mediaPlayer.value?.panBy(50, 0) },
  panRight: () => { if (isMediaType()) mediaPlayer.value?.panBy(-50, 0) },
  toggleUI: () => {
    // Only allow hiding UI for visual content (image/gif/video/pdf), not audio/other
    const type = previewFile.value?.fileType
    if (!['image', 'gif', 'video', 'pdf'].includes(type)) return
    previewUIHidden.value = !previewUIHidden.value
    if (mediaPlayer.value) {
      const cv = mediaPlayer.value.controlsVisible
      if (cv && typeof cv === 'object') cv.value = !previewUIHidden.value
      else mediaPlayer.value.controlsVisible = !previewUIHidden.value
    }
    osd.value?.show(previewUIHidden.value ? 'EyeOff' : 'Eye')
  },
  cycleTheme: () => {
    cycleTheme()
    const icons = { system: 'Monitor', light: 'Sun', dark: 'Moon' }
    osd.value?.show(icons[themeMode.value] || 'Monitor')
  },
}, () => !!previewFile.value)

const fileInfoDialog = ref(null)
const gridScrollContainer = ref(null)
let savedScrollTop = 0
const allTags = ref([])
const fileTags = ref([])
const renameDialog = ref(null)
const renameValue = ref('')
const renameTarget = ref(null)

const moveDialog = ref(null)
const moveTarget = ref('')
const moveFolders = ref([])
const moveBreadcrumbs = ref([])
const moveBrowsePath = ref('')
const moveLoading = ref(false)
const moveTargetFile = ref(null)

onMounted(async () => {
  const { data } = await configApi.getSources()
  setSourceFolder(data.current)
  if (sourceFolder.value) {
    // Load root folders for sidebar tree
    loadingFolders.value = true
    try {
      const { data } = await indexerApi.getFolders(sourceFolder.value, sourceFolder.value)
      rootFolders.value = data
    } catch {}
    loadingFolders.value = false

    // Navigate to current folder (preserved across page switches) or source root
    await navigateTo(currentFolder.value || sourceFolder.value)
    try {
      const { data: tags } = await tagApi.listTags(sourceFolder.value)
      allTags.value = tags
    } catch {}
  }
})

async function navigateTo(path) {
  closePreview()
  setCurrentFolder(path)
  switchingFolder.value = true
  offset.value = 0

  const [filesRes, breadcrumbRes] = await Promise.allSettled([
    indexerApi.getFiles(path, { offset: 0, limit: PAGE_SIZE }),
    indexerApi.getBreadcrumb(path),
  ])

  if (filesRes.status === 'fulfilled') {
    const d = filesRes.value.data
    files.value = d.files
    total.value = d.total
    hasMore.value = d.hasMore
    offset.value = d.files.length
  }
  switchingFolder.value = false
  breadcrumbs.value = breadcrumbRes.status === 'fulfilled' ? breadcrumbRes.value.data : []
}

async function loadMore() {
  if (loadingMore.value) return
  loadingMore.value = true
  try {
    const { data } = await indexerApi.getFiles(currentFolder.value, { offset: offset.value, limit: PAGE_SIZE })
    files.value.push(...data.files)
    hasMore.value = data.hasMore
    offset.value += data.files.length
  } catch {}
  loadingMore.value = false
}

function refreshFiles() { navigateTo(currentFolder.value) }

function formatSize(bytes) {
  if (!bytes) return '—'
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
}

function formatDate(str) {
  if (!str) return '—'
  try { return new Date(str).toLocaleString() } catch { return str }
}

async function onDrop(e) {
  dragOver.value = false
  const droppedFiles = e.dataTransfer?.files
  if (droppedFiles?.length) {
    uploadArea.value?.doUpload(droppedFiles)
  }
}

async function reindexFolder() {
  reindexing.value = true
  try {
    await indexerApi.triggerScan(sourceFolder.value, true)
  } catch {}
  const poll = setInterval(async () => {
    try {
      const { data } = await indexerApi.getScanStatus()
      if (!data.isScanning) {
        clearInterval(poll)
        reindexing.value = false
        refreshFiles()
      }
    } catch { clearInterval(poll); reindexing.value = false }
  }, 2000)
}

async function openPreview(file) {
  savedScrollTop = gridScrollContainer.value?.scrollTop || 0
  previewFile.value = file
  loadFileTags(file.uuid)
  await fetchPlaylist(file.uuid)
}

async function loadFileTags(uuid) {
  try {
    const { data } = await tagApi.getFileTags(uuid)
    fileTags.value = data.tags || []
  } catch { fileTags.value = [] }
}

async function onUpdateTags(tagIds) {
  if (!previewFile.value) return
  try {
    await tagApi.setFileTags(previewFile.value.uuid, tagIds)
    await loadFileTags(previewFile.value.uuid)
  } catch {}
}

async function onCreateTag({ name, color }) {
  try {
    await tagApi.createTag(sourceFolder.value, name, color)
    const { data: tags } = await tagApi.listTags(sourceFolder.value)
    allTags.value = tags
  } catch {}
}

function closePreview() {
  previewFile.value = null
  previewUIHidden.value = false
  showPlaylistPanel.value = false
  clearAutoAdvance()
  nextTick(() => {
    if (gridScrollContainer.value) {
      gridScrollContainer.value.scrollTop = savedScrollTop
    }
  })
}

function prevFile() {
  if (playlist.value.length <= 1) return
  const newIdx = playlistIndex.value > 0 ? playlistIndex.value - 1 : playlist.value.length - 1
  navigatePlaylist(newIdx)
}

function nextFile() {
  if (playlist.value.length <= 1) return
  const newIdx = playlistIndex.value < playlist.value.length - 1 ? playlistIndex.value + 1 : 0
  navigatePlaylist(newIdx)
}

function navigatePlaylist(index) {
  const file = playlist.value[index]
  if (!file) return
  const direction = index > playlistIndex.value ? 'forward' : 'backward'
  const oldIndex = playlistIndex.value

  // Compute keep UUIDs before updating state
  let keepUuids = null
  if (playbackMode.value === 'shuffle' && playlist.value.length > 1) {
    let keepItems
    if (direction === 'forward') {
      keepItems = playlist.value.slice(oldIndex + 1)
    } else {
      keepItems = playlist.value.slice(0, oldIndex)
    }
    keepUuids = keepItems.filter(f => f.uuid !== file.uuid).map(f => f.uuid)
  }

  playlistIndex.value = index
  previewFile.value = file
  loadFileTags(file.uuid)
  fetchPlaylist(file.uuid, direction, keepUuids)
}

function jumpToPlaylistItem(uuid) {
  // Jump = no keep, full re-fetch
  const file = playlist.value.find(f => f.uuid === uuid)
  if (file) {
    previewFile.value = file
    loadFileTags(file.uuid)
  }
  fetchPlaylist(uuid, 'jump')
}

async function fetchPlaylist(uuid, direction = 'jump', precomputedKeepUuids = null) {
  clearAutoAdvance()
  const mode = playbackMode.value === 'repeat' ? 'sequential' : playbackMode.value
  const opts = { sort: undefined }
  if (filterByType.value && previewFile.value) {
    opts.fileType = previewFile.value.fileType
  }
  if (mode === 'shuffle' && precomputedKeepUuids) {
    opts.keepUuids = precomputedKeepUuids
  }
  try {
    const { data } = await playlistApi.getPlaylist(uuid, currentFolder.value, mode, opts)
    playlist.value = data.items
    playlistIndex.value = data.currentIndex
    if (data.items[data.currentIndex]) {
      previewFile.value = data.items[data.currentIndex]
    }
    startAutoAdvance()
  } catch {}
}

function switchPlaybackMode(mode) {
  playbackMode.value = mode
  if (previewFile.value) {
    fetchPlaylist(previewFile.value.uuid)
  }
}

function cyclePlaybackMode() {
  const modes = ['sequential', 'shuffle', 'repeat']
  const next = modes[(modes.indexOf(playbackMode.value) + 1) % modes.length]
  switchPlaybackMode(next)
}

// Auto-advance for sequential/shuffle modes
function startAutoAdvance() {
  clearAutoAdvance()
  if (playbackMode.value === 'repeat') return
  // For non-media types, auto-advance after a delay
  const type = previewFile.value?.fileType
  if (['video', 'audio'].includes(type)) return // media auto-advances via onEnded
  autoAdvanceTimer = setTimeout(() => {
    nextFile()
  }, autoAdvanceSeconds.value * 1000)
}

function clearAutoAdvance() {
  if (autoAdvanceTimer) {
    clearTimeout(autoAdvanceTimer)
    autoAdvanceTimer = null
  }
}

function onMediaEnded() {
  if (playbackMode.value === 'repeat') {
    // Loop current
    mediaPlayer.value?.seekBy(-999999)
    nextTick(() => mediaPlayer.value?.togglePlay())
  } else {
    nextFile()
  }
}

// Keyboard shortcuts handled by useKeyboardShortcuts above

function startRename(file) {
  renameTarget.value = file
  renameValue.value = file.fileName.replace(/\.[^.]+$/, '')
  renameDialog.value?.showModal()
}

async function doRename() {
  if (!renameTarget.value || !renameValue.value.trim()) return
  const ext = renameTarget.value.fileName.match(/\.[^.]+$/)?.[0] || ''
  try {
    await fileApi.renameFile(renameTarget.value.uuid, renameValue.value.trim() + ext)
    renameDialog.value?.close()
    refreshFiles()
  } catch { alert(t('common.error')) }
}

async function startMove(file) {
  moveTargetFile.value = file
  moveTarget.value = ''
  await browseMoveTo(sourceFolder.value)
  moveDialog.value?.showModal()
}

async function browseMoveTo(path) {
  moveBrowsePath.value = path
  moveTarget.value = ''
  moveLoading.value = true
  try {
    const [foldersRes, breadcrumbRes] = await Promise.allSettled([
      indexerApi.getFolders(path, sourceFolder.value),
      indexerApi.getBreadcrumb(path),
    ])
    moveFolders.value = foldersRes.status === 'fulfilled' ? foldersRes.value.data : []
    moveBreadcrumbs.value = breadcrumbRes.status === 'fulfilled' ? breadcrumbRes.value.data : []
  } catch {}
  moveLoading.value = false
}

async function doMove() {
  if (!moveTargetFile.value || !moveTarget.value) return
  try {
    await fileApi.moveFile(moveTargetFile.value.uuid, moveTarget.value)
    moveDialog.value?.close()
    closePreview()
    refreshFiles()
  } catch { alert(t('common.error')) }
}
</script>

<style scoped>
.slide-up-enter-active, .slide-up-leave-active { transition: transform 0.25s ease; }
.slide-up-enter-from, .slide-up-leave-to { transform: translateY(100%); }
</style>
