<template>
  <div class="relative h-full">
    <!-- Grid content -->
    <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-3 p-4">
      <FileCard v-for="file in files" :key="file.uuid" :file="file" @click="$emit('preview', file)" />
    </div>

    <!-- Bottom: load more spinner (pagination) -->
    <div v-if="loadingMore" class="flex justify-center py-6">
      <span class="loading loading-dots loading-sm"></span>
    </div>

    <!-- Bottom: auto-load trigger -->
    <div v-if="hasMore && !loadingMore" ref="loadTrigger" class="h-1"></div>

    <!-- Empty state (only when truly done loading) -->
    <div v-if="!loading && !loadingMore && !files.length" class="absolute inset-0 flex items-center justify-center text-base-content/30 text-sm">
      {{ $t('gallery.noFiles') }}
    </div>

    <!-- Center overlay spinner (folder switch) — always centered via absolute inset-0 -->
    <transition name="fade">
      <div v-if="showSpinner" class="absolute inset-0 flex items-center justify-center z-10 pointer-events-none">
        <span class="loading loading-dots loading-lg"></span>
      </div>
    </transition>
  </div>
</template>

<script setup>
import { ref, watch, onMounted, onUnmounted } from 'vue'
import FileCard from './FileCard.vue'

const props = defineProps({
  files: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  loadingMore: { type: Boolean, default: false },
  hasMore: { type: Boolean, default: false },
})

const emit = defineEmits(['preview', 'loadMore'])
const loadTrigger = ref(null)
let observer = null

// Spinner with minimum display time (300ms) so it's visible
const showSpinner = ref(false)
let spinnerTimer = null

watch(() => props.loading, (val) => {
  if (val) {
    showSpinner.value = true
    clearTimeout(spinnerTimer)
  } else {
    // Keep spinner visible for at least 300ms
    spinnerTimer = setTimeout(() => {
      showSpinner.value = false
    }, 300)
  }
})

function setupObserver() {
  if (observer) observer.disconnect()
  if (!loadTrigger.value) return
  observer = new IntersectionObserver((entries) => {
    if (entries[0].isIntersecting && props.hasMore && !props.loadingMore) {
      emit('loadMore')
    }
  }, { threshold: 0 })
  observer.observe(loadTrigger.value)
}

watch(() => [loadTrigger.value, props.hasMore], () => {
  setupObserver()
}, { flush: 'post' })

onMounted(setupObserver)
onUnmounted(() => {
  observer?.disconnect()
  clearTimeout(spinnerTimer)
})
</script>

<style scoped>
.fade-enter-active { transition: opacity 0.15s ease-in; }
.fade-leave-active { transition: opacity 0.3s ease-out; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
