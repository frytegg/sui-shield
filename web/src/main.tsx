// web/src/main.tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { AppProviders } from './providers/AppProviders';
import './index.css';
// CallbackPage (zklogin) removed - app uses wallet-only flow

// debug env (temporaire)
import { ENV } from './env';
console.info('[env] VITE_SHOW_ADMIN =', ENV.VITE_SHOW_ADMIN);
console.info('[env] VITE_RPC_URL =', ENV.VITE_RPC_URL);
console.info('[env] VITE_NETWORK =', ENV.VITE_NETWORK);


const path = window.location.pathname;

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <AppProviders>
      <App />
    </AppProviders>
  </React.StrictMode>,
);
