import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { registerSW } from 'virtual:pwa-register';
import { App } from './App';
import { isNative, setupBackButton } from './native';
import { setupWidget } from './widget';
import { initTheme } from './theme';
import './styles.css';

// In de Android-app zitten alle bestanden al in de APK; de service worker is alleen voor de webversie.
if (!isNative) registerSW({ immediate: true });
setupBackButton();
setupWidget();
void initTheme();

// Vraag de browser om de database niet op te ruimen bij weinig opslagruimte
if (navigator.storage?.persist) void navigator.storage.persist();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
