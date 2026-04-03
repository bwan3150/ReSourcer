<template>
  <dialog ref="dialogEl" class="modal" @close="emit('cancel')">
    <div class="modal-box">
      <h3 class="font-bold text-lg">{{ title }}</h3>
      <p class="py-4">{{ message }}</p>
      <div class="modal-action">
        <button class="btn" @click="cancel">{{ $t('common.cancel') }}</button>
        <button class="btn btn-error" @click="confirm">{{ $t('common.confirm') }}</button>
      </div>
    </div>
    <form method="dialog" class="modal-backdrop"><button>close</button></form>
  </dialog>
</template>

<script setup>
import { ref } from 'vue'

defineProps({
  title: { type: String, default: '' },
  message: { type: String, default: '' },
})

const emit = defineEmits(['confirm', 'cancel'])
const dialogEl = ref(null)

function show() {
  dialogEl.value?.showModal()
}
function close() {
  dialogEl.value?.close()
}
function confirm() {
  emit('confirm')
  close()
}
function cancel() {
  emit('cancel')
  close()
}

defineExpose({ show, close })
</script>
