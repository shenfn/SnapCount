import { createApp } from 'vue'
import App from './App.vue'
import './styles/main.css'

if (new URLSearchParams(location.search).get('debug') === '1') {
  import('vconsole').then(m => new m.default())
}

createApp(App).mount('#app')
