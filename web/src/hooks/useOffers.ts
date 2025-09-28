// src/hooks/useOffers.ts
/**
 * useOffers — lit les offres on-chain.
 * 1) Vue via devInspect: view_offers (BCS).
 * 2) Fallback événements OfferPosted paginés.
 * 3) Compteurs count_offers / count_policies.
 *
 * Docs:
 * - SuiClient (queryEvents, devInspect): https://sdk.mystenlabs.com/typescript/sui-client :contentReference[oaicite:0]{index=0}
 * - Events guide (queryEvents): https://docs.sui.io/guides/developer/sui-101/using-events :contentReference[oaicite:1]{index=1}
 * - devInspectTransactionBlock: https://sdk.mystenlabs.com/typedoc/classes/_mysten_sui.client.SuiClient.html#devInspectTransactionBlock :contentReference[oaicite:2]{index=2}
 */
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useSuiClient } from '@mysten/dapp-kit';
import type { EventId } from '@mysten/sui/client';
import {
  viewOffers as viewOffersRpc,
  queryOfferPostedEvents,
  mapOfferEvent,
  countOffers as countOffersRpc,
  countPolicies as countPoliciesRpc,
} from '@/sui/read';

export type UiOffer = Awaited<ReturnType<typeof viewOffersRpc>>[number];

export function useOffers(pageSize = 100) {
  const client = useSuiClient();

  const [data, setData] = useState<UiOffer[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setErr] = useState<string | null>(null);

  // pagination événements (fallback)
  const [cursor, setCursor] = useState<EventId | null>(null);
  const [hasNext, setHasNext] = useState(false);

  // compteurs
  const [offersCount, setOffersCount] = useState<number>(0);
  const [policiesCount, setPoliciesCount] = useState<number>(0);

  const loadCounts = useCallback(async () => {
    const [co, cp] = await Promise.all([countOffersRpc(client), countPoliciesRpc(client)]);
    setOffersCount(co);
    setPoliciesCount(cp);
  }, [client]);

  const loadFromView = useCallback(async () => {
    const list = await viewOffersRpc(client);
    setData(list);
    setErr(null);
  }, [client]);

  const loadFromEvents = useCallback(async () => {
    const page = await queryOfferPostedEvents(client, cursor, pageSize);
    const mapped = page.data.map(mapOfferEvent).filter(Boolean) as UiOffer[];
    setData((prev) => {
      // dédupliquer par id
      const acc = new Map<string, UiOffer>();
      [...prev, ...mapped].forEach((o) => acc.set(o.id, o));
      return [...acc.values()];
    });
    setCursor(page.nextCursor);
    setHasNext(page.hasNextPage);
    setErr(null);
  }, [client, cursor, pageSize]);

  const refresh = useCallback(async () => {
    setIsLoading(true);
    setErr(null);
    setCursor(null);
    setHasNext(false);
    setData([]);
    try {
      await Promise.all([loadCounts(), loadFromView()]);
    } catch {
      await Promise.all([loadCounts(), loadFromEvents()]);
    } finally {
      setIsLoading(false);
    }
  }, [loadCounts, loadFromView, loadFromEvents]);

  useEffect(() => { refresh(); }, [refresh]);

  const loadMore = useCallback(async () => {
    if (!hasNext || isLoading) return;
    setIsLoading(true);
    try {
      await loadFromEvents();
    } finally {
      setIsLoading(false);
    }
  }, [hasNext, isLoading, loadFromEvents]);

  // Tri optionnel: premium croissant par défaut
  const sorted = useMemo(() => {
    return [...data].sort((a, b) => Number(a.premiumMist - b.premiumMist));
  }, [data]);

  return {
    data: sorted,
    isLoading,
    error,
    refresh,
    loadMore,
    hasNext,
    counts: { offers: offersCount, policies: policiesCount },
  };
}

export default useOffers;
