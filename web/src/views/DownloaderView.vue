<template>
  <AppLayout>
    <template #header>
      <div class="flex items-center gap-0.5 flex-1 text-sm">
        <button class="btn btn-ghost btn-xs" :class="{ 'font-bold': !subPage }" @click="subPage = ''">
          {{ $t('downloader.title') }}
        </button>
        <template v-if="subPage">
          <ChevronRight :size="14" class="text-base-content/30" />
          <span class="btn btn-ghost btn-xs font-bold">{{ subPageTitle }}</span>
        </template>
      </div>
      <div class="flex gap-1">
        <button class="btn btn-ghost btn-sm" @click="subPage = 'tasks'; refreshTasks()" :title="$t('downloader.activeTasks')">
          <ListTodo :size="16" />
          <span v-if="activeTasks.length" class="badge badge-sm badge-outline ml-1">{{ activeTasks.length }}</span>
        </button>
        <button class="btn btn-ghost btn-sm" @click="subPage = 'history'; loadHistory(true)" :title="$t('downloader.history')">
          <History :size="16" />
        </button>
        <button class="btn btn-ghost btn-sm" @click="settingsDialog?.showModal()" :title="$t('downloader.auth')">
          <Settings2 :size="16" />
        </button>
      </div>
    </template>

    <div class="max-w-xl mx-auto p-6">
      <!-- Main page — centered form -->
      <template v-if="!subPage">
        <div class="flex flex-col items-center justify-center min-h-[60vh] space-y-5">
          <!-- URL input + paste button -->
          <div class="flex gap-2 w-full">
            <input
              v-model="url"
              type="text"
              :placeholder="$t('downloader.urlPlaceholder')"
              class="input input-bordered flex-1"
              @input="onUrlInput"
            />
            <button class="btn btn-ghost" @click="pasteFromClipboard" :title="$t('downloader.paste')">
              <ClipboardPaste :size="18" />
            </button>
          </div>

          <!-- Target folder -->
          <div class="w-full">
            <label class="text-xs text-base-content/50 mb-1.5 block">{{ $t('downloader.saveFolder') }}</label>
            <div class="flex flex-wrap gap-1.5">
              <!-- Current folder (root) — default -->
              <button
                class="btn btn-xs"
                :class="saveFolder === '.' ? 'btn-neutral' : 'btn-ghost'"
                @click="saveFolder = '.'"
              >
                {{ $t('downloader.currentFolder') }}
              </button>
              <button
                v-for="f in folders" :key="f.name"
                class="btn btn-xs"
                :class="saveFolder === f.name ? 'btn-neutral' : 'btn-ghost'"
                @click="saveFolder = f.name"
              >{{ f.name }}</button>
              <div class="flex gap-1">
                <input v-model="newFolderName" type="text" :placeholder="$t('downloader.folderName')"
                  class="input input-bordered input-xs w-24" @keyup.enter="createNewFolder" />
                <button class="btn btn-xs btn-ghost" @click="createNewFolder" :disabled="!newFolderName.trim()">
                  <Plus :size="14" />
                </button>
              </div>
            </div>
          </div>

          <!-- Downloader selection -->
          <div class="w-full">
            <label class="text-xs text-base-content/50 mb-1.5 block">
              {{ $t('downloader.downloaderLabel') }}{{ detected?.platformName ? ' — ' + detected.platformName : '' }}
            </label>
            <div class="flex gap-1.5">
              <button
                v-for="dl in downloaders" :key="dl.value"
                class="btn btn-xs"
                :class="selectedDownloader === dl.value ? 'btn-neutral' : 'btn-ghost'"
                @click="selectedDownloader = dl.value"
              >{{ dl.label }}</button>
            </div>
          </div>

          <!-- Download button -->
          <button
            class="btn btn-neutral w-full"
            @click="startDownload"
            :disabled="!url.trim() || !detected"
          >
            <Download :size="16" />
            {{ $t('downloader.startDownload') }}
          </button>
        </div>
      </template>

      <!-- Tasks sub-page -->
      <template v-if="subPage === 'tasks'">
        <TaskList :tasks="activeTasks" :empty-text="$t('downloader.noTasks')" @cancel="cancelTask" />
      </template>

      <!-- History sub-page -->
      <template v-if="subPage === 'history'">
        <div class="flex justify-end mb-3">
          <button v-if="history.length" class="btn btn-ghost btn-xs text-error" @click="doClearHistory">
            {{ $t('downloader.clearHistory') }}
          </button>
        </div>
        <TaskList :tasks="history" :empty-text="$t('downloader.noHistory')" :has-more="historyHasMore"
          @delete="deleteHistoryTask" @load-more="loadMoreHistory" />
      </template>
    </div>

    <!-- Settings dialog -->
    <dialog ref="settingsDialog" class="modal">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">{{ $t('downloader.auth') }}</h3>
        <div class="space-y-3">
          <div v-for="p in ['x', 'pixiv']" :key="p" class="flex items-center justify-between py-2">
            <div class="flex items-center gap-2">
              <span class="text-sm">{{ p === 'x' ? 'X (Twitter)' : 'Pixiv' }}</span>
              <span class="badge badge-sm" :class="authStatus[p] ? 'badge-outline' : 'badge-ghost'">
                {{ authStatus[p] ? $t('downloader.configured') : $t('downloader.notConfigured') }}
              </span>
            </div>
            <div class="flex gap-1">
              <button class="btn btn-ghost btn-xs" @click="showAuthInput(p)">{{ $t('downloader.uploadAuth') }}</button>
              <button v-if="authStatus[p]" class="btn btn-ghost btn-xs text-error" @click="deleteAuth(p)">{{ $t('downloader.deleteAuth') }}</button>
            </div>
          </div>
          <div class="flex items-center justify-between py-2 border-t border-base-300 pt-3">
            <div class="flex items-center gap-2">
              <span class="text-sm">yt-dlp</span>
              <span class="text-xs text-base-content/40">{{ ytdlpVersion || '---' }}</span>
            </div>
            <button class="btn btn-ghost btn-xs" @click="doUpdateYtdlp" :disabled="ytdlpUpdating">
              <span v-if="ytdlpUpdating" class="loading loading-spinner loading-xs"></span>
              {{ $t('downloader.ytdlpUpdate') }}
            </button>
          </div>
        </div>
        <div class="modal-action">
          <button class="btn" @click="settingsDialog?.close()">{{ $t('common.close') }}</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>

    <!-- Auth input -->
    <dialog ref="authDialog" class="modal">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">{{ authPlatform }}</h3>
        <textarea v-model="authContent" :placeholder="$t('downloader.authPlaceholder')" class="textarea textarea-bordered w-full h-32"></textarea>
        <div class="modal-action">
          <button class="btn" @click="authDialog?.close()">{{ $t('common.cancel') }}</button>
          <button class="btn btn-neutral" @click="doUploadAuth" :disabled="!authContent.trim()">{{ $t('common.confirm') }}</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>
  </AppLayout>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { Download, ChevronRight, Plus, History, Settings2, ListTodo, ClipboardPaste } from 'lucide-vue-next'
