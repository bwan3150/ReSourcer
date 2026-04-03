<template>
  <AppLayout>
    <div class="p-6 max-w-5xl mx-auto">
      <h1 class="text-3xl font-bold mb-8">{{ $t('home.welcome') }}</h1>

      <!-- QR Code -->
      <div class="card bg-base-100 shadow mb-8">
        <div class="card-body items-center text-center">
          <h2 class="card-title mb-4">{{ $t('home.scanQr') }}</h2>
          <div class="bg-white p-4 rounded-lg">
            <canvas ref="qrCanvas"></canvas>
          </div>
          <p class="text-sm text-base-content/60 mt-2">{{ $t('home.webAccess') }}</p>
        </div>
      </div>

      <!-- Navigation Cards -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <router-link to="/gallery" class="card bg-base-100 shadow hover:shadow-lg transition-shadow cursor-pointer">
          <div class="card-body items-center text-center">
            <div class="text-4xl mb-2">🖼️</div>
            <h3 class="card-title">{{ $t('nav.gallery') }}</h3>
            <p class="text-sm text-base-content/60">{{ $t('home.galleryDesc') }}</p>
          </div>
        </router-link>
        <router-link to="/classifier" class="card bg-base-100 shadow hover:shadow-lg transition-shadow cursor-pointer">
          <div class="card-body items-center text-center">
            <div class="text-4xl mb-2">📂</div>
            <h3 class="card-title">{{ $t('nav.classifier') }}</h3>
            <p class="text-sm text-base-content/60">{{ $t('home.classifierDesc') }}</p>
          </div>
        </router-link>
        <router-link to="/downloader" class="card bg-base-100 shadow hover:shadow-lg transition-shadow cursor-pointer">
          <div class="card-body items-center text-center">
            <div class="text-4xl mb-2">⬇️</div>
            <h3 class="card-title">{{ $t('nav.downloader') }}</h3>
            <p class="text-sm text-base-content/60">{{ $t('home.downloaderDesc') }}</p>
          </div>
        </router-link>
        <router-link to="/settings" class="card bg-base-100 shadow hover:shadow-lg transition-shadow cursor-pointer">
          <div class="card-body items-center text-center">
            <div class="text-4xl mb-2">⚙️</div>
            <h3 class="card-title">{{ $t('nav.settings') }}</h3>
            <p class="text-sm text-base-content/60">{{ $t('home.settingsDesc') }}</p>
          </div>
        </router-link>
      </div>
    </div>
  </AppLayout>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import QRCode from 'qrcode'
import AppLayout from '../components/layout/AppLayout.vue'
import { getApiKey } from '../composables/useAuth'

const qrCanvas = ref(null)

onMounted(async () => {
  const url = `${window.location.origin}/login?key=${getApiKey()}`
  if (qrCanvas.value) {
    QRCode.toCanvas(qrCanvas.value, url, { width: 200, margin: 0 })
  }
})
</script>
