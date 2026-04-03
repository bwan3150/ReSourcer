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
        <!-- Preview header bar -->
        <div class="flex items-center gap-2 px-4 py-2 border-b border-base-300 shrink-0">
          <button class="btn btn-ghost btn-sm btn-square" @click="closePreview">
            <X :size="18" />
          </button>
          <span class="text-sm truncate flex-1">{{ previewFile.fileName }}</span>
          <span class="text-xs text-base-content/40">{{ previewIndex + 1 }} / {{ files.length }}</span>
          <button class="btn btn-ghost btn-xs btn-square" @click="fileInfoDialog?.showModal()" :title="$t('gallery.fileInfo')">
            <Info :size="16" />
          </button>
        </div>
        <!-- Player fills remaining space -->
        <div class="flex-1 min-h-0">
          <MediaPlayer
            :src="contentSrc"
            :type="previewFile.fileType"
            :file-name="previewFile.fileName"
            :show-nav="true"
            :has-prev="previewIndex > 0"
            :has-next="previewIndex < files.length - 1"
            @prev="prevFile"
            @next="nextFile"
          />
        </div>
      </div>
    </template>

    <!-- Browse mode (folder sidebar + file grid) -->
    <template v-else>
      <div class="flex h-full">
        <FolderSidebar
          :folders="subfolders"
          :loading="loadingFolders"
          :show-nav-buttons="currentFolder !== sourceFolder"
          @select="navigateTo"
          @go-up="goUp"
          @go-root="navigateTo(sourceFolder)"
        />
        <div
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

    <!-- Move Dialog -->
    <dialog ref="moveDialog" class="modal">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">{{ $t('gallery.moveTo') }}</h3>
        <div class="space-y-1 max-h-60 overflow-y-auto">
          <button
            v-for="f in moveFolders"
            :key="f.path"
            class="btn btn-ghost btn-sm w-full justify-start gap-2"
            :class="{ 'bg-base-300': moveTarget === f.path }"
            @click="moveTarget = f.path"
          >
            <Folder :size="16" class="shrink-0" /> {{ f.name }}
          </button>
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
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import AppLayout from '../components/layout/AppLayout.vue'
import FolderSidebar from '../components/gallery/FolderSidebar.vue'
import FileGrid from '../components/gallery/FileGrid.vue'
import MediaPlayer from '../components/shared/MediaPlayer.vue'
import UploadArea from '../components/gallery/UploadArea.vue'
import TagEditor from '../components/gallery/TagEditor.vue'
import { Folder, ChevronRight, X, Pencil, FolderInput, RefreshCw, Info, Download } from 'lucide-vue-next'
import { contentUrl } from '../api/preview'
import * as indexerApi from '../api/indexer'
import * as configApi from '../api/config'
import * as fileApi from '../api/file'
import * as tagApi from '../api/tag'

const { t } = useI18n()
const PAGE_SIZE = 50

const sourceFolder = ref('')
const currentFolder = ref('')
const breadcrumbs = ref([])
const subfolders = ref([])
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
const previewIndex = ref(0)
const contentSrc = computed(() => previewFile.value ? contentUrl(previewFile.value) : '')

const fileInfoDialog = ref(null)
const allTags = ref([])
const fileTags = ref([])
const renameDialog = ref(null)
const renameValue = ref('')
const renameTarget = ref(null)

const moveDialog = ref(null)
const moveTarget = ref('')
const moveFolders = ref([])
const moveTargetFile = ref(null)

onMounted(async () => {
  const { data } = await configApi.getSources()
  sourceFolder.value = data.current
  if (sourceFolder.value) {
    await navigateTo(sourceFolder.value)
    try {
      const { data: tags } = await tagApi.listTags(sourceFolder.value)
      allTags.value = tags
    } catch {}
  }
})

async function navigateTo(path) {
  closePreview()
  currentFolder.value = path
  loadingFolders.value = true
  switchingFolder.value = true
  offset.value = 0

  const [foldersRes, filesRes, breadcrumbRes] = await Promise.allSettled([
    indexerApi.getFolders(path, sourceFolder.value),
    indexerApi.getFiles(path, { offset: 0, limit: PAGE_SIZE }),
    indexerApi.getBreadcrumb(path),
  ])

  subfolders.value = foldersRes.status === 'fulfilled' ? foldersRes.value.data : []
  loadingFolders.value = false

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

function goUp() {
  if (breadcrumbs.value.length >= 2) navigateTo(breadcrumbs.value[breadcrumbs.value.length - 2].path)
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

function openPreview(file) {
  previewFile.value = file
  previewIndex.value = files.value.findIndex(f => f.uuid === file.uuid)
  loadFileTags(file.uuid)
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

function closePreview() { previewFile.value = null }

function prevFile() {
  if (previewIndex.value > 0) {
    previewIndex.value--
    previewFile.value = files.value[previewIndex.value]
    loadFileTags(previewFile.value.uuid)
  }
}

function nextFile() {
  if (previewIndex.value < files.value.length - 1) {
    previewIndex.value++
    previewFile.value = files.value[previewIndex.value]
    loadFileTags(previewFile.value.uuid)
  }
}

function onKeydown(e) {
  if (!previewFile.value) return
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return
  if (e.key === 'Escape') closePreview()
  else if (e.key === 'ArrowLeft') prevFile()
  else if (e.key === 'ArrowRight') nextFile()
}
onMounted(() => window.addEventListener('keydown', onKeydown))
onUnmounted(() => window.removeEventListener('keydown', onKeydown))

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
  moveFolders.value = subfolders.value.filter(f => f.path !== currentFolder.value)
  moveDialog.value?.showModal()
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
