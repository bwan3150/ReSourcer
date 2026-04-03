<template>
  <div class="space-y-3">
    <!-- Current source -->
    <div v-if="current" class="flex items-center gap-2 p-3 bg-primary/10 rounded-lg">
      <span class="badge badge-primary badge-sm">{{ $t('settings.currentSource') }}</span>
      <span class="text-sm truncate flex-1">{{ current }}</span>
    </div>

    <!-- Backup sources -->
    <div v-for="backup in backups" :key="backup" class="flex items-center gap-2 p-3 bg-base-200 rounded-lg">
      <span class="text-sm truncate flex-1">{{ backup }}</span>
      <button class="btn btn-ghost btn-xs" @click="$emit('switch', backup)">{{ $t('settings.switchSource') }}</button>
      <button class="btn btn-ghost btn-xs text-error" @click="$emit('remove', backup)">{{ $t('settings.removeSource') }}</button>
    </div>

    <!-- Add button -->
    <button class="btn btn-outline btn-sm" @click="$emit('browse')">
      + {{ $t('settings.addSource') }}
    </button>
  </div>
</template>

<script setup>
defineProps({
  current: { type: String, default: '' },
  backups: { type: Array, default: () => [] },
})

defineEmits(['switch', 'remove', 'browse'])
</script>
