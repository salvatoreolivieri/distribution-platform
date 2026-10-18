import type { ReactNode } from 'react';

export function Layout({ children }: { children: ReactNode }) {
  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', maxWidth: 960, margin: '0 auto', padding: 16 }}>
      <h1>DocBridge</h1>
      {children}
    </main>
  );
}
