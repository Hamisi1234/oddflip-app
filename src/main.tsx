import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'
import { initializeNativeApp } from './native'

void initializeNativeApp((notification) => {
  window.dispatchEvent(new CustomEvent('red-card-push', {
    detail: notification.data,
  }))
})

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
