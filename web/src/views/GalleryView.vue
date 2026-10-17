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
      <button
        class="btn btn-ghost btn-sm btn-square"
        :class="{ 'btn-active': selectMode }"
        data-testid="batch-select-toggle"
        @click="toggleSelectMode"
        :title="$t('gallery.batchSelect')"
      >
        <CheckSquare :size="16" />
      </button>
      <button class="btn btn-ghost btn-sm btn-square" @click="openNewFolderDialog" :title="$t('gallery.newFolder')">
        <FolderPlus :size="16" />
      </button>
      <button class="btn btn-ghost btn-sm btn-square" @click="openRecycleBin" :title="$t('gallery.recycleBin')">
        <Trash2 :size="16" />
      </button>
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
          <button
            class="btn btn-ghost btn-xs btn-square"
            data-testid="file-info-btn"
            :class="{ 'btn-active': showInfoPanel }"
            @click="toggleFileInfo()"
            :title="$t('gallery.fileInfo') + ' (I)'"
          >
            <Info :size="16" />
          </button>
        </div>
        <!-- Player + optional desktop info side panel -->
        <div class="flex flex-1 min-h-0 relative">
          <div class="flex-1 min-w-0 min-h-0 relative">
          <MediaPlayer
            ref="mediaPlayer"
            :src="contentSrc"
            :type="previewFile.fileType"
            :file-name="previewFile.fileName"
            :cover-url="coverSrc"
            :live-video-src="liveVideoSrc"
            :advance-mode="advanceMode"
            :show-nav="true"
            :has-prev="canGoPrev"
            :has-next="canGoNext"
            @prev="prevFile"
            @next="nextFile"
            @ended="onMediaEnded"
            @toggle-advance-mode="toggleAdvanceMode"
            @open-queue-panel="showPlaylistPanel = true"
          />
          <OsdFeedback ref="osd" />
          <!-- Queue panel: independent switches + play order -->
          <transition name="slide-up">
            <div
              v-if="showPlaylistPanel && !previewUIHidden"
              class="absolute bottom-16 right-4 w-80 bg-black/70 backdrop-blur-md rounded-xl shadow-xl z-20 overflow-hidden"
              data-testid="queue-panel"
            >
              <div class="px-3 py-2 border-b border-white/10 space-y-2">
                <label class="flex items-center justify-between gap-2 text-xs text-white/90 cursor-pointer">
                  <span>随机播放</span>
                  <input
                    type="checkbox"
                    class="toggle toggle-xs"
                    data-testid="queue-shuffle-toggle"
                    :checked="shuffleEnabled"
                    @change="setShuffleEnabled($event.target.checked)"
                  />
                </label>
                <label class="flex items-center justify-between gap-2 text-xs text-white/90 cursor-pointer">
                  <span>列表循环</span>
                  <input
                    type="checkbox"
                    class="toggle toggle-xs"
                    data-testid="queue-list-loop-toggle"
                    :checked="listLoopEnabled"
                    @change="setListLoopEnabled($event.target.checked)"
                  />
                </label>
                <label class="flex items-center justify-between gap-2 text-xs text-white/90 cursor-pointer">
                  <span>同类型播放</span>
                  <input
                    type="checkbox"
                    class="toggle toggle-xs"
                    data-testid="queue-same-type-toggle"
                    :checked="filterByType"
                    @change="setFilterByType($event.target.checked)"
                  />
                </label>
              </div>
              <div class="py-1 max-h-64 overflow-y-auto">
                <button
                  v-for="(item, i) in playlist"
                  :key="item.uuid"
                  class="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-left transition-colors"
                  :class="i === playlistIndex ? 'bg-white/15 text-white font-medium' : 'text-white/70 hover:bg-white/10'"
                  :data-testid="`queue-item-${item.uuid}`"
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

          <!-- Desktop info side panel (feature parity with iOS; not phone Photos chrome) -->
          <aside
            v-if="showInfoPanel && !previewUIHidden"
            class="w-[22rem] shrink-0 border-l border-base-300 bg-base-100 flex flex-col overflow-hidden"
            data-testid="file-info-dialog"
          >
            <div class="flex items-center justify-between gap-2 px-4 py-3 border-b border-base-300 shrink-0">
              <h3 class="font-semibold text-sm">{{ $t('gallery.fileInfo') }}</h3>
              <kbd class="kbd kbd-xs opacity-50">I</kbd>
              <button class="btn btn-ghost btn-xs btn-square ml-auto" @click="showInfoPanel = false" title="Close">
                <X :size="14" />
              </button>
            </div>
            <div class="flex-1 overflow-y-auto px-4 py-3 space-y-3 text-sm" data-testid="file-metadata-panel">
              <!-- 时间：capture → 星期•日期•时间 + filename -->
              <section v-if="photosDateHeader" class="rounded-xl bg-base-200/60 p-3" data-testid="meta-module-time">
                <div class="font-semibold" data-testid="meta-capture-time">{{ photosDateHeader }}</div>
                <div class="mt-1 text-xs text-base-content/60 flex items-center gap-1.5" data-testid="meta-filename">
                  <span class="truncate">{{ fileMeta?.filename || previewFile.fileName }}</span>
                  <span v-if="playlist.length" class="opacity-50">· {{ playlistIndex + 1 }} / {{ playlist.length }}</span>
                </div>
              </section>

              <!-- 拍摄设备 -->
              <section v-if="showDeviceModule" class="rounded-xl bg-base-200/60 p-3" data-testid="meta-module-device">
                <div class="flex items-baseline justify-between gap-2">
                  <div class="font-semibold" data-testid="meta-device">{{ deviceLabel || $t('gallery.device') }}</div>
                  <span v-if="fileMeta?.format" class="badge badge-ghost badge-sm font-semibold" data-testid="meta-format">{{ fileMeta.format }}</span>
                </div>
                <div v-if="fileMeta?.lens" class="mt-1 text-xs text-base-content/60 truncate" data-testid="meta-lens" :title="fileMeta.lens">{{ fileMeta.lens }}</div>
                <div v-if="deviceSummaryLine" class="mt-1 text-xs text-base-content/60" data-testid="meta-dimensions">{{ deviceSummaryLine }}</div>
                <div v-if="exifStrip.length" class="mt-2 flex flex-wrap gap-1" data-testid="meta-exif-strip">
                  <span v-for="item in exifStrip" :key="item" class="badge badge-ghost badge-sm font-mono">{{ item }}</span>
                </div>
              </section>

              <!-- 地图定位 -->
              <section v-if="fileMeta?.gps" class="rounded-xl bg-base-200/60 overflow-hidden" data-testid="meta-gps">
                <div class="h-24 bg-base-300/80 flex items-center justify-center text-xs text-base-content/50 px-3 text-center">
                  {{ formatGps(fileMeta.gps) }}
                </div>
                <div class="px-3 py-2 text-xs text-base-content/60">{{ formatGps(fileMeta.gps) }}</div>
              </section>

              <!-- 基础信息：仅剩余字段 -->
              <section class="rounded-xl bg-base-200/60 p-3 space-y-2" data-testid="meta-module-basics">
                <div class="font-semibold text-xs uppercase tracking-wide text-base-content/50">{{ $t('gallery.basicInfo') }}</div>
                <div v-for="row in basicsRows" :key="row.id" class="flex justify-between gap-3" :data-testid="row.testId || undefined">
                  <span class="text-base-content/50 shrink-0">{{ row.label }}</span>
                  <span class="text-right truncate max-w-[60%]">
                    <a v-if="row.href" :href="row.href" target="_blank" rel="noopener" class="underline">{{ row.value }}</a>
                    <template v-else>{{ row.value }}</template>
                  </span>
                </div>
                <div class="pt-1">
                  <div class="text-xs text-base-content/50 mb-1">{{ $t('gallery.tags') }}</div>
                  <TagEditor
                    :file-tags="fileTags"
                    :all-tags="allTags"
                    @update="onUpdateTags"
                    @create="onCreateTag"
                  />
                </div>
              </section>
            </div>

            <!-- Single action row: download / share / move / rename / delete -->
            <div class="shrink-0 border-t border-base-300 p-2 flex gap-1" data-testid="file-info-actions">
              <a
                :href="contentSrc"
                download
                class="btn btn-ghost btn-sm btn-square flex-1"
                data-testid="file-info-download"
                :title="$t('common.download')"
              >
                <Download :size="16" />
              </a>
              <button
                class="btn btn-ghost btn-sm btn-square flex-1"
                data-testid="file-info-share"
                :title="$t('common.share')"
                @click="sharePreviewFile()"
              >
                <Share2 :size="16" />
              </button>
              <button
                class="btn btn-ghost btn-sm btn-square flex-1"
                :title="$t('common.move')"
                @click="showInfoPanel = false; startMove(previewFile)"
              >
                <FolderInput :size="16" />
              </button>
              <button
                class="btn btn-ghost btn-sm btn-square flex-1"
                :title="$t('common.rename')"
                @click="showInfoPanel = false; startRename(previewFile)"
              >
                <Pencil :size="16" />
              </button>
              <button
                v-if="!isInRecycleBin"
                class="btn btn-ghost btn-sm btn-square flex-1 text-error"
                data-testid="file-info-delete"
                :title="$t('common.delete')"
                @click="showInfoPanel = false; confirmDelete(previewFile)"
              >
                <Trash2 :size="16" />
              </button>
            </div>
          </aside>
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
            :select-mode="selectMode"
            :selected-ids="selectedIds"
            @preview="openPreview"
            @load-more="loadMore"
            @toggle-select="toggleFileSelect"
          />
          <!-- Batch action bar -->
          <div
            v-if="selectMode"
            data-testid="batch-action-bar"
            class="sticky bottom-0 z-10 flex items-center gap-2 px-4 py-3 bg-base-100/95 backdrop-blur border-t border-base-300"
          >
            <span class="text-sm text-base-content/60 shrink-0" data-testid="batch-selected-count">
              {{ $t('gallery.selectedCount', { count: selectedIds.size }) }}
            </span>
            <button class="btn btn-ghost btn-sm" data-testid="batch-select-all" @click="selectAllVisible">
              {{ allVisibleSelected ? $t('gallery.deselectAll') : $t('gallery.selectAll') }}
            </button>
            <div class="flex-1" />
            <button
              class="btn btn-ghost btn-sm gap-1"
              data-testid="batch-move-btn"
              :disabled="!selectedIds.size || bulkBusy"
              @click="startBulkMove"
            >
              <FolderInput :size="14" />
              {{ $t('common.move') }}
            </button>
            <button
              v-if="!isInRecycleBin"
              class="btn btn-ghost btn-sm gap-1 text-error"
              data-testid="batch-delete-btn"
              :disabled="!selectedIds.size || bulkBusy"
              @click="confirmBulkDelete"
            >
              <Trash2 :size="14" />
              {{ $t('common.delete') }}
            </button>
            <button class="btn btn-ghost btn-sm" data-testid="batch-cancel-btn" @click="exitSelectMode">
              {{ $t('common.cancel') }}
            </button>
          </div>
        </div>
      </div>
    </template>

    <!-- Delete Confirm Dialog -->
    <ConfirmDialog
      ref="deleteDialog"
      :title="bulkDeletePending ? $t('gallery.bulkDeleteConfirmTitle', { count: selectedIds.size }) : $t('gallery.deleteConfirmTitle')"
      :message="bulkDeletePending ? $t('gallery.bulkDeleteConfirmMsg') : $t('gallery.deleteConfirmMsg')"
      @confirm="bulkDeletePending ? doBulkDelete() : doDelete()"
      @cancel="bulkDeletePending = false"
    />

    <!-- New Folder Dialog -->
    <dialog ref="newFolderDialog" class="modal">
      <div class="modal-box max-w-sm">
        <h3 class="font-bold text-lg mb-4">{{ $t('gallery.newFolder') }}</h3>
        <input
          v-model="newFolderName"
          class="input input-bordered w-full"
          :placeholder="$t('gallery.folderName')"
          @keyup.enter="doCreateFolder"
        />
        <div class="modal-action">
          <button class="btn" @click="newFolderDialog?.close()">{{ $t('common.cancel') }}</button>
          <button class="btn btn-neutral" @click="doCreateFolder" :disabled="!newFolderName.trim()">{{ $t('common.confirm') }}</button>
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
    <dialog ref="moveDialog" class="modal" data-testid="move-dialog">
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
            data-testid="move-here-btn"
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
          <button class="btn btn-neutral" data-testid="move-confirm-btn" @click="doMove" :disabled="!moveTarget">{{ $t('common.confirm') }}</button>
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
import ConfirmDialog from '../components/shared/ConfirmDialog.vue'
import { Folder, ChevronRight, X, Pencil, FolderInput, RefreshCw, Info, Download, FolderPlus, Trash2, CheckSquare, Share2 } from 'lucide-vue-next'
import { contentUrl, thumbnailUrl, liveVideoUrl } from '../api/preview'
import { useCurrentFolder } from '../composables/useCurrentFolder'
import { usePrivacy } from '../composables/usePrivacy'
import * as indexerApi from '../api/indexer'
import * as playlistApi from '../api/playlist'
import * as configApi from '../api/config'
import * as fileApi from '../api/file'
import * as folderApi from '../api/folder'
import * as tagApi from '../api/tag'

