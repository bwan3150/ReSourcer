<template>
  <div class="space-y-3">
    <!-- Current source -->
    <div v-if="current" class="flex items-center gap-2 p-3 bg-base-300 rounded-lg">
      <span class="badge badge-outline badge-sm">{{ $t('settings.currentSource') }}</span>
      <span class="text-sm truncate flex-1">{{ current }}</span>
    </div>

    <!-- Backup sources -->
    <div v-for="backup in backups" :key="backup" class="flex items-center gap-2 p-3 bg-base-200 rounded-lg">
      <span class="text-sm truncate flex-1">{{ backup }}</span>
      <button class="btn btn-ghost btn-xs" @click="$emit('switch', backup)">{{ $t('settings.switchSource') }}</button>
      <button class="btn btn-ghost btn-xs text-error" @click="$emit('remove', backup)">{{ $t('settings.removeSource') }}</button>
    </div>

    <!-- Actions -->
    <div class="flex gap-2">
      <button class="btn btn-outline btn-sm" @click="$emit('browse')">
        + {{ $t('settings.addSource') }}
      </button>
      <button class="btn btn-ghost btn-sm" @click="showMigrate = true">
        <ArrowRightLeft :size="14" />
        {{ $t('settings.migrate') }}
      </button>
    </div>

    <!-- Migrate form -->
    <div v-if="showMigrate" class="border border-base-300 rounded-lg p-3 space-y-2">
      <p class="text-xs text-base-content/50">{{ $t('settings.migrateDesc') }}</p>
      <input
        v-model="oldPath"
        type="text"
        :placeholder="$t('settings.migrateOld')"
        class="input input-bordered input-sm w-full font-mono"
      />
      <input
        v-model="newPath"
        type="text"
        :placeholder="$t('settings.migrateNew')"
        class="input input-bordered input-sm w-full font-mono"
      />
      <div class="flex gap-2">
        <button class="btn btn-neutral btn-sm" @click="doMigrate" :disabled="migrating || !oldPath.trim() || !newPath.trim()">
          <span v-if="migrating" class="loading loading-spinner loading-xs"></span>
          {{ $t('common.confirm') }}
        </button>
        <button class="btn btn-ghost btn-sm" @click="showMigrate = false">{{ $t('common.cancel') }}</button>
      </div>
      <div v-if="migrateResult" class="text-xs text-base-content/50">
        {{ migrateResult }}
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ArrowRightLeft } from 'lucide-vue-next'
import * as configApi from '../../api/config'

const { t } = useI18n()

defineProps({
  current: { type: String, default: '' },
  backups: { type: Array, default: () => [] },
})

const emit = defineEmits(['switch', 'remove', 'browse', 'migrated'])

const showMigrate = ref(false)
const oldPath = ref('')
const newPath = ref('')
const migrating = ref(false)
const migrateResult = ref('')

async function doMigrate() {
  migrating.value = true
  migrateResult.value = ''
  try {
    const { data } = await configApi.migrateSource(oldPath.value.trim(), newPath.value.trim())
    migrateResult.value = `${data.updatedRows} records updated`
    emit('migrated')
  } catch (e) {
    migrateResult.value = t('common.error')
  }
  migrating.value = false
}
</script>
