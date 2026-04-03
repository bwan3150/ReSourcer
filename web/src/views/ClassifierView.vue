<template>
  <AppLayout>
    <div class="flex h-[calc(100vh-64px)]">
      <!-- Main preview area -->
      <div class="flex-1 flex flex-col min-w-0">
        <!-- Progress -->
        <div class="px-4 py-2 border-b border-base-300 flex items-center gap-3 shrink-0">
          <span class="text-sm">{{ $t('classifier.progress') }}: {{ processedCount }} / {{ totalFiles }}</span>
          <progress class="progress progress-primary flex-1" :value="processedCount" :max="totalFiles"></progress>
          <button class="btn btn-ghost btn-sm" @click="undo" :disabled="!undoStack.length" :title="$t('classifier.undoHint')">
            ↩ {{ $t('classifier.undo') }}
          </button>
        </div>

        <!-- File preview -->
        <div class="flex-1 flex items-center justify-center bg-base-200 relative">
          <template v-if="currentFile">
            <img
              v-if="isImage"
              :src="currentContentUrl"
              :alt="currentFile.fileName"
              class="max-w-full max-h-full object-contain"
            />
            <video
              v-else-if="isVideo"
              :key="currentContentUrl"
              :src="currentContentUrl"
              controls
              autoplay
              class="max-w-full max-h-full object-contain"
            />
            <div v-else class="text-base-content/50 text-lg">{{ currentFile.fileName }}</div>
          </template>
          <div v-else-if="!loading" class="text-center">
            <p class="text-2xl mb-2">{{ totalFiles === 0 ? $t('classifier.noFiles') : $t('classifier.allDone') }}</p>
          </div>
          <div v-if="loading" class="loading loading-spinner loading-lg"></div>
        </div>

        <!-- File name -->
        <div v-if="currentFile" class="px-4 py-2 border-t border-base-300 text-sm text-center truncate shrink-0">
          {{ currentFile.fileName }}
        </div>
      </div>

      <!-- Category sidebar -->
      <aside class="w-72 bg-base-200 border-l border-base-300 flex flex-col overflow-hidden">
        <div class="p-3 border-b border-base-300">
          <h3 class="font-bold">{{ $t('classifier.categories') }}</h3>
          <p class="text-xs text-base-content/50 mt-1">{{ $t('classifier.shortcutHint') }}</p>
        </div>

        <div class="flex-1 overflow-y-auto p-2 space-y-1">
          <button
            v-for="(cat, i) in categories"
            :key="cat.name"
            class="btn btn-outline btn-sm w-full justify-start gap-2"
            @click="classify(cat)"
            :disabled="!currentFile"
          >
            <kbd class="kbd kbd-xs">{{ shortcutLabel(i) }}</kbd>
            <span class="truncate">{{ cat.name }}</span>
            <span class="badge badge-sm badge-ghost ml-auto">{{ cat.fileCount }}</span>
          </button>
        </div>

        <!-- Actions -->
        <div class="p-3 border-t border-base-300 space-y-2 shrink-0">
          <button class="btn btn-ghost btn-sm w-full" @click="skipFile" :disabled="!currentFile">
            {{ $t('classifier.skipFile') }} →
          </button>

          <!-- Preset selector -->
          <div v-if="presets.length" class="dropdown dropdown-top w-full">
            <label tabindex="0" class="btn btn-ghost btn-sm w-full">{{ $t('classifier.loadPreset') }}</label>
            <ul tabindex="0" class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow w-full mb-1">
              <li v-for="preset in presets" :key="preset.name">
                <a @click="loadPreset(preset.name)">{{ preset.name }}</a>
              </li>
            </ul>
          </div>
        </div>
      </aside>
    </div>
  </AppLayout>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import AppLayout from '../components/layout/AppLayout.vue'
import * as configApi from '../api/config'
import * as indexerApi from '../api/indexer'
import * as fileApi from '../api/file'
import * as folderApi from '../api/folder'
import { contentUrl } from '../api/preview'

