// src/hooks/useZkLogin.ts
import { useCallback, useState } from 'react';

type Artifacts = null | {
  jwt: string;
  addressSeed: string;
  proof: Record<string, unknown>;
};

export function useZkLogin() {
  const [address, setAddress] = useState<string | undefined>();
  const [artifacts, setArtifacts] = useState<Artifacts>(null);

  const logout = useCallback(() => {
    setAddress(undefined);
    setArtifacts(null);
  }, []);

  const login = useCallback(() => {
    const demo = import.meta.env.VITE_ZKLOGIN_DEMO === '1';
    const startUrl = import.meta.env.VITE_ZKLOGIN_START_URL;

    if (demo) {
      // Simule une adresse pour tester l’UI immédiatement
      const bytes = crypto.getRandomValues(new Uint8Array(32));
      const fake = '0x' + Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
      setAddress(fake);
      setArtifacts(null); // pas de preuve en mode démo
      return;
    }

    if (startUrl) {
      // Laisse ton backend gérer OIDC + preuve puis rediriger vers l’app
      sessionStorage.setItem('zklogin:return', window.location.href);
      window.location.href = startUrl;
      return;
    }

    alert('Config manquante: définis VITE_ZKLOGIN_START_URL ou VITE_ZKLOGIN_DEMO=1');
  }, []);

  return { login, logout, address, artifacts, setArtifacts };
}
