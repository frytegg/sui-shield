// src/hooks/usePolicies.ts
/**
 * usePolicies — charge la liste live des policies.
 *
 * Stratégie:
 * 1) Essaye la vue on-chain (devInspect -> view_policies + BCS).
 * 2) Fallback sur les événements PolicyCreated paginés si la vue n’existe pas.
 * 3) Expose { data, isLoading, error, refresh } à l’UI.
 *
 * Docs:
 * - devInspectTransactionBlock (views) :contentReference[oaicite:4]{index=4}
 * - queryEvents pagination :contentReference[oaicite:5]{index=5}
 */
import { useEffect, useMemo, useState, useCallback } from 'react';
import { useSuiClient } from '@mysten/dapp-kit';
import type { EventId } from '@mysten/sui/client';
import {
  viewPolicies as viewPoliciesRpc,
  queryPolicyCreatedEvents,
  mapPolicyEvent,
  type UiPolicy,
} from '@/sui/read';

export function usePolicies(pageSize = 100) {
  const client = useSuiClient();

  const [data, setData] = useState<UiPolicy[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setErr] = useState<string | null>(null);

  // pagination événements (fallback)
  const [cursor, setCursor] = useState<EventId | null>(null);
  const [hasNext, setHasNext] = useState(false);

  const loadFromView = useCallback(async () => {
    const list = await viewPoliciesRpc(client); // peut jeter si view absente
    setData(list);
    setErr(null);
  }, [client]);

  const loadFromEvents = useCallback(async () => {
    const page = await queryPolicyCreatedEvents(client, cursor, pageSize);
    const mapped = page.data.map(mapPolicyEvent).filter(Boolean) as UiPolicy[];
    setData((prev) => {
      // dédupliquer par policyId
      const acc = new Map<string, UiPolicy>();
      [...prev, ...mapped].forEach((p) => acc.set(p.policyId, p));
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
      await loadFromView();
    } catch (e: any) {
      // Vue indisponible ou BCS incompatible → fallback événements
      await loadFromEvents();
    } finally {
      setIsLoading(false);
    }
  }, [loadFromView, loadFromEvents]);

  // Initial load
  useEffect(() => { refresh(); }, [refresh]);

  // Load more (events only)
  const loadMore = useCallback(async () => {
    if (!hasNext || isLoading) return;
    setIsLoading(true);
    try {
      await loadFromEvents();
    } finally {
      setIsLoading(false);
    }
  }, [hasNext, isLoading, loadFromEvents]);

  // Tri stable: non expirées d’abord, puis par expiry
  const sorted = useMemo(() => {
    return [...data].sort((a, b) => {
      const ax = Date.now() > a.expiryMs ? 1 : 0;
      const bx = Date.now() > b.expiryMs ? 1 : 0;
      if (ax !== bx) return ax - bx;
      return a.expiryMs - b.expiryMs;
    });
  }, [data]);

  return { data: sorted, isLoading, error, refresh, loadMore, hasNext };
}

export default usePolicies;