const { t } = useI18n()

const sourceFolder = ref('')
const categories = ref([])
const presets = ref([])
const files = ref([])
const currentIndex = ref(0)
const loading = ref(false)
const undoStack = ref([])
const processedCount = ref(0)
const totalFiles = ref(0)

const currentFile = computed(() => files.value[currentIndex.value] || null)
const isImage = computed(() => ['image', 'gif'].includes(currentFile.value?.fileType))
const isVideo = computed(() => currentFile.value?.fileType === 'video')
const currentContentUrl = computed(() => currentFile.value ? contentUrl(currentFile.value) : '')

function shortcutLabel(i) {
  if (i < 9) return String(i + 1)
  if (i < 35) return String.fromCharCode(65 + i - 9)
  return ''
}

onMounted(async () => {
  loading.value = true
  try {
    const { data: state } = await configApi.getConfigState()
    sourceFolder.value = state.sourceFolder
    presets.value = state.presets || []

    // Load categories
    const { data: folderList } = await folderApi.listFolders(sourceFolder.value)
    categories.value = folderList.filter(f => !f.hidden)

    // Load files from source root
    const { data: fileData } = await indexerApi.getFiles(sourceFolder.value, { offset: 0, limit: 500 })
    files.value = fileData.files
    totalFiles.value = fileData.total
  } catch (err) {
    console.error(err)
  }
  loading.value = false
})

async function classify(category) {
  if (!currentFile.value) return
  const file = currentFile.value
  const targetPath = `${sourceFolder.value}/${category.name}`

  try {
    await fileApi.moveFile(file.uuid, targetPath)
    undoStack.value.push({ uuid: file.uuid, fromFolder: sourceFolder.value, fileName: file.fileName })
    if (undoStack.value.length > 20) undoStack.value.shift()
    files.value.splice(currentIndex.value, 1)
    processedCount.value++
    if (currentIndex.value >= files.value.length) currentIndex.value = Math.max(0, files.value.length - 1)
  } catch {
    alert(t('common.error'))
  }
}

async function undo() {
  const last = undoStack.value.pop()
  if (!last) return
  try {
    await fileApi.moveFile(last.uuid, last.fromFolder)
    // Reload files
    const { data } = await indexerApi.getFiles(sourceFolder.value, { offset: 0, limit: 500 })
    files.value = data.files
    processedCount.value = Math.max(0, processedCount.value - 1)
  } catch {
    alert(t('common.error'))
  }
}

function skipFile() {
  if (currentIndex.value < files.value.length - 1) {
    currentIndex.value++
  }
}

async function loadPreset(name) {
  try {
    const { data } = await configApi.loadPreset(name)
    // Reload categories
    const { data: folderList } = await folderApi.listFolders(sourceFolder.value)
    categories.value = folderList.filter(f => !f.hidden)
  } catch {}
}

// Keyboard shortcuts
function onKeydown(e) {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return

  // Ctrl+Z / Cmd+Z for undo
  if ((e.ctrlKey || e.metaKey) && e.key === 'z') {
    e.preventDefault()
    undo()
    return
  }

  // 1-9 for first 9 categories
  if (e.key >= '1' && e.key <= '9') {
    const idx = parseInt(e.key) - 1
    if (idx < categories.value.length) classify(categories.value[idx])
    return
  }

  // a-z for categories 10-35
  if (e.key >= 'a' && e.key <= 'z' && !e.ctrlKey && !e.metaKey) {
    const idx = e.key.charCodeAt(0) - 97 + 9
    if (idx < categories.value.length) classify(categories.value[idx])
    return
  }

  // Right arrow to skip
  if (e.key === 'ArrowRight') skipFile()
}

onMounted(() => window.addEventListener('keydown', onKeydown))
onUnmounted(() => window.removeEventListener('keydown', onKeydown))
</script>
