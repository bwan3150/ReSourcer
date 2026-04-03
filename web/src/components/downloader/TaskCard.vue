<template>
  <div class="card bg-base-100 shadow-sm">
    <div class="card-body p-3">
      <div class="flex items-start gap-3">
        <!-- Platform badge -->
        <div class="badge badge-outline shrink-0">{{ task.platform }}</div>

        <div class="flex-1 min-w-0">
          <!-- File name or URL -->
          <p class="text-sm font-medium truncate">{{ task.fileName || task.url }}</p>

          <!-- Progress bar for active tasks -->
          <div v-if="isActive" class="mt-2">
            <progress class="progress progress-primary w-full" :value="task.progress" max="100"></progress>
            <div class="flex justify-between text-xs text-base-content/50 mt-1">
              <span>{{ Math.round(task.progress || 0) }}%</span>
              <span v-if="task.speed">{{ task.speed }}</span>
              <span v-if="task.eta">{{ $t('downloader.eta') }}: {{ task.eta }}</span>
            </div>
          </div>

          <!-- Status badge for history -->
          <div v-else class="mt-1">
            <span class="badge badge-sm" :class="statusClass">{{ statusLabel }}</span>
            <span v-if="task.error" class="text-xs text-error ml-2">{{ task.error }}</span>
          </div>
        </div>

        <!-- Actions -->
        <div class="shrink-0">
          <button v-if="isActive" class="btn btn-ghost btn-xs text-error" @click="$emit('cancel', task.id)">✕</button>
          <button v-else class="btn btn-ghost btn-xs" @click="$emit('delete', task.id)">🗑</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
const props = defineProps({
  task: { type: Object, required: true },
})
defineEmits(['cancel', 'delete'])

const isActive = computed(() => ['pending', 'downloading'].includes(props.task.status))

const statusClass = computed(() => {
  switch (props.task.status) {
    case 'completed': return 'badge-success'
    case 'failed': return 'badge-error'
    case 'cancelled': return 'badge-warning'
    default: return 'badge-ghost'
  }
})

const statusLabel = computed(() => t(`downloader.${props.task.status}`))
</script>
