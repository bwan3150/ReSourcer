<template>
  <AppLayout>
    <div class="flex h-full overflow-hidden">
      <!-- Main preview area -->
      <div class="flex-1 flex flex-col min-w-0 overflow-hidden">
        <!-- Progress bar -->
        <div class="px-4 py-2 border-b border-base-300 flex items-center gap-3 shrink-0">
          <button class="btn btn-ghost btn-xs gap-1" @click="undo" :disabled="!undoStack.length" :title="$t('classifier.undoHint')">
            <Undo2 :size="14" />
          </button>
          <progress class="progress flex-1" :value="processedCount" :max="totalFiles"></progress>
          <span class="text-xs text-base-content/50 tabular-nums">{{ processedCount }}/{{ totalFiles }}</span>
          <label class="swap swap-rotate btn btn-ghost btn-xs" :title="showOriginal ? $t('classifier.thumbnail') : $t('classifier.original')">
            <input type="checkbox" v-model="showOriginal" />
            <ImageIcon :size="14" class="swap-off" />
            <Maximize :size="14" class="swap-on" />
          </label>
        </div>

        <!-- Media player (fills remaining height) -->
        <div class="flex-1 min-h-0 overflow-hidden">
          <template v-if="currentFile">
            <MediaPlayer
              :src="currentContentUrl"
              :type="currentMediaType"
              :file-name="currentFile.fileName"
              :autoplay="showOriginal"
            />
          </template>
          <div v-else-if="!loading" class="flex items-center justify-center h-full">
            <p class="text-base-content/30">{{ totalFiles === 0 ? $t('classifier.noFiles') : $t('classifier.allDone') }}</p>
          </div>
          <div v-if="loading" class="flex items-center justify-center h-full">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        </div>

        <!-- File name -->
        <div v-if="currentFile" class="px-4 py-1.5 border-t border-base-300 text-xs text-center truncate shrink-0 text-base-content/50">
          {{ currentFile.fileName }}
        </div>
      </div>

      <!-- Category sidebar (only this scrolls internally) -->
      <aside class="w-64 border-l border-base-300 flex flex-col overflow-hidden shrink-0">
        <div class="p-3 border-b border-base-300 shrink-0">
          <p class="text-xs text-base-content/50">{{ $t('classifier.shortcutHint') }}</p>
        </div>

        <div class="flex-1 overflow-y-auto p-2 space-y-0.5">
          <button
            v-for="(cat, i) in categories"
            :key="cat.name"
            class="btn btn-ghost btn-sm w-full justify-start gap-2"
            @click="classify(cat)"
            :disabled="!currentFile"
          >
            <kbd class="kbd kbd-xs">{{ shortcutLabel(i) }}</kbd>
            <span class="truncate flex-1 text-left">{{ cat.name }}</span>
            <span class="text-xs text-base-content/40">{{ cat.fileCount }}</span>
          </button>
        </div>

        <div class="p-2 border-t border-base-300 space-y-1 shrink-0">
          <button class="btn btn-ghost btn-xs w-full gap-1" @click="skipFile" :disabled="!currentFile">
            {{ $t('classifier.skipFile') }}
            <ChevronRight :size="14" />
          </button>
        </div>
      </aside>
    </div>
  </AppLayout>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import AppLayout from '../components/layout/AppLayout.vue'
import MediaPlayer from '../components/shared/MediaPlayer.vue'
import { Undo2, ChevronRight, Image as ImageIcon, Maximize } from 'lucide-vue-next'
import * as configApi from '../api/config'
import * as indexerApi from '../api/indexer'
import * as fileApi from '../api/file'
import * as folderApi from '../api/folder'
import { contentUrl, thumbnailUrl } from '../api/preview'

const { t } = useI18n()

const sourceFolder = ref('')
const categories = ref([])
const files = ref([])
const currentIndex = ref(0)
const loading = ref(false)
const undoStack = ref([])
const processedCount = ref(0)
const totalFiles = ref(0)

const currentFile = computed(() => files.value[currentIndex.value] || null)
const showOriginal = ref(false)
const currentContentUrl = computed(() => {
  if (!currentFile.value) return ''
  if (showOriginal.value) return contentUrl(currentFile.value)
  return thumbnailUrl(currentFile.value, 800)
})
const currentMediaType = computed(() => {
  if (!currentFile.value) return 'other'
  // In thumbnail mode, show everything as image (thumbnail is always jpg)
  if (!showOriginal.value) return 'image'
  return currentFile.value.fileType
})

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
    const { data: folderList } = await folderApi.listFolders(sourceFolder.value)
    categories.value = folderList.filter(f => !f.hidden)

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
    undoStack.value.push({ uuid: file.uuid, fromFolder: sourceFolder.value, fileName: file.fileName, categoryName: category.name })
    if (undoStack.value.length > 20) undoStack.value.shift()
    files.value.splice(currentIndex.value, 1)
    processedCount.value++
    if (currentIndex.value >= files.value.length) currentIndex.value = Math.max(0, files.value.length - 1)

    // Update category file count
    const cat = categories.value.find(c => c.name === category.name)
    if (cat) cat.fileCount = (cat.fileCount || 0) + 1
  } catch {
    alert(t('common.error'))
  }
}

async function undo() {
  const last = undoStack.value.pop()
  if (!last) return
  try {
    await fileApi.moveFile(last.uuid, last.fromFolder)
    const { data } = await indexerApi.getFiles(sourceFolder.value, { offset: 0, limit: 500 })
    files.value = data.files
    processedCount.value = Math.max(0, processedCount.value - 1)

    // Update category file count
    if (last.categoryName) {
      const cat = categories.value.find(c => c.name === last.categoryName)
      if (cat && cat.fileCount > 0) cat.fileCount--
    }
  } catch {
    alert(t('common.error'))
  }
}

function skipFile() {
  if (currentIndex.value < files.value.length - 1) {
    currentIndex.value++
  }
}

function onKeydown(e) {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return
  if ((e.ctrlKey || e.metaKey) && e.key === 'z') { e.preventDefault(); undo(); return }
  if (e.key >= '1' && e.key <= '9') {
    const idx = parseInt(e.key) - 1
    if (idx < categories.value.length) classify(categories.value[idx])
    return
  }
  if (e.key >= 'a' && e.key <= 'z' && !e.ctrlKey && !e.metaKey) {
    const idx = e.key.charCodeAt(0) - 97 + 9
    if (idx < categories.value.length) classify(categories.value[idx])
    return
  }
  if (e.key === 'ArrowRight') skipFile()
}

onMounted(() => window.addEventListener('keydown', onKeydown))
onUnmounted(() => window.removeEventListener('keydown', onKeydown))
</script>
