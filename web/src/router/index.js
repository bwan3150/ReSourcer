import { createRouter, createWebHistory } from 'vue-router'
import { getApiKey } from '../composables/useAuth'

const routes = [
  { path: '/login', name: 'login', component: () => import('../views/LoginView.vue') },
  { path: '/', redirect: '/gallery' },
  { path: '/gallery', name: 'gallery', component: () => import('../views/GalleryView.vue') },
  { path: '/classifier', name: 'classifier', component: () => import('../views/ClassifierView.vue') },
  { path: '/downloader', name: 'downloader', component: () => import('../views/DownloaderView.vue') },
  { path: '/metrics', name: 'metrics', component: () => import('../views/MetricsView.vue') },
  { path: '/settings', name: 'settings', component: () => import('../views/SettingsView.vue') },
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach((to) => {
  if (to.name !== 'login' && !getApiKey()) {
    return { name: 'login' }
  }
})
