import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, ORACLE_ID } from '@/sui/config';

/** Envoie une observation de gas pour une policy. */
export function txSubmitObservation(
  params: { policyId: string; txDigest: string; gasUsedMist: bigint },
  existing?: Transaction,
): Transaction {
  const tx = existing ?? new Transaction();

  tx.moveCall({
    target: `${PACKAGE_ID}::gas_oracle::submit_observation`,
    arguments: [
      tx.object(ORACLE_ID),                 // shared oracle
      tx.object(params.policyId),           // policy object
      tx.pure.string(params.txDigest),      // digest observé (string)
      tx.pure.u64(params.gasUsedMist),      // gas utilisé en MIST (u64)
    ],
  });

  return tx;
}

export function txSetOperator(
  params: { newOperator: string; enabled?: boolean },
  existing?: Transaction,
): Transaction {
  const tx = existing ?? new Transaction();
  const enabled = params.enabled ?? true; // par défaut: activer

  tx.moveCall({
    target: `${PACKAGE_ID}::gas_oracle::set_operator`,
    arguments: [
      tx.object(ORACLE_ID),
      tx.pure.address(params.newOperator),
      tx.pure.bool(enabled),
    ],
  });

  return tx;
}