import AppLayout from '../components/layout/AppLayout.vue'
import TaskList from '../components/downloader/TaskList.vue'
import * as downloadApi from '../api/download'
import * as configApi from '../api/config'
import * as folderApi from '../api/folder'
import { usePolling } from '../composables/usePolling'

const { t } = useI18n()

const subPage = ref('')
const subPageTitle = computed(() => {
  if (subPage.value === 'tasks') return t('downloader.activeTasks')
  if (subPage.value === 'history') return t('downloader.history')
  return ''
})

const url = ref('')
const saveFolder = ref('.')
const newFolderName = ref('')
const detected = ref(null)
const detecting = ref(false)
const folders = ref([])
const manualDownloader = ref(false)
const selectedDownloader = ref('auto')

const downloaders = [
  { value: 'auto', label: 'Auto' },
  { value: 'ytdlp', label: 'yt-dlp' },
  { value: 'pixiv_toolkit', label: 'Pixiv Toolkit' },
]

const activeTasks = ref([])
const history = ref([])
const historyOffset = ref(0)
const historyHasMore = ref(false)

const authStatus = ref({ x: false, pixiv: false })
const settingsDialog = ref(null)
const authDialog = ref(null)
const authPlatform = ref('')
const authContent = ref('')
const ytdlpVersion = ref('')
const ytdlpUpdating = ref(false)
const sourceFolder = ref('')

