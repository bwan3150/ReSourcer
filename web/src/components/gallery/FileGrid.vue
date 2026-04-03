<template>
  <div>
    <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-3 p-4">
      <FileCard v-for="file in files" :key="file.uuid" :file="file" @click="$emit('preview', file)" />
    </div>

    <div v-if="loading" class="flex justify-center p-6">
      <span class="loading loading-spinner loading-md"></span>
    </div>

    <div v-if="!loading && !files.length" class="text-center py-16 text-base-content/50">
      {{ $t('gallery.noFiles') }}
    </div>

    <div v-if="hasMore && !loading" class="flex justify-center p-4">
      <button class="btn btn-outline btn-sm" @click="$emit('loadMore')">
        {{ $t('common.loadMore') }}
      </button>
    </div>
  </div>
</template>

<script setup>
import FileCard from './FileCard.vue'

defineProps({
  files: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  hasMore: { type: Boolean, default: false },
})

defineEmits(['preview', 'loadMore'])
</script>
