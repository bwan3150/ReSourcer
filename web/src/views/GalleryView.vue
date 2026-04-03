<template>
  <AppLayout>
    <div class="flex h-full">
      <!-- Sidebar -->
      <FolderSidebar
        :source-folder="sourceFolder"
        :sources="allSources"
        :folders="folders"
        :current-folder="currentFolder"
        :loading="loadingFolders"
        @select="selectFolder"
        @switch-source="onSwitchSource"
      />

      <!-- Main content -->
      <div class="flex-1 flex flex-col min-w-0">
        <!-- Toolbar -->
        <div class="flex items-center gap-3 px-4 py-2 border-b border-base-300 shrink-0">
          <!-- Breadcrumb -->
          <div class="flex items-center gap-1 text-sm flex-1 min-w-0 overflow-hidden">
            <button
              v-for="(crumb, i) in breadcrumbs"
              :key="crumb.path"
              class="btn btn-ghost btn-xs"
              :class="{ 'font-bold': i === breadcrumbs.length - 1 }"
              @click="selectFolder(crumb.path)"
            >
              {{ crumb.name }}
            </button>
          </div>

          <span class="text-sm text-base-content/50">{{ total }} {{ $t('gallery.files') }}</span>
          <UploadArea :target-folder="currentFolder" @uploaded="refreshFiles" />
        </div>

        <!-- File grid -->
        <div class="flex-1 overflow-y-auto">
          <FileGrid
            :files="files"
            :loading="loadingFiles"
            :has-more="hasMore"
            @preview="openPreview"
            @load-more="loadMore"
          />
        </div>
      </div>
    </div>

    <!-- Preview Modal -->
    <FilePreviewModal
      ref="previewModal"
      :file="previewFile"
      :current-index="previewIndex"
      :total="files.length"
      @prev="prevFile"
      @next="nextFile"
      @close="previewFile = null"
      @rename="startRename"
      @move="startMove"
    />

    <!-- Rename Dialog -->
    <dialog ref="renameDialog" class="modal">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">{{ $t('common.rename') }}</h3>
        <input v-model="renameValue" class="input input-bordered w-full" @keyup.enter="doRename" />
        <div class="modal-action">
          <button class="btn" @click="renameDialog?.close()">{{ $t('common.cancel') }}</button>
          <button class="btn btn-primary" @click="doRename" :disabled="!renameValue.trim()">{{ $t('common.confirm') }}</button>
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
            class="btn btn-ghost btn-sm w-full justify-start"
            :class="{ 'btn-active': moveTarget === f.path }"
            @click="moveTarget = f.path"
          >
            <Folder :size="16" class="shrink-0" /> {{ f.name }}
          </button>
        </div>
        <div class="modal-action">
          <button class="btn" @click="moveDialog?.close()">{{ $t('common.cancel') }}</button>
          <button class="btn btn-primary" @click="doMove" :disabled="!moveTarget">{{ $t('common.confirm') }}</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>
  </AppLayout>
</template>

<script setup>
import { ref, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import AppLayout from '../components/layout/AppLayout.vue'
import FolderSidebar from '../components/gallery/FolderSidebar.vue'
import FileGrid from '../components/gallery/FileGrid.vue'
import FilePreviewModal from '../components/gallery/FilePreviewModal.vue'
import UploadArea from '../components/gallery/UploadArea.vue'
import { Folder } from 'lucide-vue-next'
import * as indexerApi from '../api/indexer'
import * as configApi from '../api/config'
import * as fileApi from '../api/file'

const { t } = useI18n()
const PAGE_SIZE = 50

// State
const sourceFolder = ref('')
const allSources = ref([])
const folders = ref([])
const currentFolder = ref('')
const breadcrumbs = ref([])
const files = ref([])
const total = ref(0)
const offset = ref(0)
const hasMore = ref(false)
const loadingFolders = ref(false)
const loadingFiles = ref(false)

// Preview
const previewModal = ref(null)
const previewFile = ref(null)
const previewIndex = ref(0)

// Rename
const renameDialog = ref(null)
const renameValue = ref('')
const renameTarget = ref(null)

// Move
const moveDialog = ref(null)
const moveTarget = ref('')
const moveFolders = ref([])
const moveTargetFile = ref(null)

onMounted(async () => {
  const { data } = await configApi.getSources()
  allSources.value = [data.current, ...(data.backups || [])]
  sourceFolder.value = data.current
  if (sourceFolder.value) {
    currentFolder.value = sourceFolder.value
    await loadFolders()
    await loadFiles(true)
  }
})

async function loadFolders() {
  loadingFolders.value = true
  try {
    const { data } = await indexerApi.getFolders(sourceFolder.value, sourceFolder.value)
    folders.value = data
  } catch { folders.value = [] }
  loadingFolders.value = false
}

async function loadFiles(reset = false) {
  if (reset) {
    offset.value = 0
    files.value = []
  }
  loadingFiles.value = true
  try {
    const { data } = await indexerApi.getFiles(currentFolder.value, {
      offset: offset.value, limit: PAGE_SIZE,
    })
    if (reset) {
      files.value = data.files
    } else {
      files.value.push(...data.files)
    }
    total.value = data.total
    hasMore.value = data.hasMore
    offset.value += data.files.length
  } catch { /* ignore */ }
  loadingFiles.value = false

  // Load breadcrumb
  try {
    const { data } = await indexerApi.getBreadcrumb(currentFolder.value)
    breadcrumbs.value = data
  } catch { breadcrumbs.value = [] }
}

async function loadMore() {
  await loadFiles(false)
}

async function selectFolder(path) {
  currentFolder.value = path
  await loadFiles(true)
}

async function onSwitchSource(path) {
  sourceFolder.value = path
  currentFolder.value = path
  await configApi.switchSource(path)
  await loadFolders()
  await loadFiles(true)
}

function refreshFiles() {
  loadFiles(true)
}

// Preview
function openPreview(file) {
  previewFile.value = file
  previewIndex.value = files.value.findIndex(f => f.uuid === file.uuid)
  previewModal.value?.show()
}

function prevFile() {
  if (previewIndex.value > 0) {
    previewIndex.value--
    previewFile.value = files.value[previewIndex.value]
  }
}

function nextFile() {
  if (previewIndex.value < files.value.length - 1) {
    previewIndex.value++
    previewFile.value = files.value[previewIndex.value]
  }
}

// Rename
function startRename(file) {
  renameTarget.value = file
  renameValue.value = file.fileName.replace(/\.[^.]+$/, '')
  renameDialog.value?.showModal()
}

async function doRename() {
  if (!renameTarget.value || !renameValue.value.trim()) return
  const ext = renameTarget.value.fileName.match(/\.[^.]+$/)?.[0] || ''
  const newName = renameValue.value.trim() + ext
  try {
    await fileApi.renameFile(renameTarget.value.uuid, newName)
    renameDialog.value?.close()
    refreshFiles()
  } catch (err) {
    alert(t('common.error'))
  }
}

// Move
async function startMove(file) {
  moveTargetFile.value = file
  moveTarget.value = ''
  moveFolders.value = folders.value.filter(f => f.path !== currentFolder.value)
  moveDialog.value?.showModal()
}

async function doMove() {
  if (!moveTargetFile.value || !moveTarget.value) return
  try {
    await fileApi.moveFile(moveTargetFile.value.uuid, moveTarget.value)
    moveDialog.value?.close()
    previewModal.value?.close()
    refreshFiles()
  } catch {
    alert(t('common.error'))
  }
}
</script>
