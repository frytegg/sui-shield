// src/sui/read.ts
/**
 * Lecture on-chain centralisée: events + vues (devInspect) + BCS.
 *
 * Expose:
 * - queryOfferPostedEvents/queryPolicyCreatedEvents
 * - viewOffers/viewPolicies  (robustes)
 * - countOffers/countPolicies (robustes)
 *
 * Si devInspect ne renvoie rien, on retourne [] / 0 et on log un warn.
 */

import {
  SuiClient,
  DevInspectResults,
  SuiEvent,
  EventId,
} from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { bcs } from '@mysten/sui/bcs';
import { PACKAGE_ID, BOOK_ID } from './config';

// ---------- Types UI ----------
export type UiOffer = {
  id: string;
  insurer: string;
  premiumMist: bigint;
  collateralMist: bigint;
  strikeMist: bigint;
  validUntilMs?: number;
  recurring?: boolean;
};

export type UiPolicy = {
  policyId: string;
  insured: string;
  insurer: string;
  expiryMs: number;
  remainingTxs: bigint;
  coverageLeftMist: bigint;
  policyType?: number;
};

// ---------- Constantes ----------
const EV_OFFER = `${PACKAGE_ID}::gas_insurance_marketplace::OfferPosted`;
const EV_POLICY = `${PACKAGE_ID}::gas_insurance_marketplace::PolicyCreated`;

const VIEW_OFFERS = `${PACKAGE_ID}::gas_insurance_marketplace::view_offers`;
const VIEW_POLICIES = `${PACKAGE_ID}::gas_insurance_marketplace::view_policies`;
const COUNT_OFFERS = `${PACKAGE_ID}::gas_insurance_marketplace::count_offers`;
const COUNT_POLICIES = `${PACKAGE_ID}::gas_insurance_marketplace::count_policies`;

const ZERO_SENDER =
  '0x0000000000000000000000000000000000000000000000000000000000000000';

// ---------- BCS schemas ----------
const OfferView = bcs.struct('OfferView', {
  offer_id: bcs.Address,
  insurer: bcs.Address,
  policy_type: bcs.u8(),
  strike_mist_per_unit: bcs.u64(),
  premium_mist: bcs.u64(),
  coverage_limit_mist: bcs.u64(),
  start_ms: bcs.u64(),
  expiry_ms: bcs.u64(),
  max_txs: bcs.u64(),
  is_active: bcs.bool(),
});

const PolicyView = bcs.struct('PolicyView', {
  policy_id: bcs.Address,
  insured: bcs.Address,
  insurer: bcs.Address,
  expiry_ms: bcs.u64(),
  remaining_txs: bcs.u64(),
  coverage_left_mist: bcs.u64(),
  policy_type: bcs.u8(),
});