const RECYCLE_BIN_NAME = '_Recycle'

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
const fileMeta = ref(null)
const playlist = ref([])
const playlistIndex = ref(0)
const playlistAtStart = ref(false)
const playlistAtEnd = ref(false)

// Two-axis playback state (persisted). Migrate legacy single-mode key once.
const advanceMode = ref(loadAdvanceMode()) // 'autoNext' | 'repeatCurrent'
const shuffleEnabled = ref(localStorage.getItem('playback_shuffle') === 'true')
const listLoopEnabled = ref(loadListLoopEnabled())
const filterByType = ref(localStorage.getItem('playlist_filterByType') === 'true')
const autoAdvanceSeconds = ref(parseInt(localStorage.getItem('playlist_autoAdvanceSeconds') || '8'))
const showPlaylistPanel = ref(false)
let autoAdvanceTimer = null
/** When true, next shuffle fetch omits current_queue (fresh true shuffle). */
let shuffleNeedsFresh = shuffleEnabled.value

function loadAdvanceMode() {
  const saved = localStorage.getItem('playback_advanceMode')
  if (saved === 'autoNext' || saved === 'repeatCurrent') return saved
  const legacy = localStorage.getItem('playbackMode') || localStorage.getItem('playback_mode')
  if (legacy === 'repeat' || legacy === 'repeatCurrent') return 'repeatCurrent'
  if (legacy === 'sequential' || legacy === 'shuffle') return 'autoNext'
  return 'repeatCurrent'
}

