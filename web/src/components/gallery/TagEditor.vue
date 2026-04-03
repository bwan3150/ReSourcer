<template>
  <div>
    <!-- All tags as toggleable chips -->
    <div class="flex flex-wrap gap-1.5">
      <button
        v-for="tag in allTags"
        :key="tag.id"
        class="badge badge-sm cursor-pointer transition-all"
        :class="isSelected(tag.id) ? 'badge-outline border-2' : 'opacity-40'"
        :style="tagStyle(tag, isSelected(tag.id))"
        @click="toggleTag(tag.id)"
      >
        {{ tag.name }}
      </button>

      <!-- Add new tag button -->
      <button class="badge badge-sm badge-ghost cursor-pointer gap-0.5" @click="showCreateDialog">
        <Plus :size="12" />
      </button>
    </div>

    <!-- Create tag dialog -->
    <dialog ref="createDialog" class="modal">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">{{ $t('gallery.addTag') }}</h3>
        <div class="space-y-3">
          <input
            v-model="newTagName"
            type="text"
            :placeholder="$t('gallery.tagName')"
            class="input input-bordered w-full"
            @keyup.enter="createTag"
          />
          <div>
            <label class="text-xs text-base-content/50 mb-1.5 block">{{ $t('gallery.tagColor') }}</label>
            <div class="flex gap-2">
              <button
                v-for="c in colors"
                :key="c"
                class="w-7 h-7 rounded-full cursor-pointer border-2 transition-all"
                :class="newTagColor === c ? 'border-base-content scale-110' : 'border-transparent'"
                :style="{ backgroundColor: c }"
                @click="newTagColor = c"
              ></button>
            </div>
          </div>
        </div>
        <div class="modal-action">
          <button class="btn" @click="createDialog?.close()">{{ $t('common.cancel') }}</button>
          <button class="btn btn-neutral" @click="createTag" :disabled="!newTagName.trim()">{{ $t('common.confirm') }}</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { Plus } from 'lucide-vue-next'

const props = defineProps({
  fileTags: { type: Array, default: () => [] },
  allTags: { type: Array, default: () => [] },
})

const emit = defineEmits(['update', 'create'])

const createDialog = ref(null)
const newTagName = ref('')
const newTagColor = ref('#6b7280')

const colors = [
  '#6b7280', '#ef4444', '#f97316', '#eab308',
  '#22c55e', '#14b8a6', '#3b82f6', '#8b5cf6',
  '#ec4899', '#78716c',
]

function isSelected(tagId) {
  return props.fileTags.some(t => t.id === tagId)
}

function tagStyle(tag, selected) {
  if (selected) {
    return { backgroundColor: tag.color, color: '#fff', borderColor: tag.color }
  }
  return { borderColor: tag.color, color: tag.color }
}

function toggleTag(tagId) {
  let ids
  if (isSelected(tagId)) {
    ids = props.fileTags.filter(t => t.id !== tagId).map(t => t.id)
  } else {
    ids = [...props.fileTags.map(t => t.id), tagId]
  }
  emit('update', ids)
}

function showCreateDialog() {
  newTagName.value = ''
  newTagColor.value = '#6b7280'
  createDialog.value?.showModal()
}

function createTag() {
  if (!newTagName.value.trim()) return
  emit('create', { name: newTagName.value.trim(), color: newTagColor.value })
  createDialog.value?.close()
}
</script>
