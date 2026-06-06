import { createApp } from 'vue'
import App from './App.vue'
import './styles/main.css'
import './styles/components/app-shell.css'
import './styles/components/nav-fab.css'
import './styles/components/shared-ui.css'
import './styles/pages/home.css'
import './styles/pages/auth.css'
import './styles/pages/domain-detail.css'
import './styles/pages/account-detail.css'
import './styles/pages/settings.css'
import './styles/pages/pending.css'
import './styles/pages/record-detail.css'
import './styles/pages/report.css'
import './styles/pages/unbound.css'

if (new URLSearchParams(location.search).get('debug') === '1') {
  import('vconsole').then(m => new m.default())
}

createApp(App).mount('#app')