const polling = usePolling(async () => {
  const { data } = await downloadApi.getActiveTasks()
  activeTasks.value = data.tasks || []
  if (!activeTasks.value.length) polling.stop()
}, 2000)

onMounted(async () => {
  try {
    const { data: dlConfig } = await configApi.getDownloadConfig()
    sourceFolder.value = dlConfig.sourceFolder
    authStatus.value = dlConfig.authStatus || { x: false, pixiv: false }
    ytdlpVersion.value = dlConfig.ytdlpVersion || ''

    const { data: folderList } = await folderApi.listFolders(sourceFolder.value)
    folders.value = folderList

    await refreshTasks()
  } catch {}
})

async function pasteFromClipboard() {
  try {
    const text = await navigator.clipboard.readText()
    if (text) {
      url.value = text.trim()
      onUrlInput()
    }
  } catch {}
}

let detectTimer = null
function onUrlInput() {
  clearTimeout(detectTimer)
  detected.value = null
  detecting.value = false
  if (!url.value.trim()) return
  detecting.value = true
  detectTimer = setTimeout(async () => {
    try {
      const { data } = await downloadApi.detectUrl(url.value.trim())
      detected.value = data
      // Auto-select downloader from detection
      if (!manualDownloader.value && data.downloader) {
        selectedDownloader.value = data.downloader
      }
    } catch {}
    detecting.value = false
  }, 600)
}

async function startDownload() {
  if (!url.value.trim() || !detected.value) return
  const dl = selectedDownloader.value === 'auto' ? detected.value?.downloader : selectedDownloader.value
  const folder = saveFolder.value === '.' ? sourceFolder.value : saveFolder.value
  try {
    await downloadApi.createTask(url.value.trim(), folder, dl)
    url.value = ''
    detected.value = null
    selectedDownloader.value = 'auto'
    manualDownloader.value = false
    await refreshTasks()
    polling.start()
  } catch {}
}

async function refreshTasks() {
  try {
    const { data } = await downloadApi.getActiveTasks()
    activeTasks.value = data.tasks || []
    if (activeTasks.value.length) polling.start()
  } catch {}
}

async function cancelTask(id) {
  await downloadApi.cancelTask(id)
  await refreshTasks()
}

async function loadHistory(reset = false) {
  if (reset) historyOffset.value = 0
  try {
    const { data } = await downloadApi.getHistory(historyOffset.value, 50)
    if (reset) history.value = data.items || []
    else history.value.push(...(data.items || []))
    historyHasMore.value = data.hasMore
    historyOffset.value += (data.items?.length || 0)
  } catch {}
}

function loadMoreHistory() { loadHistory(false) }

async function deleteHistoryTask(id) {
  await downloadApi.cancelTask(id)
  await loadHistory(true)
}

async function doClearHistory() {
  await downloadApi.clearHistory()
  await loadHistory(true)
}

async function createNewFolder() {
  if (!newFolderName.value.trim()) return
  try {
    await folderApi.createFolder(newFolderName.value.trim())
    saveFolder.value = newFolderName.value.trim()
    newFolderName.value = ''
    const { data } = await folderApi.listFolders(sourceFolder.value)
    folders.value = data
  } catch {}
}

function showAuthInput(platform) {
  authPlatform.value = platform
  authContent.value = ''
  authDialog.value?.showModal()
}

async function doUploadAuth() {
  try {
    await configApi.uploadCredentials(authPlatform.value, authContent.value)
    authStatus.value[authPlatform.value] = true
    authDialog.value?.close()
  } catch {}
}

async function deleteAuth(platform) {
  try {
    await configApi.deleteCredentials(platform)
    authStatus.value[platform] = false
  } catch {}
}

async function doUpdateYtdlp() {
  ytdlpUpdating.value = true
  try {
    await downloadApi.updateYtdlp()
    const { data } = await downloadApi.getYtdlpVersion()
    ytdlpVersion.value = data.version || ''
  } catch {}
  ytdlpUpdating.value = false
}
</script>