function loadListLoopEnabled() {
  const saved = localStorage.getItem('playback_listLoop')
  if (saved === 'true' || saved === 'false') return saved === 'true'
  // Legacy sequential always wrapped; default on for first-time users.
  return true
}

function persistPlaybackPrefs() {
  localStorage.setItem('playback_advanceMode', advanceMode.value)
  localStorage.setItem('playback_shuffle', String(shuffleEnabled.value))
  localStorage.setItem('playback_listLoop', String(listLoopEnabled.value))
  localStorage.setItem('playlist_filterByType', String(filterByType.value))
}

const canGoPrev = computed(() => {
  if (playlist.value.length <= 1) return false
  if (shuffleEnabled.value || listLoopEnabled.value) return true
  return !(playlistAtStart.value && playlistIndex.value <= 0)
})
const canGoNext = computed(() => {
  if (playlist.value.length <= 1) return false
  if (shuffleEnabled.value || listLoopEnabled.value) return true
  return !(playlistAtEnd.value && playlistIndex.value >= playlist.value.length - 1)
})

function apiPlaylistMode() {
  if (shuffleEnabled.value) return 'shuffle'
  if (listLoopEnabled.value) return 'list_loop'
  return 'sequential'
}
const contentSrc = computed(() => previewFile.value ? contentUrl(previewFile.value) : '')
const coverSrc = computed(() => previewFile.value ? thumbnailUrl(previewFile.value, 600) : '')
const liveVideoSrc = computed(() => previewFile.value ? liveVideoUrl(previewFile.value) : '')
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
    toggleFileInfo()
    osd.value?.show('Info')
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

