// src/sui/config.ts

// Réseau Sui à cibler.
// Pour testnet en dev; passe à 'mainnet' en prod.
export const NETWORK: 'localnet' | 'devnet' | 'testnet' | 'mainnet' = 'testnet';

// URL RPC standard fournie par le SDK pour ce réseau.
import { getFullnodeUrl } from '@mysten/sui/client'; // helper officiel
export const RPC_URL = getFullnodeUrl(NETWORK);

// IDs on-chain de ton package et des objets partagés.
// Ces valeurs viennent de tes transactions "init_*".
export const PACKAGE_ID =
  '0x205acdd30a8a741d3f7de74ed7517e526aa720e1d02789aeda87e53a0cf5dc99';

export const BOOK_ID =
  '0xd49a7b1a8e205fd69aecc9fca7ebaa713258dbe7430e88145ab7b93c93715cdd';

export const ORACLE_ID =
  '0x14011bd609a7905416bca0bfa056b269ffb1d91003cf04d2352db04fbfb580c6';

// ID constant du Clock sur Sui (utilisé par plusieurs entry functions).
export const CLOCK_ID = '0x6';
