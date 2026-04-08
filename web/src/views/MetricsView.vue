<template>
  <AppLayout>
    <template #header>
      <h1 class="text-lg font-bold flex-1">{{ $t('metrics.title') }}</h1>
    </template>

    <div class="p-4 space-y-4 max-w-3xl mx-auto">
      <!-- System info + Uptime -->
      <div class="grid grid-cols-2 gap-3">
        <div class="bg-base-200 rounded-xl p-4 flex flex-col gap-1">
          <div class="text-xs text-base-content/40 uppercase tracking-wider">{{ $t('metrics.system') }}</div>
          <div class="text-base font-mono font-bold text-center min-h-[1.75rem]">
            <span v-if="!systemInfo" class="loading loading-spinner loading-xs text-base-content/20"></span>
            <span v-else>{{ systemInfo.osName }} {{ systemInfo.arch }}</span>
          </div>
          <div v-if="systemInfo" class="text-xs text-base-content/30 text-center">{{ systemInfo.hostname }} · {{ systemInfo.cpuCount }} cores</div>
        </div>
        <div class="bg-base-200 rounded-xl p-4 flex flex-col gap-1">
          <div class="text-xs text-base-content/40 uppercase tracking-wider">{{ $t('metrics.uptime') }}</div>
          <div class="text-2xl font-mono font-bold text-center min-h-[1.75rem]">
            <span v-if="!current" class="loading loading-spinner loading-xs text-base-content/20"></span>
            <span v-else>{{ formatUptime(current.uptimeSeconds) }}</span>
          </div>
          <div v-if="current && current.systemUptimeSeconds" class="text-xs text-base-content/30 text-center">{{ $t('metrics.systemUptime') }}: {{ formatUptime(current.systemUptimeSeconds) }}</div>
        </div>
      </div>

      <!-- Live stats cards with progress bars -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <!-- CPU -->
        <div class="bg-base-200 rounded-xl p-4 flex flex-col items-center gap-1.5">
          <div class="text-lg font-bold font-mono tabular-nums flex items-center min-h-[1.75rem]"
            :style="current ? { color: severityColor(current.cpuUsagePercent) } : {}">
            <span v-if="!current" class="loading loading-spinner loading-xs text-base-content/20"></span>
            <template v-else>{{ current.cpuUsagePercent.toFixed(1) }}%</template>
          </div>
          <div class="text-xs text-base-content/40 uppercase tracking-wider">CPU</div>
          <div class="w-full h-1.5 rounded-full bg-base-300 overflow-hidden mt-1">
            <div class="h-full rounded-full transition-all duration-500"
              :style="{ width: (current ? current.cpuUsagePercent : 0) + '%', backgroundColor: current ? severityColor(current.cpuUsagePercent) : '' }"></div>
          </div>
          <div v-if="current" class="text-[10px] text-base-content/30 tabular-nums">
            Load {{ current.loadAvg_1m.toFixed(2) }} · {{ current.loadAvg_5m.toFixed(2) }} · {{ current.loadAvg_15m.toFixed(2) }}
          </div>
        </div>
        <!-- Memory -->
        <div class="bg-base-200 rounded-xl p-4 flex flex-col items-center gap-1.5">
          <div class="text-lg font-bold font-mono tabular-nums flex items-center min-h-[1.75rem]"
            :style="current ? { color: severityColor(memPercent) } : {}">
            <span v-if="!current" class="loading loading-spinner loading-xs text-base-content/20"></span>
            <template v-else>{{ memPercent.toFixed(1) }}%</template>
          </div>
          <div class="text-xs text-base-content/40 uppercase tracking-wider">{{ $t('metrics.memory') }}</div>
          <div class="w-full h-1.5 rounded-full bg-base-300 overflow-hidden mt-1">
            <div class="h-full rounded-full transition-all duration-500"
              :style="{ width: (current ? memPercent : 0) + '%', backgroundColor: current ? severityColor(memPercent) : '' }"></div>
          </div>
          <div v-if="current" class="text-[10px] text-base-content/30 tabular-nums">{{ formatBytes(current.memoryUsedBytes) }} / {{ formatBytes(current.memoryTotalBytes) }}</div>
        </div>
        <!-- Disk -->
        <div class="bg-base-200 rounded-xl p-4 flex flex-col items-center gap-1.5">
          <div class="text-lg font-bold font-mono tabular-nums flex items-center min-h-[1.75rem]"
            :style="current ? { color: severityColor(diskPercent) } : {}">
            <span v-if="!current" class="loading loading-spinner loading-xs text-base-content/20"></span>
            <template v-else>{{ diskPercent.toFixed(1) }}%</template>
          </div>
          <div class="text-xs text-base-content/40 uppercase tracking-wider">{{ $t('metrics.disk') }}</div>
          <div class="w-full h-1.5 rounded-full bg-base-300 overflow-hidden mt-1">
            <div class="h-full rounded-full transition-all duration-500"
              :style="{ width: (current ? diskPercent : 0) + '%', backgroundColor: current ? severityColor(diskPercent) : '' }"></div>
          </div>
          <div v-if="current" class="text-[10px] text-base-content/30 tabular-nums">{{ formatBytes(current.diskUsedBytes) }} / {{ formatBytes(current.diskTotalBytes) }}</div>
        </div>
        <!-- Indexed Files -->
        <div class="bg-base-200 rounded-xl p-4 flex flex-col items-center gap-1.5">
          <div class="text-lg font-bold font-mono tabular-nums flex items-center min-h-[1.75rem] text-base-content/60">
            <span v-if="!current" class="loading loading-spinner loading-xs text-base-content/20"></span>
            <template v-else>{{ (current.indexedFiles ?? 0).toLocaleString() }}</template>
          </div>
          <div class="text-xs text-base-content/40 uppercase tracking-wider">{{ $t('metrics.indexedFiles') }}</div>
          <div v-if="current && current.dbSizeBytes" class="text-[10px] text-base-content/30 tabular-nums">
            DB {{ formatBytes(current.dbSizeBytes) }}
            <template v-if="current.dbWalSizeBytes !== undefined"> · WAL {{ formatBytes(current.dbWalSizeBytes) }}</template>
          </div>
        </div>
      </div>

      <!-- History charts (single column) -->
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <div class="text-xs text-base-content/40 uppercase tracking-wider">{{ $t('metrics.history') }}</div>
          <div class="flex gap-1">
            <button v-for="r in rangeOptions" :key="r.value"
              @click="rangeMinutes = r.value; loadHistory()"
              class="px-2.5 py-1 rounded-md text-xs font-medium transition-colors"
              :class="rangeMinutes === r.value ? 'bg-base-300 text-base-content' : 'text-base-content/30 hover:text-base-content/60 hover:bg-base-200'"
            >{{ r.label }}</button>
          </div>
        </div>

        <div class="bg-base-200 rounded-xl p-4">
          <div class="text-xs text-base-content/40 mb-2">CPU %</div>
          <MiniChart :data="cpuData" :min="0" :max="100" unit="%" color="#3b82f6" :height="160" :range-minutes="rangeMinutes" />
        </div>

        <div class="bg-base-200 rounded-xl p-4">
          <div class="text-xs text-base-content/40 mb-2">{{ $t('metrics.memory') }}</div>
          <MiniChart :data="memoryData" :min="0" :max="memoryMax" unit="GB" color="#8b5cf6" :height="160" :range-minutes="rangeMinutes" />
        </div>

        <div class="bg-base-200 rounded-xl p-4">
          <div class="text-xs text-base-content/40 mb-2">{{ $t('metrics.disk') }}</div>
          <MiniChart :data="diskData" :min="0" :max="diskMax" unit="GB" color="#06b6d4" :height="160" :range-minutes="rangeMinutes" />
        </div>

        <div class="bg-base-200 rounded-xl p-4">
          <div class="text-xs text-base-content/40 mb-2">Load (1m)</div>
          <MiniChart :data="loadData" :min="0" color="#f59e0b" :height="160" :range-minutes="rangeMinutes" />
        </div>
      </div>

      <!-- Disk details -->
      <div v-if="disks.length" class="space-y-3">
        <div class="text-xs text-base-content/40 uppercase tracking-wider">{{ $t('metrics.diskDetails') }}</div>
        <div v-for="d in disks" :key="d.mountPoint" class="bg-base-200 rounded-xl p-4">
          <div class="flex justify-between text-sm mb-2">
            <span class="font-medium font-mono truncate">{{ d.mountPoint }}</span>
            <span class="text-base-content/30 text-xs">{{ d.filesystem }}</span>
          </div>
          <progress class="progress w-full" :value="d.usedBytes" :max="d.totalBytes"></progress>
          <div class="flex justify-between text-xs text-base-content/40 mt-1">
            <span>{{ formatBytes(d.usedBytes) }} {{ $t('metrics.used') }}</span>
            <span>{{ formatBytes(d.availableBytes) }} {{ $t('metrics.available') }}</span>
          </div>
        </div>
      </div>
    </div>
  </AppLayout>
