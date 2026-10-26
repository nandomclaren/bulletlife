import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { registerSW } from 'virtual:pwa-register';
import { App } from './App';
import { startBackups, startSyncUpkeep } from './data/repo';
import { recordLaunch } from './data/spikeDb';
import { applyPalette, applyTheme } from './theme';
import './styles.css';
import './editor/editor.css';
import './pages/pages.css';
import './open/open.css';
import './ink/ink.css';
import './search/search.css';

applyTheme();
applyPalette();
registerSW({ immediate: true });
void recordLaunch();
startBackups();
startSyncUpkeep();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
