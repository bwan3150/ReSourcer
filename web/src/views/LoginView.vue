<template>
  <div class="min-h-screen flex items-center justify-center bg-base-200">
    <div class="card w-96 bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title justify-center text-2xl mb-4">{{ $t('login.title') }}</h2>
        <div class="form-control">
          <label class="label"><span class="label-text">{{ $t('login.apiKeyLabel') }}</span></label>
          <input
            v-model="key"
            type="text"
            :placeholder="$t('login.apiKeyPlaceholder')"
            class="input input-bordered w-full"
            @keyup.enter="login"
            :disabled="verifying"
          />
        </div>
        <div v-if="error" class="text-error text-sm mt-2">{{ error }}</div>
        <div class="card-actions mt-4">
          <button class="btn btn-primary w-full" @click="login" :disabled="verifying || !key.trim()">
            <span v-if="verifying" class="loading loading-spinner loading-sm"></span>
            {{ verifying ? $t('login.verifying') : $t('login.loginBtn') }}
          </button>
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
import { verifyApiKey } from '../api/auth'

const { t } = useI18n()
const router = useRouter()
const route = useRoute()
const key = ref('')
const verifying = ref(false)
const error = ref('')

async function login() {
  if (!key.value.trim() || verifying.value) return
  verifying.value = true
  error.value = ''
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
  const urlKey = route.query.key
  if (urlKey) {
    key.value = urlKey
    login()
  }
})
</script>
