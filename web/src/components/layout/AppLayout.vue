<template>
  <div class="min-h-screen flex flex-col">
    <NavBar />
    <main class="flex-1">
      <slot />
    </main>
  </div>
</template>

<script setup>
import NavBar from './NavBar.vue'
</script>
