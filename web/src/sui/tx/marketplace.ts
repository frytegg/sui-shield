// src/sui/tx/marketplace.ts
import { Transaction, type TransactionObjectArgument } from '@mysten/sui/transactions';
import { PACKAGE_ID, BOOK_ID, ORACLE_ID } from '@/sui/config';

// Clock système Sui (objet partagé)
const CLOCK_ID = '0x6';

// Utilitaire: choisir l’argument coin depuis un id string ou un arg inline
function coinArg(
  tx: Transaction,
  coin: { coinId: string } | { coinArg: TransactionObjectArgument },
): TransactionObjectArgument {
  if ('coinArg' in coin) return coin.coinArg;
  return tx.object(coin.coinId);
}

/**
 * accept_offer(
 *   book: &mut Book, clock: &Clock, offer_id: ID, premium_coin: Coin<SUI>, ctx: &mut TxContext
 * )
 */
export function txAcceptOffer(
  params: {
    offerId: string;
    premium: { coinId: string } | { coinArg: TransactionObjectArgument };
  },
  existing?: Transaction,
): Transaction {
  const tx = existing ?? new Transaction();
  const premiumArg = coinArg(tx, params.premium);

  tx.moveCall({
    target: `${PACKAGE_ID}::gas_insurance_marketplace::accept_offer`,
    arguments: [
      tx.object(BOOK_ID),
      tx.object(CLOCK_ID),       // <-- Clock requis
      tx.object(params.offerId),
      premiumArg,
    ],
  });

  return tx;
}

/**
 * post_offer(
 *  book: &mut Book,
 *  policy_type: u8,                 // 0=ONE_TIME, 1=WINDOW
 *  strike_mist_per_unit: u64,
 *  premium_mist: u64,
 *  start_ms: u64,
 *  expiry_ms: u64,
 *  max_txs: u64,
 *  collateral: Coin<SUI>,
 *  coverage_limit_mist: u64,
 *  ctx: &mut TxContext
 * )
 *
 * NOTE: pour ONE_TIME, start_ms == expiry_ms et max_txs = 1.
 */
export function txPostOffer(
  params: {
    premiumMist: bigint;
    strikeMist: bigint;           // strike_mist_per_unit
    validUntilMs: number;         // expiry_ms
    recurring: boolean;           // -> policy_type
    maxTransactions: number;      // max_txs (ignoré et forcé à 1 en one-time)
    validFromMs: number;          // start_ms (en recurring), ignoré en one-time
    collateralMist: bigint;       // coverage_limit_mist == valeur du coin
    collateral: { coinId: string } | { coinArg: TransactionObjectArgument };
  },
  existing?: Transaction,
): Transaction {
  const tx = existing ?? new Transaction();
  const collateralArg = coinArg(tx, params.collateral);

  // Mapping selon la signature Move
  const policyType = params.recurring ? 1 : 0;                            // u8
  const startMs = params.recurring ? params.validFromMs : params.validUntilMs; // u64
  const maxTxs = params.recurring ? params.maxTransactions : 1;           // u64

  tx.moveCall({
    target: `${PACKAGE_ID}::gas_insurance_marketplace::post_offer`,
    arguments: [
      tx.object(BOOK_ID),
      tx.pure.u8(policyType),
      tx.pure.u64(params.strikeMist),
      tx.pure.u64(params.premiumMist),
      tx.pure.u64(startMs),
      tx.pure.u64(params.validUntilMs),
      tx.pure.u64(maxTxs),
      collateralArg,                                  // Coin<SUI>
      tx.pure.u64(params.collateralMist),             // coverage_limit_mist
    ],
  });

  return tx;
}

/**
 * settle_tx(
 *  book: &mut Book, oracle: &mut GasOracle, clock: &Clock, policy: &mut Policy, tx_digest: vector<u8>, ctx
 * )
 */
export function txSettle(
  params: { policyId: string; txDigest: string },
  existing?: Transaction,
): Transaction {
  const tx = existing ?? new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::gas_insurance_marketplace::settle_tx`,
    arguments: [
      tx.object(BOOK_ID),
      tx.object(ORACLE_ID),
      tx.object(CLOCK_ID),
      tx.object(params.policyId),
      tx.pure.vector('u8', Array.from(new TextEncoder().encode(params.txDigest))), // digest bytes
    ],
  });
  return tx;
}

/**
 * reclaim_collateral_after_expiry(
 *  book: &mut Book, clock: &Clock, policy: &mut Policy, ctx
 * )
 */
export function txReclaim(
  params: { policyId: string },
  existing?: Transaction,
): Transaction {
  const tx = existing ?? new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::gas_insurance_marketplace::reclaim_collateral_after_expiry`,
    arguments: [
      tx.object(BOOK_ID),
      tx.object(CLOCK_ID),
      tx.object(params.policyId),
    ],
  });
  return tx;
}
