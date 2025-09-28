// src/sui/tx/coin.ts
/**
 * Fund plan + enact — prépare puis fabrique un Coin<SUI> d’un montant exact dans la même PTB.
 * 1) planFundExactSui: calcule hors-PTB la stratégie (coin cible + merges) via getCoins().
 * 2) enactFundPlan: exécute dans une Transaction: merge si besoin puis splitCoins pour créer le coin exact.
 *
 * Docs: split/merge PTB, examples. https://sdk.mystenlabs.com/typescript/transaction-building/basics
 *       PTB guide. https://docs.sui.io/guides/developer/sui-101/building-ptb
 */
import { SuiClient } from '@mysten/sui/client';
import { Transaction, type TransactionObjectArgument } from '@mysten/sui/transactions';

export type FundPlan = {
  // Coin utilisé comme cible de merge + source du split final
  targetCoinId: string;
  // Coins à merger dans target avant split
  mergeFromIds: string[];
};

export async function planFundExactSui(
  client: SuiClient,
  owner: string,
  amountMist: bigint,
): Promise<FundPlan> {
  const { data } = await client.getCoins({ owner, coinType: '0x2::sui::SUI', limit: 200 });
  const coins = (data ?? []).map((c) => ({ id: c.coinObjectId, bal: BigInt(c.balance) }));
  if (!coins.length) throw new Error('Aucun Coin<SUI> disponible.');

  // 1) Un seul coin suffit → pas de merge
  const single = coins.find((c) => c.bal >= amountMist);
  if (single) return { targetCoinId: single.id, mergeFromIds: [] };

  // 2) Sinon on agrège par ordre décroissant jusqu’à couvrir
  const sorted = [...coins].sort((a, b) => Number(b.bal - a.bal));
  let sum = 0n;
  const picked: string[] = [];
  for (const c of sorted) {
    sum += c.bal;
    picked.push(c.id);
    if (sum >= amountMist) break;
  }
  if (sum < amountMist) throw new Error('Solde SUI insuffisant.');

  // On merge tout dans le premier
  const [target, ...rest] = picked;
  return { targetCoinId: target, mergeFromIds: rest };
}

/**
 * Exécute le plan dans la PTB et retourne le coin exact.
 * - mergeCoins si nécessaire
 * - splitCoins(target, [amount])
 */
export function enactFundPlan(
  tx: Transaction,
  plan: FundPlan,
  amountMist: bigint,
): TransactionObjectArgument {
  if (plan.mergeFromIds.length) {
    tx.mergeCoins(
      tx.object(plan.targetCoinId),
      plan.mergeFromIds.map((id) => tx.object(id)),
    );
  }
  const [exact] = tx.splitCoins(tx.object(plan.targetCoinId), [tx.pure.u64(amountMist)]);
  return exact;
}
