<template>
  <div class="card bg-base-100 shadow-sm">
    <div class="card-body p-3">
      <div class="flex items-start gap-3">
        <!-- Platform badge -->
        <div class="badge badge-outline shrink-0">{{ task.platform }}</div>

        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium truncate">{{ task.fileName || task.url }}</p>

          <div v-if="isActive" class="mt-2">
            <progress class="progress progress-primary w-full" :value="task.progress" max="100"></progress>
            <div class="flex justify-between text-xs text-base-content/50 mt-1">
              <span>{{ Math.round(task.progress || 0) }}%</span>
              <span v-if="task.speed">{{ task.speed }}</span>
              <span v-if="task.eta">{{ $t('downloader.eta') }}: {{ task.eta }}</span>
            </div>
          </div>

          <div v-else class="mt-1">
            <span class="badge badge-sm" :class="statusClass">{{ statusLabel }}</span>
            <span v-if="task.error" class="text-xs text-error ml-2">{{ task.error }}</span>
          </div>
        </div>

        <div class="shrink-0">
          <button v-if="isActive" class="btn btn-ghost btn-xs btn-square text-error" @click="$emit('cancel', task.id)">
            <X :size="16" />
          </button>
          <button v-else class="btn btn-ghost btn-xs btn-square" @click="$emit('delete', task.id)">
            <Trash2 :size="16" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { X, Trash2 } from 'lucide-vue-next'

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
