<template>
  <AppLayout>
    <div class="max-w-4xl mx-auto p-6 space-y-6">
      <!-- URL Input Section -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">{{ $t('downloader.title') }}</h2>

          <!-- URL input -->
          <div class="flex gap-2">
            <input
              v-model="url"
              type="text"
              :placeholder="$t('downloader.urlPlaceholder')"
              class="input input-bordered flex-1"
              @input="onUrlInput"
            />
            <button class="btn btn-outline" @click="detect" :disabled="detecting || !url.trim()">
              <span v-if="detecting" class="loading loading-spinner loading-xs"></span>
              {{ detecting ? $t('downloader.detecting') : $t('downloader.detect') }}
            </button>
          </div>

          <!-- Detection result -->
          <div v-if="detected" class="flex items-center gap-2 mt-2">
            <span class="badge badge-info">{{ detected.platformName }}</span>
            <span v-if="detected.requiresAuth" class="badge badge-warning">{{ $t('downloader.requiresAuth') }}</span>
          </div>

          <!-- Folder selection -->
          <div class="mt-3">
            <label class="label"><span class="label-text">{{ $t('downloader.saveFolder') }}</span></label>
            <div class="flex flex-wrap gap-2">
              <button
                v-for="f in folders"
                :key="f.name"
                class="btn btn-sm"
                :class="saveFolder === f.name ? 'btn-primary' : 'btn-outline'"
                @click="saveFolder = f.name"
              >
                {{ f.name }}
              </button>
              <!-- New folder -->
              <div class="flex gap-1">
                <input
                  v-model="newFolderName"
                  type="text"
                  :placeholder="$t('downloader.folderName')"
                  class="input input-bordered input-sm w-32"
                  @keyup.enter="createNewFolder"
                />
                <button class="btn btn-sm btn-ghost" @click="createNewFolder" :disabled="!newFolderName.trim()">+</button>
              </div>
            </div>
          </div>

          <!-- Download button -->
          <div class="card-actions mt-4">
            <button
              class="btn btn-primary"
              @click="startDownload"
              :disabled="!url.trim() || !saveFolder"
            >
              {{ $t('downloader.startDownload') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Active Tasks -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h3 class="card-title text-base">{{ $t('downloader.activeTasks') }}</h3>
          <TaskList
            :tasks="activeTasks"
            :empty-text="$t('downloader.noTasks')"
            @cancel="cancelTask"
          />
        </div>
      </div>

      <!-- History -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex justify-between items-center">
            <h3 class="card-title text-base">{{ $t('downloader.history') }}</h3>
            <button v-if="history.length" class="btn btn-ghost btn-sm text-error" @click="doClearHistory">
              {{ $t('downloader.clearHistory') }}
            </button>
          </div>
          <TaskList
            :tasks="history"
            :empty-text="$t('downloader.noHistory')"
            :has-more="historyHasMore"
            @delete="deleteHistoryTask"
            @load-more="loadMoreHistory"
          />
        </div>
      </div>

      <!-- Auth & yt-dlp -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h3 class="card-title text-base">{{ $t('downloader.auth') }}</h3>

          <!-- X auth -->
          <div class="flex items-center justify-between py-2">
            <div>
              <span class="font-medium">X (Twitter)</span>
              <span class="badge badge-sm ml-2" :class="authStatus.x ? 'badge-success' : 'badge-ghost'">
                {{ authStatus.x ? $t('downloader.configured') : $t('downloader.notConfigured') }}
              </span>
            </div>
            <div class="flex gap-1">
              <button class="btn btn-ghost btn-xs" @click="showAuthInput('x')">{{ $t('downloader.uploadAuth') }}</button>
              <button v-if="authStatus.x" class="btn btn-ghost btn-xs text-error" @click="deleteAuth('x')">{{ $t('downloader.deleteAuth') }}</button>
            </div>
          </div>

          <!-- Pixiv auth -->
          <div class="flex items-center justify-between py-2">
            <div>
              <span class="font-medium">Pixiv</span>
              <span class="badge badge-sm ml-2" :class="authStatus.pixiv ? 'badge-success' : 'badge-ghost'">
                {{ authStatus.pixiv ? $t('downloader.configured') : $t('downloader.notConfigured') }}
              </span>
            </div>
            <div class="flex gap-1">
              <button class="btn btn-ghost btn-xs" @click="showAuthInput('pixiv')">{{ $t('downloader.uploadAuth') }}</button>
              <button v-if="authStatus.pixiv" class="btn btn-ghost btn-xs text-error" @click="deleteAuth('pixiv')">{{ $t('downloader.deleteAuth') }}</button>
            </div>
          </div>

          <!-- yt-dlp version -->
          <div class="flex items-center justify-between py-2 border-t border-base-300 mt-2 pt-3">
            <div>
              <span class="font-medium">{{ $t('downloader.ytdlpVersion') }}</span>
              <span class="text-sm text-base-content/50 ml-2">{{ ytdlpVersion || '—' }}</span>
            </div>
            <button class="btn btn-ghost btn-xs" @click="doUpdateYtdlp" :disabled="ytdlpUpdating">
              <span v-if="ytdlpUpdating" class="loading loading-spinner loading-xs"></span>
              {{ $t('downloader.ytdlpUpdate') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Auth input modal -->
      <dialog ref="authDialog" class="modal">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-4">{{ $t('downloader.uploadAuth') }} — {{ authPlatform }}</h3>
          <textarea
            v-model="authContent"
            :placeholder="$t('downloader.authPlaceholder')"
            class="textarea textarea-bordered w-full h-32"
          ></textarea>
          <div class="modal-action">
            <button class="btn" @click="authDialog?.close()">{{ $t('common.cancel') }}</button>
            <button class="btn btn-primary" @click="doUploadAuth" :disabled="!authContent.trim()">{{ $t('common.confirm') }}</button>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop"><button>close</button></form>
      </dialog>
    </div>
  </AppLayout>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import AppLayout from '../components/layout/AppLayout.vue'
import TaskList from '../components/downloader/TaskList.vue'
import * as downloadApi from '../api/download'
import * as configApi from '../api/config'
import * as folderApi from '../api/folder'
import { usePolling } from '../composables/usePolling'

const { t } = useI18n()

// Form
const url = ref('')
const saveFolder = ref('')
const newFolderName = ref('')
const detected = ref(null)
const detecting = ref(false)
const folders = ref([])

// Tasks
const activeTasks = ref([])
const history = ref([])
const historyOffset = ref(0)
const historyHasMore = ref(false)

// Auth
const authStatus = ref({ x: false, pixiv: false })
const authDialog = ref(null)
const authPlatform = ref('')
const authContent = ref('')
const ytdlpVersion = ref('')
const ytdlpUpdating = ref(false)

// Source folder
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
    await loadHistory(true)
  } catch {}
})

async function detect() {
  if (!url.value.trim()) return
  detecting.value = true
  try {
    const { data } = await downloadApi.detectUrl(url.value.trim())
    detected.value = data
  } catch { detected.value = null }
  detecting.value = false
}

let detectTimer = null
function onUrlInput() {
  clearTimeout(detectTimer)
  detected.value = null
  detectTimer = setTimeout(() => {
    if (url.value.trim()) detect()
  }, 800)
}

async function startDownload() {
  if (!url.value.trim() || !saveFolder.value) return
  try {
    await downloadApi.createTask(url.value.trim(), saveFolder.value, detected.value?.downloader)
    url.value = ''
    detected.value = null
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
  await loadHistory(true)
}

async function loadHistory(reset = false) {
  if (reset) historyOffset.value = 0
  try {
    const { data } = await downloadApi.getHistory(historyOffset.value, 50)
    if (reset) {
      history.value = data.items || []
    } else {
      history.value.push(...(data.items || []))
    }
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
