// src/sui/client.ts

// Client RPC Sui typé. Sert pour queries et soumissions de PTB.
import { SuiClient } from '@mysten/sui/client';
import { RPC_URL } from './config';

// Instance unique du client à réutiliser dans l'app.
export const client = new SuiClient({ url: RPC_URL });

// Petite vérification runtime que les IDs existent côté réseau.
export async function verifyOnChainConfig() {
  const [book, oracle] = await Promise.all([
    client.getObject({ id: import('./config').then(m => m.BOOK_ID) as unknown as string, options: { showOwner: true, showType: true } }),
    client.getObject({ id: import('./config').then(m => m.ORACLE_ID) as unknown as string, options: { showOwner: true, showType: true } }),
  ]);
  return { book, oracle };
}
