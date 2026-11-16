import { StrictMode, useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';

function App() {
  const [health, setHealth] = useState('checking...');

  useEffect(() => {
    fetch('./api/health')
      .then((r) => r.json())
      .then((d) => setHealth(JSON.stringify(d)))
      .catch(() => setHealth('offline / static-only mode'));
  }, []);

  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', maxWidth: 640, margin: '48px auto', padding: 20 }}>
      <h1>MicroApp Starter</h1>
      <p>Cloud-agnostic rapid micro-app skeleton ready for static + API delivery.</p>
      <pre style={{ background: '#111827', color: '#e5e7eb', padding: 12, borderRadius: 8 }}>{health}</pre>
    </main>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