</template>

<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import AppLayout from '../components/layout/AppLayout.vue'
import MiniChart from '../components/metrics/MiniChart.vue'
import * as metricsApi from '../api/metrics'

const current = ref(null)
const snapshots = ref([])
const disks = ref([])
const systemInfo = ref(null)
const rangeMinutes = ref(60)
let pollTimer = null
let historyTimer = null

const memPercent = computed(() => {
  if (!current.value || !current.value.memoryTotalBytes) return 0
  return (current.value.memoryUsedBytes / current.value.memoryTotalBytes) * 100
})
const diskPercent = computed(() => {
  if (!current.value || !current.value.diskTotalBytes) return 0
  return (current.value.diskUsedBytes / current.value.diskTotalBytes) * 100
})

function toTs(s) { return new Date(s.timestamp).getTime() }

const cpuData = computed(() => snapshots.value.map(s => ({ t: toTs(s), v: s.cpuUsagePercent })))
const memoryData = computed(() => snapshots.value.map(s => ({ t: toTs(s), v: s.memoryUsedBytes })))
const memoryMax = computed(() => current.value?.memoryTotalBytes || 1)
const diskData = computed(() => snapshots.value.map(s => ({ t: toTs(s), v: s.diskUsedBytes })))
const diskMax = computed(() => current.value?.diskTotalBytes || 1)
const loadData = computed(() => snapshots.value.map(s => ({ t: toTs(s), v: s.loadAvg_1m })))

