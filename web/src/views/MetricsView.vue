<template>
  <AppLayout>
    <template #header>
      <h1 class="text-lg font-bold flex-1">{{ $t('metrics.title') }}</h1>
      <select v-model="rangeMinutes" class="select select-sm select-bordered w-28" @change="loadHistory">
        <option :value="5">5 min</option>
        <option :value="30">30 min</option>
        <option :value="60">1 h</option>
        <option :value="360">6 h</option>
        <option :value="1440">24 h</option>
      </select>
    </template>

    <div class="p-4 space-y-4 max-w-5xl mx-auto">
      <!-- Current stats row -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div class="bg-base-200 rounded-lg p-3">
          <div class="text-xs text-base-content/40">CPU</div>
          <div class="text-2xl font-bold tabular-nums">{{ current ? current.cpuUsagePercent.toFixed(1) + '%' : '—' }}</div>
        </div>
        <div class="bg-base-200 rounded-lg p-3">
          <div class="text-xs text-base-content/40">{{ $t('metrics.memory') }}</div>
          <div class="text-2xl font-bold tabular-nums">{{ current ? formatBytes(current.memoryUsedBytes) : '—' }}</div>
          <div class="text-xs text-base-content/30">/ {{ current ? formatBytes(current.memoryTotalBytes) : '—' }}</div>
        </div>
        <div class="bg-base-200 rounded-lg p-3">
          <div class="text-xs text-base-content/40">{{ $t('metrics.disk') }}</div>
          <div class="text-2xl font-bold tabular-nums">{{ current ? formatBytes(current.diskUsedBytes) : '—' }}</div>
          <div class="text-xs text-base-content/30">/ {{ current ? formatBytes(current.diskTotalBytes) : '—' }}</div>
        </div>
        <div class="bg-base-200 rounded-lg p-3">
          <div class="text-xs text-base-content/40">{{ $t('metrics.uptime') }}</div>
          <div class="text-2xl font-bold tabular-nums">{{ current ? formatUptime(current.uptimeSeconds) : '—' }}</div>
        </div>
      </div>

      <!-- Load averages -->
      <div v-if="current" class="flex gap-4 text-sm text-base-content/50">
        <span>Load: {{ current.loadAvg1m.toFixed(2) }} / {{ current.loadAvg5m.toFixed(2) }} / {{ current.loadAvg15m.toFixed(2) }}</span>
        <span>{{ $t('metrics.processMemory') }}: {{ formatBytes(current.processMemoryBytes) }}</span>
      </div>

      <!-- Charts -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="bg-base-200 rounded-lg p-3">
          <div class="text-xs text-base-content/40 mb-1">CPU %</div>
          <MiniChart :data="cpuData" :min="0" :max="100" unit="%" color="#666" :height="140" />
        </div>
        <div class="bg-base-200 rounded-lg p-3">
          <div class="text-xs text-base-content/40 mb-1">{{ $t('metrics.memory') }}</div>
          <MiniChart :data="memoryData" :min="0" :max="memoryMax" unit="GB" color="#888" :height="140" />
        </div>
        <div class="bg-base-200 rounded-lg p-3">
          <div class="text-xs text-base-content/40 mb-1">{{ $t('metrics.disk') }}</div>
          <MiniChart :data="diskData" :min="0" :max="diskMax" unit="GB" color="#aaa" :height="140" />
        </div>
        <div class="bg-base-200 rounded-lg p-3">
          <div class="text-xs text-base-content/40 mb-1">Load (1m)</div>
          <MiniChart :data="loadData" :min="0" color="#999" :height="140" />
        </div>
      </div>

      <!-- Disk details -->
      <div v-if="disks.length" class="space-y-2">
        <div class="text-sm font-medium text-base-content/50">{{ $t('metrics.diskDetails') }}</div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div v-for="d in disks" :key="d.mountPoint" class="bg-base-200 rounded-lg p-3">
            <div class="flex justify-between text-sm mb-1">
              <span class="font-medium truncate">{{ d.mountPoint }}</span>
              <span class="text-base-content/40 text-xs">{{ d.filesystem }}</span>
            </div>
            <progress
              class="progress w-full"
              :value="d.usedBytes"
              :max="d.totalBytes"
            ></progress>
            <div class="flex justify-between text-xs text-base-content/40 mt-1">
              <span>{{ formatBytes(d.usedBytes) }} {{ $t('metrics.used') }}</span>
              <span>{{ formatBytes(d.availableBytes) }} {{ $t('metrics.available') }}</span>
            </div>
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
const rangeMinutes = ref(60)
let pollTimer = null
let historyTimer = null

const cpuData = computed(() => snapshots.value.map(s => s.cpuUsagePercent))
const memoryData = computed(() => snapshots.value.map(s => s.memoryUsedBytes))
const memoryMax = computed(() => current.value?.memoryTotalBytes || 1)
const diskData = computed(() => snapshots.value.map(s => s.diskUsedBytes))
const diskMax = computed(() => current.value?.diskTotalBytes || 1)
const loadData = computed(() => snapshots.value.map(s => s.loadAvg1m))

async function loadCurrent() {
  try {
    const { data } = await metricsApi.getCurrent()
    if (data.cpuUsagePercent !== undefined) current.value = data
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
  await Promise.all([loadCurrent(), loadHistory(), loadDisks()])
  // Poll current every 10s, history every 30s
  pollTimer = setInterval(async () => {
    await loadCurrent()
  }, 10000)
  historyTimer = setInterval(loadHistory, 30000)
})

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer)
  if (historyTimer) clearInterval(historyTimer)
})
</script>
