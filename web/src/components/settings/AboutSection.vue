<template>
  <div class="collapse collapse-arrow join-item border border-base-300">
    <input type="radio" name="settings-accordion" />
    <div class="collapse-title font-medium text-sm flex items-center gap-2">
      <Info :size="18" class="text-base-content/50" />
      {{ $t('settings.about') }}
    </div>
    <div class="collapse-content">
      <div class="space-y-2 text-sm">
        <!-- 网页端：静态文件由服务端托管，更新无需重启 -->
        <div class="flex justify-between items-center">
          <span class="text-base-content/50">{{ $t('settings.webVersion') }}</span>
          <div class="flex items-center gap-2">
            <span>{{ webVersion }}</span>
            <span v-if="hasWebUpdate" class="badge badge-outline badge-xs">{{ latestWebVersion }}</span>
            <button v-if="hasWebUpdate" class="btn btn-ghost btn-xs" @click="updateWeb" :disabled="updatingWeb">
              <span v-if="updatingWeb" class="loading loading-spinner loading-xs"></span>
              <Download v-else :size="14" />
            </button>
            <button v-else class="btn btn-ghost btn-xs" @click="checkWeb" :disabled="checkingWeb">
              <span v-if="checkingWeb" class="loading loading-spinner loading-xs"></span>
              <RefreshCw v-else :size="14" />
            </button>
          </div>
        </div>

        <!-- 服务端：替换二进制后需要重启 -->
        <div class="flex justify-between items-center">
          <span class="text-base-content/50">{{ $t('settings.serverVersion') }}</span>
          <div class="flex items-center gap-2">
            <span>{{ serverVersion || '—' }}</span>
            <span v-if="hasServerUpdate" class="badge badge-outline badge-xs">{{ latestServerVersion }}</span>
            <button v-if="hasServerUpdate" class="btn btn-ghost btn-xs" @click="updateServer" :disabled="updatingServer">
              <span v-if="updatingServer" class="loading loading-spinner loading-xs"></span>
              <Download v-else :size="14" />
            </button>
            <button v-else class="btn btn-ghost btn-xs" @click="checkServer" :disabled="checkingServer">
              <span v-if="checkingServer" class="loading loading-spinner loading-xs"></span>
              <RefreshCw v-else :size="14" />
            </button>
          </div>
        </div>

        <div class="flex gap-2 mt-4">
          <a v-if="iosUrl" :href="iosUrl" target="_blank" rel="noopener" class="btn btn-ghost btn-xs gap-1">
            <Smartphone :size="16" />
            iOS
          </a>
          <a v-if="githubUrl" :href="githubUrl" target="_blank" rel="noopener" class="btn btn-ghost btn-xs gap-1">
            <Github :size="16" />
            GitHub
          </a>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { Info, Github, Download, Smartphone, RefreshCw } from 'lucide-vue-next'
import * as configApi from '../../api/config'

const emit = defineEmits(['toast'])
const { t } = useI18n()

const webVersion = __APP_VERSION__
const serverVersion = ref('')
const githubUrl = ref('')
const iosUrl = ref('')

const latestWebVersion = ref('')
const hasWebUpdate = ref(false)
const checkingWeb = ref(false)
const updatingWeb = ref(false)

const latestServerVersion = ref('')
const hasServerUpdate = ref(false)
const checkingServer = ref(false)
const updatingServer = ref(false)

onMounted(loadAppInfo)

async function loadAppInfo() {
  try {
    const { data } = await configApi.getAppInfo()
    serverVersion.value = data.version || ''
    githubUrl.value = data.githubUrl || ''
    iosUrl.value = data.iosUrl || ''
  } catch {}
}

async function checkWeb() {
  checkingWeb.value = true
  try {
    // 问服务端：只有它知道自己托管的那份静态文件是什么版本
    const { data } = await configApi.checkWebUpdate()
    latestWebVersion.value = data.latestVersion || ''
    hasWebUpdate.value = data.hasUpdate || false
    if (!data.hasUpdate) emit('toast', t('settings.upToDate'))
  } catch {
    // 服务端没托管网页端（独立部署）时退回直接查 GitHub，只提示、不提供更新按钮
    const latest = await configApi.fetchLatestWebTag()
    if (latest) {
      latestWebVersion.value = latest
      hasWebUpdate.value = latest !== webVersion
    }
  }
  checkingWeb.value = false
}

async function updateWeb() {
  updatingWeb.value = true
  try {
    await configApi.doWebUpdate()
    emit('toast', t('settings.webUpdated'))
    hasWebUpdate.value = false
    // 静态文件已就位，刷新页面即可加载新版本
    setTimeout(() => window.location.reload(true), 1200)
  } catch {
    updatingWeb.value = false
  }
}

async function checkServer() {
  checkingServer.value = true
  try {
    const { data } = await configApi.checkUpdate()
    latestServerVersion.value = data.latestVersion || ''
    hasServerUpdate.value = data.hasUpdate || false
    if (!data.hasUpdate) emit('toast', t('settings.upToDate'))
  } catch {}
  checkingServer.value = false
}

async function updateServer() {
  updatingServer.value = true
  try {
    await configApi.doUpdate()
    emit('toast', t('settings.updateStarted'))
    hasServerUpdate.value = false
    await configApi.waitForServerRestart()
    await loadAppInfo()
    emit('toast', t('settings.upToDate'))
  } catch {}
  updatingServer.value = false
}
</script>
