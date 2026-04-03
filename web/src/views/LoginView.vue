<template>
  <div class="min-h-screen flex items-center justify-center bg-base-200">
    <div class="w-80">
      <!-- Card with overlapping logo -->
      <div class="relative pt-8">
        <!-- Logo — overlaps card top -->
        <div class="absolute left-1/2 -translate-x-1/2 -top-0 z-10">
          <div class="w-16 h-16 rounded-2xl bg-white text-black flex items-center justify-center text-2xl font-bold shadow-lg border border-base-300">
            Re
          </div>
        </div>

        <div class="card bg-base-100 shadow-xl pt-12">
          <div class="card-body gap-4">
            <!-- Server address -->
            <div class="form-control">
              <label class="label pb-1"><span class="label-text text-xs">{{ $t('login.serverLabel') }}</span></label>
              <div class="flex gap-1.5">
                <button class="btn btn-xs flex-1" :class="serverMode === 'local' ? 'btn-neutral' : 'btn-ghost'" @click="serverMode = 'local'; onServerModeChange()">
                  {{ $t('login.localServer') }}
                </button>
                <button class="btn btn-xs flex-1" :class="serverMode === 'custom' ? 'btn-neutral' : 'btn-ghost'" @click="serverMode = 'custom'">
                  {{ $t('login.customServer') }}
                </button>
              </div>
            <input
              v-if="serverMode === 'custom'"
              v-model="customUrl"
              type="text"
              :placeholder="$t('login.serverPlaceholder')"
              class="input input-bordered input-sm w-full mt-2"
            />
          </div>

          <!-- API Key -->
          <div class="form-control">
            <label class="label pb-1"><span class="label-text text-xs">{{ $t('login.apiKeyLabel') }}</span></label>
            <input
              v-model="key"
              type="text"
              :placeholder="$t('login.apiKeyPlaceholder')"
              class="input input-bordered input-sm w-full"
              @keyup.enter="login"
              :disabled="verifying"
            />
          </div>

          <!-- Error -->
          <div v-if="error" class="text-error text-xs">{{ error }}</div>

          <!-- Login button -->
          <button class="btn btn-neutral w-full" @click="login" :disabled="verifying || !key.trim()">
            <span v-if="verifying" class="loading loading-spinner loading-sm"></span>
            {{ verifying ? $t('login.verifying') : $t('login.loginBtn') }}
          </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { setApiKey } from '../composables/useAuth'
import { setServerUrl } from '../composables/useServer'
import { verifyApiKey } from '../api/auth'

const { t } = useI18n()
const router = useRouter()
const route = useRoute()

const key = ref('')
const verifying = ref(false)
const error = ref('')
const serverMode = ref(localStorage.getItem('server_url') ? 'custom' : 'local')
const customUrl = ref(localStorage.getItem('server_url') || '')

function onServerModeChange() {
  if (serverMode.value === 'local') {
    customUrl.value = ''
  }
}

function applyServerUrl() {
  if (serverMode.value === 'custom' && customUrl.value.trim()) {
    setServerUrl(customUrl.value.trim())
  } else {
    setServerUrl('')
  }
}

async function login() {
  if (!key.value.trim() || verifying.value) return
  verifying.value = true
  error.value = ''
  applyServerUrl()
  try {
    const { data } = await verifyApiKey(key.value.trim())
    if (data.valid) {
      setApiKey(key.value.trim())
      router.push('/')
    } else {
      error.value = t('login.invalidKey')
    }
  } catch {
    error.value = t('login.networkError')
  } finally {
    verifying.value = false
  }
}

onMounted(() => {
  // Auto-login from URL params
  const urlKey = route.query.key
  const urlServer = route.query.server
  if (urlServer) {
    serverMode.value = 'custom'
    customUrl.value = urlServer
  }
  if (urlKey) {
    key.value = urlKey
    login()
  }
})
</script>
