// src/hooks/useSuiCoins.ts
/**
 * useSuiCoins — liste les Coin<SUI> d’un owner et expose des helpers simples.
 *
 * Docs:
 * - getCoins(owner, coinType): https://docs.sui.io/sui-api-ref#suix_getcoins (SDK wrapper: client.getCoins) :contentReference[oaicite:3]{index=3}
 */
import { useCallback, useEffect, useState } from 'react';
import { useSuiClient } from '@mysten/dapp-kit';

export type SuiCoin = {
  coinObjectId: string;
  balance: bigint;
};

export function useSuiCoins(owner?: string) {
  const client = useSuiClient();
  const [coins, setCoins] = useState<SuiCoin[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setErr] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!owner) {
      setCoins([]);
      return;
    }
    setLoading(true);
    setErr(null);
    try {
      const out = await client.getCoins({ owner, coinType: '0x2::sui::SUI', limit: 200 });
      setCoins(
        (out.data ?? []).map((c) => ({
          coinObjectId: c.coinObjectId,
          balance: BigInt(c.balance),
        })),
      );
    } catch (e: any) {
      setErr(e?.message ?? 'getCoins failed');
      setCoins([]);
    } finally {
      setLoading(false);
    }
  }, [client, owner]);

  useEffect(() => { void refresh(); }, [refresh]);

  const pickAny = useCallback(() => {
    if (!coins.length) throw new Error('Aucun Coin<SUI> disponible.');
    return coins[0].coinObjectId;
  }, [coins]);

  const pickForAmount = useCallback((amountMist: bigint) => {
    const found = coins.find((c) => c.balance >= amountMist);
    if (!found) throw new Error('Solde SUI insuffisant.');
    return found.coinObjectId;
  }, [coins]);

  return { coins, loading, error, refresh, pickAny, pickForAmount };
}

export default useSuiCoins;