const rangeOptions = [
  { value: 5, label: '5m' },
  { value: 30, label: '30m' },
  { value: 60, label: '1h' },
  { value: 360, label: '6h' },
  { value: 1440, label: '24h' },
]

async function loadCurrent() {
  try {
    const { data } = await metricsApi.getCurrent()
    // Skip if server hasn't collected first snapshot yet
    if (data && data.timestamp) current.value = data
  } catch {}
}

async function loadHistory() {
  try {
    const { data } = await metricsApi.getHistory(rangeMinutes.value)
    snapshots.value = data.snapshots || []
  } catch {}
}

async function loadDisks() {
  try {
    const { data } = await metricsApi.getDiskDetails()
    disks.value = data.disks || []
  } catch {}
}

async function loadSystemInfo() {
  try {
    const { data } = await metricsApi.getSystemInfo()
    systemInfo.value = data
  } catch {}
}

// Severity color: green → amber → red based on percentage
function severityColor(percent) {
  if (percent < 50) return '#22c55e'  // green
  if (percent < 80) return '#f59e0b'  // amber
  return '#ef4444'                     // red
}

function formatBytes(bytes) {
  if (!bytes) return '0 B'
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
  return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB'
}

function formatUptime(seconds) {
  if (!seconds) return '0s'
  const d = Math.floor(seconds / 86400)
  const h = Math.floor((seconds % 86400) / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

onMounted(async () => {
  await Promise.all([loadCurrent(), loadHistory(), loadDisks(), loadSystemInfo()])
  pollTimer = setInterval(loadCurrent, 5000)
  historyTimer = setInterval(loadHistory, 30000)
})

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer)
  if (historyTimer) clearInterval(historyTimer)
})
</script>
