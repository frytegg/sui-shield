import { useCallback, useMemo, useRef, useState } from 'react';
import { useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';
import type { SuiTransactionBlockResponse } from '@mysten/sui/client';

// Réseau cible: testnet
const CHAIN = 'sui:testnet';

export type ExecuteTxResponse = {
  digest: string;
  response: SuiTransactionBlockResponse;
};

export function useExecuteTx() {
  // Adresse connectée via wallet
  const account = useCurrentAccount();
  // Client RPC (pour waitForTransaction)
  const client = useSuiClient();
  // Hook dapp-kit pour signer+exécuter
  const { mutateAsync: signAndExecute, isPending, error: walletError } = useSignAndExecuteTransaction();
  // État UI
  const [lastDigest, setLastDigest] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  // Annulation d’un wait en cours si composant unmount
  const abortRef = useRef<AbortController | null>(null);

  // Fonction principale d’exécution
  const execute = useCallback(async (build: () => Transaction): Promise<ExecuteTxResponse> => {
    // Reset état UI
    setErrorMessage(null);
    setLastDigest(null);

    // Vérifier connexion wallet
    if (!account) {
      const msg = 'Wallet non connecté.';
      setErrorMessage(msg);
      throw new Error(msg);
    }

    try {
      // 1) Construire la PTB
      const tx = build();
      // 2) Définir l’émetteur si absent
      tx.setSenderIfNotSet(account.address);
      // 3) Signer + exécuter côté wallet
      const result = await signAndExecute({
        transaction: tx,
        chain: CHAIN,
        options: { showEffects: false, showEvents: false },
      });

      // 4) Attendre l’indexation côté fullnode pour effets/événements stables
      abortRef.current?.abort();
      abortRef.current = new AbortController();

      const response = await client.waitForTransaction({
        digest: (result as any).digest,
        signal: abortRef.current.signal,
        options: {
          showEffects: true,
          showEvents: true,
          showObjectChanges: false,
          showBalanceChanges: false,
          showInput: false,
        },
      });

      setLastDigest(response.digest);
      return { digest: response.digest, response };
    } catch (e: any) {
      // Normaliser un message d’erreur lisible
      const msg = e?.message ?? e?.shortMessage ?? walletError?.message ?? 'Échec de la transaction.';
      setErrorMessage(msg);
      throw new Error(msg);
    }
  }, [account, client, signAndExecute, walletError]);

  // API retournée au composant
  return useMemo(() => ({
    execute,
    isPending,
    error: errorMessage,
    lastDigest,
    reset: () => {
      setErrorMessage(null);
      setLastDigest(null);
      abortRef.current?.abort();
    },
  }), [execute, isPending, errorMessage, lastDigest]);
}

export default useExecuteTx;