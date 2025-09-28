// web/src/env.ts
type Cfg = {
  VITE_ZK_CLIENT_ID?: string;
  VITE_ZK_ISS?: string;
  VITE_ZK_REDIRECT_URL?: string;
  VITE_RPC_URL?: string;
};
declare global { interface Window { __ENV?: Partial<Cfg>; } }

export const ENV: Cfg = {
  VITE_SHOW_ADMIN: import.meta.env.VITE_SHOW_ADMIN ?? '1',
  VITE_ZK_CLIENT_ID: import.meta.env.VITE_ZK_CLIENT_ID || window.__ENV?.VITE_ZK_CLIENT_ID,
  VITE_ZK_ISS: import.meta.env.VITE_ZK_ISS || window.__ENV?.VITE_ZK_ISS,
  VITE_ZK_REDIRECT_URL: import.meta.env.VITE_ZK_REDIRECT_URL || window.__ENV?.VITE_ZK_REDIRECT_URL,
  VITE_RPC_URL: import.meta.env.VITE_RPC_URL || window.__ENV?.VITE_RPC_URL,
};
