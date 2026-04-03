<template>
  <div>
    <p class="text-xs text-base-content/50 mb-2">{{ description }}</p>
    <div class="flex flex-wrap gap-2 mb-2">
      <span v-for="(item, i) in items" :key="i" class="badge badge-outline gap-1">
        {{ item }}
        <button class="text-error" @click="remove(i)"><X :size="12" /></button>
      </span>
    </div>
    <div class="flex gap-2">
      <input
        v-model="newItem"
        :placeholder="$t('settings.addItem')"
        class="input input-bordered input-sm flex-1"
        @keyup.enter="add"
      />
      <button class="btn btn-sm btn-ghost btn-square" @click="add" :disabled="!newItem.trim()">
        <Plus :size="16" />
      </button>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { X, Plus } from 'lucide-vue-next'

const props = defineProps({
  items: { type: Array, default: () => [] },
  description: { type: String, default: '' },
})

const emit = defineEmits(['update'])
const newItem = ref('')

function add() {
  if (!newItem.value.trim()) return
  const updated = [...props.items, newItem.value.trim()]
  emit('update', updated)
  newItem.value = ''
}

function remove(index) {
  const updated = props.items.filter((_, i) => i !== index)
  emit('update', updated)
}
</script>
