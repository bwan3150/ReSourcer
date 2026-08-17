<template>
  <div>
    <input ref="fileInput" type="file" multiple class="hidden" @change="onFileSelect" />
    <button class="btn btn-neutral btn-sm gap-1" @click="fileInput?.click()" :disabled="uploading">
      <span v-if="uploading" class="loading loading-spinner loading-xs"></span>
      <Upload v-else :size="16" />
      <span v-if="uploading && progressText">{{ progressText }}</span>
      <span v-else>{{ $t('common.upload') }}</span>
    </button>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { Upload } from 'lucide-vue-next'
import { uploadFiles, getUploadPolicy, uploadFileChunked } from '../../api/upload'

const props = defineProps({
  targetFolder: { type: String, required: true },
})

const emit = defineEmits(['uploaded'])
const fileInput = ref(null)
const uploading = ref(false)
const progressText = ref('')

async function doUpload(fileList) {
  const files = Array.from(fileList)
  if (!files.length) return
  uploading.value = true
  progressText.value = ''
  try {
    // 查询服务器分片阈值；失败则回退为 0（全部走直传，兼容旧服务器）
    let chunkSize = 0
    try {
      const policy = await getUploadPolicy()
      chunkSize = policy.data?.chunkSize ?? 0
    } catch (_) {
      chunkSize = 0
    }

    // 按阈值拆分：小文件直传，大文件分片
    const smallFiles = []
    const largeFiles = []
    for (const f of files) {
      if (chunkSize > 0 && f.size > chunkSize) {
        largeFiles.push(f)
      } else {
        smallFiles.push(f)
      }
    }

    // 小文件批量直传（保持原逻辑）
    if (smallFiles.length) {
      await uploadFiles(props.targetFolder, smallFiles)
    }

    // 大文件逐个分片上传
    for (let i = 0; i < largeFiles.length; i++) {
      const f = largeFiles[i]
      await uploadFileChunked(props.targetFolder, f, {
        chunkSize,
        onProgress: ratio => {
          const pct = Math.round(ratio * 100)
          progressText.value = `${f.name.slice(0, 12)}… ${pct}%`
        },
      })
    }

    emit('uploaded')
  } catch (err) {
    console.error('Upload failed:', err)
  } finally {
    uploading.value = false
    progressText.value = ''
    if (fileInput.value) fileInput.value.value = ''
  }
}

async function onFileSelect(e) {
  await doUpload(e.target.files)
}

defineExpose({ doUpload, uploading })
</script>