const showInfoPanel = ref(false)
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

// 新建文件夹 / 删除（回收站）
const newFolderDialog = ref(null)
const newFolderName = ref('')
const deleteDialog = ref(null)
const deleteTarget = ref(null)
const { isPrivate, isUnlocked } = usePrivacy()

// 批量选择
const selectMode = ref(false)
const selectedIds = ref(new Set())
const bulkBusy = ref(false)
const bulkMoveMode = ref(false)
const bulkDeletePending = ref(false)

const allVisibleSelected = computed(() => {
  if (!files.value.length) return false
  return files.value.every(f => selectedIds.value.has(f.uuid))
})

// 当前浏览目录是否为回收站（回收站内禁止再次删除）
const isInRecycleBin = computed(() => {
  const p = currentFolder.value || ''
  return p.split('/').filter(Boolean).pop() === RECYCLE_BIN_NAME
})

onMounted(async () => {
  const { data } = await configApi.getSources()
  let current = data.current
  // 启动时若当前源为私密且未解锁，自动切换到首个非私密源
  if (current && isPrivate(current) && !isUnlocked.value) {
    const all = [data.current, ...(data.backups || [])]
    const target = all.find(p => !isPrivate(p))
    if (target && target !== current) {
      try {
        await configApi.switchSource(target)
        current = target
      } catch {}
    }
  }
  setSourceFolder(current)
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
  exitSelectMode()
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

function formatGps(gps) {
  if (!gps || gps.lat == null || gps.lon == null) return ''
  const latHem = gps.lat >= 0 ? 'N' : 'S'
  const lonHem = gps.lon >= 0 ? 'E' : 'W'
  return `${Math.abs(gps.lat).toFixed(5)}° ${latHem}, ${Math.abs(gps.lon).toFixed(5)}° ${lonHem}`
}

function formatDuration(seconds) {
  if (seconds == null || Number.isNaN(seconds)) return ''
  const s = Math.floor(seconds)
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`
  return `${m}:${String(sec).padStart(2, '0')}`
}

async function loadFileMetadata() {
  fileMeta.value = null
  const file = previewFile.value
  if (!file) return
  const path = file.currentPath || file.path
  if (!path) return
  try {
    const { data } = await fileApi.getFileMetadata(path)
    fileMeta.value = data
  } catch {
    fileMeta.value = null
  }
}

function toggleFileInfo() {
  if (showInfoPanel.value) {
    showInfoPanel.value = false
    return
  }
  showInfoPanel.value = true
  loadFileMetadata()
}

function openFileInfo() {
  showInfoPanel.value = true
  loadFileMetadata()
}

async function sharePreviewFile() {
  const file = previewFile.value
  if (!file) return
  const url = contentSrc.value
  const title = file.fileName || fileMeta.value?.filename || 'file'
  try {
    if (typeof navigator !== 'undefined' && typeof navigator.share === 'function') {
      await navigator.share({ title, url, text: title })
      return
    }
  } catch (e) {
    // User cancel or share unsupported — fall through to clipboard
    if (e && (e.name === 'AbortError' || e.name === 'NotAllowedError')) return
  }
  try {
    await navigator.clipboard.writeText(url)
    osd.value?.show('Share2')
  } catch {
    // Last resort: open in new tab so user can copy from address bar
    window.open(url, '_blank', 'noopener')
  }
}

const deviceLabel = computed(() => {
  const m = fileMeta.value
  if (!m) return null
  if (m.make && m.model) {
    if (String(m.model).toLowerCase().startsWith(String(m.make).toLowerCase())) return m.model
    return `${m.make} ${m.model}`
  }
  return m.model || m.make || null
})

const hasCaptureContext = computed(() => {
  const m = fileMeta.value
  if (!m) return false
  return !!(deviceLabel.value || m.lens || m.iso != null || m.aperture != null || m.shutterSpeed || m.captureTime)
})

const showDeviceModule = computed(() => {
  const m = fileMeta.value
  if (!m) return false
  return !!(
    deviceLabel.value
    || m.lens
    || m.iso != null
    || m.aperture != null
    || m.shutterSpeed
    || (hasCaptureContext.value && m.format)
  )
})

const photosDateHeader = computed(() => {
  const raw = fileMeta.value?.captureTime
  if (!raw) return ''
  try {
    const d = new Date(raw.includes('T') ? raw : raw.replace(' ', 'T'))
    if (Number.isNaN(d.getTime())) return ''
    return d.toLocaleString(undefined, {
      weekday: 'long',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
  } catch {
    return ''
  }
})

const deviceSummaryLine = computed(() => {
  if (!showDeviceModule.value) return ''
  const m = fileMeta.value
  const parts = []
  if (m?.megapixels != null) {
    const mp = Number(m.megapixels)
    parts.push(`${mp >= 10 ? mp.toFixed(0) : mp.toFixed(1)} MP`)
  }
  if (m?.width && m?.height) parts.push(`${m.width} × ${m.height}`)
  parts.push(formatSize(m?.size ?? previewFile.value?.fileSize))
  return parts.join(' • ')
})

const exifStrip = computed(() => {
  const m = fileMeta.value
  if (!m || !showDeviceModule.value) return []
  const items = []
  if (m.iso != null) items.push(`ISO${m.iso}`)
  const fl = m.focalLength35mm ?? m.focalLengthMm
  if (fl != null) items.push(`${Math.round(Number(fl))}mm`)
  if (m.exposureCompensation != null) {
    const v = Number(m.exposureCompensation)
    items.push(Math.abs(v) < 0.05 ? '0ev' : `${v > 0 ? '+' : ''}${Math.round(v)}ev`)
  }
  if (m.aperture != null) items.push(`ƒ${Number(m.aperture).toFixed(1)}`)
  if (m.shutterSpeed) items.push(String(m.shutterSpeed).endsWith('s') ? m.shutterSpeed : `${m.shutterSpeed}s`)
  return items
})

function calendarDayKey(raw) {
  if (!raw) return null
  try {
    const d = new Date(String(raw).includes('T') ? raw : String(raw).replace(' ', 'T'))
    if (Number.isNaN(d.getTime())) return null
    return d.toISOString().slice(0, 10)
  } catch {
    return null
  }
}

const basicsRows = computed(() => {
  const m = fileMeta.value
  const file = previewFile.value
  if (!file) return []
  const rows = []

  // Filename lives in 时间 subtitle when capture time module shows; otherwise 基础信息
  if (!photosDateHeader.value) {
    rows.push({
      id: 'filename',
      label: t('gallery.fileName'),
      value: m?.filename || file.fileName,
      testId: 'meta-filename',
    })
  }

  const path = file.currentPath || file.path || ''
  const folder = path.includes('/') ? path.slice(0, path.lastIndexOf('/')) : ''
  if (folder) {
    rows.push({ id: 'path', label: t('gallery.path'), value: folder, testId: 'meta-path' })
  }

  if (!showDeviceModule.value) {
    const format = m?.format || file.extension?.replace('.', '').toUpperCase()
    if (format) rows.push({ id: 'format', label: t('gallery.format'), value: format, testId: 'meta-format' })
    if (m?.width && m?.height) {
      rows.push({ id: 'dims', label: t('gallery.dimensions'), value: `${m.width} × ${m.height}`, testId: 'meta-dimensions' })
    }
    rows.push({
      id: 'size',
      label: t('gallery.fileSize'),
      value: formatSize(m?.size ?? file.fileSize),
      testId: 'meta-size',
    })
  }

  if (m?.duration) {
    rows.push({ id: 'duration', label: t('gallery.duration'), value: formatDuration(m.duration), testId: 'meta-duration' })
  }
  if (m?.codec) {
    rows.push({ id: 'codec', label: t('gallery.codec'), value: String(m.codec).toUpperCase(), testId: 'meta-codec' })
  }

  const captureDay = calendarDayKey(m?.captureTime)
  const createdRaw = m?.created || file.createdAt
  const modifiedRaw = m?.modified || file.modifiedAt
  const createdDay = calendarDayKey(createdRaw)
  if (createdRaw && !(photosDateHeader.value && captureDay && createdDay === captureDay)) {
    rows.push({ id: 'created', label: t('gallery.created'), value: formatDate(createdRaw) })
  }
  if (modifiedRaw && String(modifiedRaw).slice(0, 19) !== String(createdRaw || '').slice(0, 19)) {
    const modifiedDay = calendarDayKey(modifiedRaw)
    if (!(photosDateHeader.value && captureDay && modifiedDay === captureDay)) {
      rows.push({ id: 'modified', label: t('gallery.modified'), value: formatDate(modifiedRaw) })
    }
  }

  if (file.sourceUrl) {
    rows.push({
      id: 'source',
      label: t('gallery.sourceUrl'),
      value: file.sourceUrl,
      href: file.sourceUrl,
    })
  }

  return rows
})

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
  // Opening preview with shuffle on always starts a fresh shuffled queue
  if (shuffleEnabled.value) shuffleNeedsFresh = true
  await fetchPlaylist(file.uuid, { keepShuffleQueue: false })
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
  showInfoPanel.value = false
  fileMeta.value = null
  clearAutoAdvance()
  nextTick(() => {
    if (gridScrollContainer.value) {
      gridScrollContainer.value.scrollTop = savedScrollTop
    }
  })
}

function prevFile() {
  if (!canGoPrev.value) return
  navigatePlaylist(-1)
}

function nextFile() {
  if (!canGoNext.value) return
  navigatePlaylist(1)
}

function navigatePlaylist(direction) {
  if (playlist.value.length <= 1) return
  const wrap = shuffleEnabled.value || listLoopEnabled.value
  let newIndex = playlistIndex.value + direction

  if (newIndex >= 0 && newIndex < playlist.value.length) {
    // Stay inside current window — preserves shuffled order without refetch
    moveWithinPlaylist(newIndex)
    // Refetch at edges for shuffle/list_loop to refill the sliding window
    if (shuffleEnabled.value || listLoopEnabled.value) {
      if (newIndex === 0 || newIndex === playlist.value.length - 1) {
        const file = playlist.value[newIndex]
        fetchPlaylist(file.uuid, { keepShuffleQueue: shuffleEnabled.value })
      }
    }
    return
  }

  if (!wrap) return

  // Wrap within window then refetch centered on the new item
  newIndex = direction > 0 ? 0 : playlist.value.length - 1
  const file = playlist.value[newIndex]
  previewFile.value = file
  loadFileTags(file.uuid)
  fetchPlaylist(file.uuid, { keepShuffleQueue: shuffleEnabled.value })
}

function moveWithinPlaylist(index) {
  const file = playlist.value[index]
  if (!file) return
  playlistIndex.value = index
  previewFile.value = file
  loadFileTags(file.uuid)
  clearAutoAdvance()
  startAutoAdvance()
}

function jumpToPlaylistItem(uuid) {
  const file = playlist.value.find(f => f.uuid === uuid)
  if (file) {
    previewFile.value = file
    loadFileTags(file.uuid)
  }
  // Jump: reshuffle if shuffle on (don't reuse stale neighbors around jump target)
  if (shuffleEnabled.value) shuffleNeedsFresh = true
  fetchPlaylist(uuid, { keepShuffleQueue: false })
}

async function fetchPlaylist(uuid, { keepShuffleQueue = !shuffleNeedsFresh } = {}) {
  clearAutoAdvance()
  const mode = apiPlaylistMode()
  const opts = { sort: undefined }
  if (filterByType.value && previewFile.value) {
    opts.fileType = previewFile.value.fileType
  }
  // True shuffle: omit current_queue on first enter / jump so server builds a fresh random queue
  if (mode === 'shuffle' && keepShuffleQueue && playlist.value.length > 0 && !shuffleNeedsFresh) {
    opts.currentQueue = playlist.value.map(f => f.uuid)
  }
  try {
    const { data } = await playlistApi.getPlaylist(uuid, currentFolder.value, mode, opts)
    playlist.value = data.items
    playlistIndex.value = data.currentIndex
    playlistAtStart.value = !!data.atStart
    playlistAtEnd.value = !!data.atEnd
    if (data.items[data.currentIndex]) {
      previewFile.value = data.items[data.currentIndex]
    }
    if (mode === 'shuffle') shuffleNeedsFresh = false
    startAutoAdvance()
  } catch {}
}

function toggleAdvanceMode() {
  advanceMode.value = advanceMode.value === 'repeatCurrent' ? 'autoNext' : 'repeatCurrent'
  persistPlaybackPrefs()
  clearAutoAdvance()
  startAutoAdvance()
}

function setShuffleEnabled(on) {
  shuffleEnabled.value = !!on
  if (on) shuffleNeedsFresh = true
  persistPlaybackPrefs()
  if (previewFile.value) fetchPlaylist(previewFile.value.uuid, { keepShuffleQueue: false })
}

function setListLoopEnabled(on) {
  listLoopEnabled.value = !!on
  persistPlaybackPrefs()
  if (previewFile.value) fetchPlaylist(previewFile.value.uuid, { keepShuffleQueue: !shuffleNeedsFresh })
}

function setFilterByType(on) {
  filterByType.value = !!on
  persistPlaybackPrefs()
  if (previewFile.value) {
    if (shuffleEnabled.value) shuffleNeedsFresh = true
    fetchPlaylist(previewFile.value.uuid, { keepShuffleQueue: false })
  }
}

// Auto-advance when advanceMode is autoNext (non-media uses timer; media uses onEnded)
function startAutoAdvance() {
  clearAutoAdvance()
  if (advanceMode.value === 'repeatCurrent') return
  const type = previewFile.value?.fileType
  if (['video', 'audio'].includes(type)) return
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
  if (advanceMode.value === 'repeatCurrent') {
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
  bulkMoveMode.value = false
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
    const folders = foldersRes.status === 'fulfilled' ? foldersRes.value.data : []
    // 回收站不作为移动目标
    moveFolders.value = (folders || []).filter(f => f.name !== RECYCLE_BIN_NAME)
    moveBreadcrumbs.value = breadcrumbRes.status === 'fulfilled' ? breadcrumbRes.value.data : []
  } catch {}
  moveLoading.value = false
}

async function doMove() {
  if (!moveTarget.value) return
  if (bulkMoveMode.value) {
    await doBulkMove()
    return
  }
  if (!moveTargetFile.value) return
  try {
    await fileApi.moveFile(moveTargetFile.value.uuid, moveTarget.value)
    moveDialog.value?.close()
    closePreview()
    refreshFiles()
  } catch { alert(t('common.error')) }
}

function toggleSelectMode() {
  if (selectMode.value) {
    exitSelectMode()
  } else {
    selectMode.value = true
    selectedIds.value = new Set()
  }
}

function exitSelectMode() {
  selectMode.value = false
  selectedIds.value = new Set()
  bulkMoveMode.value = false
  bulkDeletePending.value = false
}

function toggleFileSelect(file) {
  if (!file?.uuid) return
  const next = new Set(selectedIds.value)
  if (next.has(file.uuid)) next.delete(file.uuid)
  else next.add(file.uuid)
  selectedIds.value = next
}

function selectAllVisible() {
  if (allVisibleSelected.value) {
    selectedIds.value = new Set()
  } else {
    selectedIds.value = new Set(files.value.map(f => f.uuid).filter(Boolean))
  }
}

async function startBulkMove() {
  if (!selectedIds.value.size) return
  bulkMoveMode.value = true
  moveTargetFile.value = null
  moveTarget.value = ''
  await browseMoveTo(sourceFolder.value)
  moveDialog.value?.showModal()
}

async function doBulkMove() {
  if (!moveTarget.value || !selectedIds.value.size) return
  bulkBusy.value = true
  try {
    const { data } = await fileApi.batchMoveFiles([...selectedIds.value], moveTarget.value)
    moveDialog.value?.close()
    if (data.failureCount > 0) {
      alert(t('gallery.bulkPartialResult', { ok: data.successCount, fail: data.failureCount }))
    }
    exitSelectMode()
    refreshFiles()
  } catch {
    alert(t('common.error'))
  } finally {
    bulkBusy.value = false
  }
}

function confirmBulkDelete() {
  if (!selectedIds.value.size) return
  bulkDeletePending.value = true
  deleteTarget.value = null
  deleteDialog.value?.show()
}

async function doBulkDelete() {
  if (!selectedIds.value.size) return
  bulkBusy.value = true
  try {
    const { data } = await fileApi.batchDeleteFiles([...selectedIds.value])
    if (data.failureCount > 0) {
      alert(t('gallery.bulkPartialResult', { ok: data.successCount, fail: data.failureCount }))
    }
    exitSelectMode()
    refreshFiles()
  } catch {
    alert(t('common.error'))
  } finally {
    bulkBusy.value = false
    bulkDeletePending.value = false
  }
}

// 新建文件夹：在当前浏览目录下创建
function openNewFolderDialog() {
  newFolderName.value = ''
  newFolderDialog.value?.showModal()
}

async function doCreateFolder() {
  const name = newFolderName.value.trim()
  if (!name) return
  try {
    await folderApi.createFolder(name, currentFolder.value || sourceFolder.value)
    newFolderDialog.value?.close()
    // 刷新根文件夹树与当前文件列表
    try {
      const { data } = await indexerApi.getFolders(sourceFolder.value, sourceFolder.value)
      rootFolders.value = data
    } catch {}
    refreshFiles()
  } catch { alert(t('common.error')) }
}

// 打开回收站（当前源文件夹根部的 _Recycle 目录）
function openRecycleBin() {
  navigateTo(`${sourceFolder.value}/${RECYCLE_BIN_NAME}`)
}

// 软删除：确认后移入回收站
function confirmDelete(file) {
  deleteTarget.value = file
  deleteDialog.value?.show()
}

async function doDelete() {
  if (!deleteTarget.value) return
  try {
    await fileApi.deleteFile(deleteTarget.value.uuid)
    closePreview()
    refreshFiles()
  } catch { alert(t('common.error')) }
  deleteTarget.value = null
  bulkDeletePending.value = false
}
</script>

<style scoped>
.slide-up-enter-active, .slide-up-leave-active { transition: transform 0.25s ease; }
.slide-up-enter-from, .slide-up-leave-to { transform: translateY(100%); }
</style>
