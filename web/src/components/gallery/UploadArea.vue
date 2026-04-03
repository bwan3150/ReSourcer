<template>
  <div>
    <input ref="fileInput" type="file" multiple class="hidden" @change="onFileSelect" />
    <button class="btn btn-primary btn-sm gap-1" @click="fileInput?.click()" :disabled="uploading">
      <span v-if="uploading" class="loading loading-spinner loading-xs"></span>
      {{ $t('gallery.uploadFiles') }}
    </button>

    <!-- Upload progress -->
    <div v-if="tasks.length" class="mt-3 space-y-2">
      <div v-for="task in tasks" :key="task.id" class="flex items-center gap-2 text-sm">
        <span class="truncate flex-1">{{ task.fileName }}</span>
        <progress class="progress progress-primary w-24" :value="task.progress" max="100"></progress>
        <span class="text-xs w-10 text-right">{{ Math.round(task.progress) }}%</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { uploadFiles, getActiveTasks } from '../../api/upload'

const props = defineProps({
  targetFolder: { type: String, required: true },
})

const emit = defineEmits(['uploaded'])
const fileInput = ref(null)
const uploading = ref(false)
const tasks = ref([])

async function onFileSelect(e) {
  const files = Array.from(e.target.files)
  if (!files.length) return

  uploading.value = true
  try {
    await uploadFiles(props.targetFolder, files, (e) => {
      if (e.total) {
        tasks.value = [{ id: 'upload', fileName: `${files.length} files`, progress: (e.loaded / e.total) * 100 }]
      }
    })
    emit('uploaded')
  } catch (err) {
    console.error('Upload failed:', err)
  } finally {
    uploading.value = false
    tasks.value = []
    if (fileInput.value) fileInput.value.value = ''
  }
}
</script>
