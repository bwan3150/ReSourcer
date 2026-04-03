<template>
  <div class="space-y-2">
    <div v-if="!tasks.length" class="text-center py-8 text-base-content/50">
      {{ emptyText }}
    </div>
    <TaskCard
      v-for="task in tasks"
      :key="task.id"
      :task="task"
      @cancel="$emit('cancel', $event)"
      @delete="$emit('delete', $event)"
    />
    <div v-if="hasMore" class="flex justify-center pt-2">
      <button class="btn btn-ghost btn-sm" @click="$emit('loadMore')">{{ $t('common.loadMore') }}</button>
    </div>
  </div>
</template>

<script setup>
import TaskCard from './TaskCard.vue'

defineProps({
  tasks: { type: Array, default: () => [] },
  emptyText: { type: String, default: '' },
  hasMore: { type: Boolean, default: false },
})

defineEmits(['cancel', 'delete', 'loadMore'])
</script>
