import { SuiClient, type DevInspectResults, type EventId, type SuiEvent } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { bcs } from '@mysten/sui/bcs';
import { PACKAGE_ID, ORACLE_ID } from '@/sui/config';

const ZERO =
  '0x0000000000000000000000000000000000000000000000000000000000000000';

// supposé: gas_oracle::ObservationSubmitted
const EV_OBS = `${PACKAGE_ID}::gas_oracle::ObservationSubmitted`;

function fromB64(b: string) {
  if (typeof atob === 'function') {
    const s = atob(b); const a = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) a[i] = s.charCodeAt(i);
    return a;
  }
  // @ts-ignore
  return Uint8Array.from(Buffer.from(b, 'base64'));
}

async function callView(client: SuiClient, target: string, args: (tx: Transaction) => any[]) {
  const tx = new Transaction();
  tx.moveCall({ target, arguments: args(tx) });
  return client.devInspectTransactionBlock({ transactionBlock: tx, sender: ZERO });
}

function firstBytes(r: DevInspectResults) {
  const rv = r.results?.[0]?.returnValues?.[0];
  if (!rv) return null;
  return fromB64((rv as [string, string])[0]);
}

/** Retourne gasUsedMist si trouvé, sinon null. */
export async function viewObservedGas(client: SuiClient, policyId: string): Promise<bigint | null> {
  try {
    const r = await callView(
      client,
      `${PACKAGE_ID}::gas_oracle::get_observed_gas`,
      (tx) => [tx.object(ORACLE_ID), tx.object(policyId)],
    );
    const bytes = firstBytes(r);
    if (!bytes) return null;

    // cas 1: la vue retourne u64 directement
    try {
      return bcs.u64().parse(bytes) as bigint;
    } catch {
      // cas 2: struct { gas_used_mist: u64, tx_digest: String/vec<u8> } (meilleure supposition)
      const Obs = bcs.struct('Observation', {
        gas_used_mist: bcs.u64(),
      });
      const s = Obs.parse(bytes) as { gas_used_mist: bigint };
      return BigInt(s.gas_used_mist ?? 0n);
    }
  } catch {
    return null;
  }
}

export async function queryObservationEvents(
  client: SuiClient,
  cursor?: EventId | null,
  limit = 50,
): Promise<{ data: SuiEvent[]; nextCursor: EventId | null; hasNextPage: boolean }> {
  try {
    const res = await client.queryEvents({
      query: { MoveEventType: EV_OBS },
      cursor: cursor ?? undefined,
      limit,
      order: 'descending',
    });
    return { data: res.data, nextCursor: res.nextCursor ?? null, hasNextPage: !!res.hasNextPage };
  } catch {
    return { data: [], nextCursor: null, hasNextPage: false };
  }
}
