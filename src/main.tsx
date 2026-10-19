import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { registerSW } from 'virtual:pwa-register';
import { App } from './App';
import { startBackups } from './data/repo';
import { recordLaunch } from './data/spikeDb';
import { applyTheme } from './theme';
import './styles.css';
import './editor/editor.css';
import './pages/pages.css';
import './open/open.css';

applyTheme();
registerSW({ immediate: true });
void recordLaunch();
startBackups();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
