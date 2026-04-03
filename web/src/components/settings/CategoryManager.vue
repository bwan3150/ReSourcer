<template>
  <div class="space-y-1">
    <div
      v-for="folder in folders"
      :key="folder.name"
      class="flex items-center gap-2 p-2 bg-base-200 rounded"
    >
      <span class="text-sm flex-1 truncate">{{ folder.name }}</span>
      <span class="badge badge-sm badge-ghost">{{ folder.fileCount }}</span>
      <button
        class="btn btn-ghost btn-xs"
        @click="$emit('toggle', folder)"
      >
        {{ folder.hidden ? $t('settings.showFolder') : $t('settings.hideFolder') }}
      </button>
    </div>
    <div v-if="!folders.length" class="text-sm text-base-content/50 py-3 text-center">
      {{ $t('settings.noFolders') }}
    </div>
  </div>
</template>

<script setup>
defineProps({
  folders: { type: Array, default: () => [] },
})

defineEmits(['toggle'])
</script>
