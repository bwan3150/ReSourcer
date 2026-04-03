/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js}'],
  theme: {
    extend: {},
  },
  plugins: [require('daisyui')],
  daisyui: {
    themes: [
      {
        light: {
          ...require('daisyui/src/theming/themes')['light'],
          'primary': '#374151',       // gray-700
          'primary-content': '#ffffff',
          'neutral': '#1f2937',       // gray-800
          'neutral-content': '#f9fafb',
          'info': '#6b7280',          // gray-500
          'success': '#6b7280',
          'warning': '#9ca3af',
          'error': '#dc2626',         // keep red for danger
        },
      },
      {
        dark: {
          ...require('daisyui/src/theming/themes')['dark'],
          'primary': '#d1d5db',       // gray-300
          'primary-content': '#111827',
          'neutral': '#e5e7eb',       // gray-200
          'neutral-content': '#111827',
          'info': '#9ca3af',          // gray-400
          'success': '#9ca3af',
          'warning': '#6b7280',
          'error': '#ef4444',
        },
      },
    ],
    darkTheme: 'dark',
  },
}
