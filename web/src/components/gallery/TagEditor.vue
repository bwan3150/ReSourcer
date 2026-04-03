<template>
  <div>
    <div class="flex flex-wrap gap-1 mb-2">
      <span
        v-for="tag in fileTags"
        :key="tag.id"
        class="badge gap-1 cursor-pointer"
        :style="{ backgroundColor: tag.color, color: '#fff' }"
        @click="removeTag(tag.id)"
      >
        {{ tag.name }}
        <X :size="12" />
      </span>
      <span v-if="!fileTags.length" class="text-xs text-base-content/40">{{ $t('gallery.tags') }}</span>
    </div>
    <div class="dropdown dropdown-end">
      <label tabindex="0" class="btn btn-ghost btn-xs gap-1">
        <Plus :size="14" /> {{ $t('gallery.addTag') }}
      </label>
      <ul tabindex="0" class="dropdown-content menu menu-sm bg-base-200 rounded-box shadow w-48 max-h-60 overflow-y-auto z-50">
        <li v-for="tag in availableTags" :key="tag.id">
          <a @click="addTag(tag.id)" class="flex items-center gap-2">
            <span class="w-3 h-3 rounded-full" :style="{ backgroundColor: tag.color }"></span>
            {{ tag.name }}
          </a>
        </li>
        <li v-if="!availableTags.length"><span class="text-xs text-base-content/50">{{ $t('common.noData') }}</span></li>
      </ul>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { X, Plus } from 'lucide-vue-next'

const props = defineProps({
  fileTags: { type: Array, default: () => [] },
  allTags: { type: Array, default: () => [] },
})

const emit = defineEmits(['update'])

const availableTags = computed(() =>
  props.allTags.filter(t => !props.fileTags.some(ft => ft.id === t.id))
)

function addTag(tagId) {
  const ids = [...props.fileTags.map(t => t.id), tagId]
  emit('update', ids)
}

function removeTag(tagId) {
  const ids = props.fileTags.filter(t => t.id !== tagId).map(t => t.id)
  emit('update', ids)
}
</script>
