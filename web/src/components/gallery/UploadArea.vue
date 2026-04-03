<template>
  <div>
    <input ref="fileInput" type="file" multiple class="hidden" @change="onFileSelect" />
    <button class="btn btn-neutral btn-sm gap-1" @click="fileInput?.click()" :disabled="uploading">
      <span v-if="uploading" class="loading loading-spinner loading-xs"></span>
      <Upload v-else :size="16" />
      {{ $t('common.upload') }}
    </button>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { Upload } from 'lucide-vue-next'
import { uploadFiles } from '../../api/upload'

const props = defineProps({
  targetFolder: { type: String, required: true },
})

const emit = defineEmits(['uploaded'])
const fileInput = ref(null)
const uploading = ref(false)

async function doUpload(fileList) {
  const files = Array.from(fileList)
  if (!files.length) return
  uploading.value = true
  try {
    await uploadFiles(props.targetFolder, files)
    emit('uploaded')
  } catch (err) {
    console.error('Upload failed:', err)
  } finally {
    uploading.value = false
    if (fileInput.value) fileInput.value.value = ''
  }
}

async function onFileSelect(e) {
  await doUpload(e.target.files)
}

defineExpose({ doUpload, uploading })
</script>