// ---------- Utils bytes ----------
function b64ToBytes(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function hexToBytes(s: string): Uint8Array {
  const t = s.startsWith('0x') ? s.slice(2) : s;
  if (!/^[0-9a-fA-F]*$/.test(t) || t.length % 2) throw new Error('bad hex');
  const out = new Uint8Array(t.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(t.slice(i * 2, i * 2 + 2), 16);
  return out;
}
/** Tolérant aux formats devInspect: [b64,"vector<u8>"] | b64 | 0x… | Uint8Array | number[] */
function toBytes(input: any): Uint8Array | null {
  if (input == null) return null;
  if (Array.isArray(input)) {
    if (input.length === 2 && typeof input[0] === 'string') return toBytes(input[0]);
    if (input.every((x) => typeof x === 'number')) return Uint8Array.from(input as number[]);
    return null;
  }
  if (input instanceof Uint8Array) return input;
  if (typeof input === 'string') {
    try { return b64ToBytes(input); } catch { /* not b64 */ }
    try { return hexToBytes(input); } catch { /* not hex */ }
    return null;
  }
  if (typeof input === 'object') {
    if (input.bytes && Array.isArray(input.bytes)) return Uint8Array.from(input.bytes);
    if (typeof input.value === 'string') return toBytes(input.value);
  }
  return null;
}

/** Extrait les bytes du premier retour. Null si rien ou longueur 0. */
function firstReturnBytes(r: DevInspectResults): Uint8Array | null {
  const rv = r.results?.[0]?.returnValues?.[0];
  const b = toBytes(rv);
  if (!b || b.length === 0) return null;
  return b;
}

// ---------- devInspect helpers ----------
async function callViewWithArgs(client: SuiClient, target: string, args: (tx: Transaction) => any[]) {
  const tx = new Transaction();
  tx.moveCall({ target, arguments: args(tx) });
  return client.devInspectTransactionBlock({ transactionBlock: tx, sender: ZERO_SENDER });
}

/** Essaie avec BOOK_ID, puis sans argument si premier essai vide. */
async function callViewRobust(client: SuiClient, target: string): Promise<Uint8Array | null> {
  try {
    const r1 = await callViewWithArgs(client, target, (tx) => [tx.object(BOOK_ID)]);
    const b1 = firstReturnBytes(r1);
    if (b1) return b1;
  } catch (e) {
    console.warn(`${target} devInspect with BOOK_ID failed:`, e);
  }
  try {
    const r2 = await callViewWithArgs(client, target, () => []);
    const b2 = firstReturnBytes(r2);
    if (b2) return b2;
  } catch (e) {
    console.warn(`${target} devInspect without args failed:`, e);
  }
  return null;
}

// ---------- Events ----------
export type EventsPage<T = SuiEvent> = {
  data: T[];
  nextCursor: EventId | null;
  hasNextPage: boolean;
};

export async function queryOfferPostedEvents(
  client: SuiClient,
  cursor?: EventId | null,
  limit = 50,
): Promise<EventsPage> {
  const res = await client.queryEvents({
    query: { MoveEventType: EV_OFFER },
    cursor: cursor ?? undefined,
    limit,
    order: 'descending',
  });
  return { data: res.data, nextCursor: res.nextCursor ?? null, hasNextPage: !!res.hasNextPage };
}

export async function queryPolicyCreatedEvents(
  client: SuiClient,
  cursor?: EventId | null,
  limit = 50,
): Promise<EventsPage> {
  const res = await client.queryEvents({
    query: { MoveEventType: EV_POLICY },
    cursor: cursor ?? undefined,
    limit,
    order: 'descending',
  });
  return { data: res.data, nextCursor: res.nextCursor ?? null, hasNextPage: !!res.hasNextPage };
}

// ---------- Views + fallbacks ----------
export async function viewOffers(client: SuiClient): Promise<UiOffer[]> {
  // 1) Récupère les derniers IDs d’offres via événements
  const ev = await client.queryEvents({
    query: { MoveEventType: EV_OFFER },
    order: 'descending',
    limit: 200,
  });
  const ids = ev.data
    .map((e) => (e as any).parsedJson?.offer_id as string | undefined)
    .filter((x): x is string => !!x);

  if (ids.length === 0) return [];

  // 2) Appelle la vue avec (book, vector<ID>)
  const tx = new Transaction();
  tx.moveCall({
    target: VIEW_OFFERS,
    arguments: [tx.object(BOOK_ID), tx.pure.vector('address', ids)],
  });
  const r = await client.devInspectTransactionBlock({
    transactionBlock: tx,
    sender: ZERO_SENDER,
  });

  const bytes = firstReturnBytes(r);
  if (!bytes) {
    // fallback événements si la vue ne renvoie rien
    return ev.data.map(mapOfferEvent).filter(Boolean) as UiOffer[];
  }

  // 3) Parse BCS -> UI
  const vec = bcs.vector(OfferView).parse(bytes) as Array<{
    offer_id: string;
    insurer: string;
    policy_type: number;
    strike_mist_per_unit: bigint;
    premium_mist: bigint;
    coverage_limit_mist: bigint;
    start_ms: bigint;
    expiry_ms: bigint;
    max_txs: bigint;
    is_active: boolean;
  }>;

  return vec.map((o) => ({
    id: o.offer_id,
    insurer: o.insurer,
    premiumMist: BigInt(o.premium_mist),
    collateralMist: BigInt(o.coverage_limit_mist),
    strikeMist: BigInt(o.strike_mist_per_unit),
    validUntilMs: Number(o.expiry_ms),
    recurring: Number(o.policy_type) === 1,
  }));
}


export async function viewPolicies(client: SuiClient): Promise<UiPolicy[]> {
  const bytes = await callViewRobust(client, VIEW_POLICIES);
  if (!bytes) {
    console.warn('viewPolicies devInspect empty → []');
    return [];
  }
  try {
    const vec = bcs.vector(PolicyView).parse(bytes) as Array<{
      policy_id: string; insured: string; insurer: string; expiry_ms: bigint;
      remaining_txs: bigint; coverage_left_mist: bigint; policy_type: number;
    }>;
    return vec.map((p) => ({
      policyId: p.policy_id,
      insured: p.insured,
      insurer: p.insurer,
      expiryMs: Number(p.expiry_ms),
      remainingTxs: BigInt(p.remaining_txs),
      coverageLeftMist: BigInt(p.coverage_left_mist),
      policyType: Number(p.policy_type ?? 0),
    }));
  } catch (e) {
    console.warn('viewPolicies parse failed → []', e);
    return [];
  }
}

export async function countOffers(client: SuiClient): Promise<number> {
  try {
    const bytes = await callViewRobust(client, COUNT_OFFERS);
    if (!bytes || bytes.length < 8) throw new Error('empty');
    const n = bcs.u64().parse(bytes) as bigint;
    return Number(n);
  } catch (e) {
    console.warn('countOffers devInspect failed:', e);
    return 0;
  }
}

export async function countPolicies(client: SuiClient): Promise<number> {
  try {
    const bytes = await callViewRobust(client, COUNT_POLICIES);
    if (!bytes || bytes.length < 8) throw new Error('empty');
    const n = bcs.u64().parse(bytes) as bigint;
    return Number(n);
  } catch (e) {
    console.warn('countPolicies devInspect failed:', e);
    return 0;
  }
}

// ---------- Map événements -> UI ----------
export function mapOfferEvent(ev: SuiEvent): UiOffer | null {
  const pj: any = ev.parsedJson ?? {};
  if (!pj) return null;
  return {
    id: String(pj.offer_id ?? ev.id?.txDigest + ':' + ev.id?.eventSeq),
    insurer: String(pj.insurer ?? pj.creator ?? '0x'),
    premiumMist: BigInt(pj.premium_mist ?? 0),
    collateralMist: BigInt(pj.coverage_limit_mist ?? 0),
    strikeMist: BigInt(pj.strike_mist_per_unit ?? 0),
    validUntilMs: pj.expiry_ms ? Number(pj.expiry_ms) : undefined,
    recurring: Number(pj.policy_type ?? 0) === 1,
  };
}


export function mapPolicyEvent(ev: SuiEvent): UiPolicy | null {
  const pj: any = ev.parsedJson ?? {};
  if (!pj) return null;
  return {
    policyId: String(pj.policy_id ?? pj.id ?? ev.id?.txDigest + ':' + ev.id?.eventSeq),
    insured: String(pj.insured ?? '0x'),
    insurer: String(pj.insurer ?? '0x'),
    expiryMs: Number(pj.expiry_ms ?? 0),
    remainingTxs: BigInt(pj.remaining_txs ?? 0),
    coverageLeftMist: BigInt(pj.coverage_left_mist ?? 0),
    policyType: pj.policy_type !== undefined ? Number(pj.policy_type) : undefined,
  };
}
