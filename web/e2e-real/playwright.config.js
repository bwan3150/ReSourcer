import { defineConfig } from '@playwright/test'
export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.js',
  timeout: 90_000,
  retries: 0,
  workers: 1,
  reporter: [['list']],
  use: {
    baseURL: 'http://127.0.0.1:5173',
    trace: 'off',
    screenshot: 'only-on-failure',
  },
})
