Gas Insurance — README (Testnet)

Purpose
- On-chain gas insurance on Sui. Three modules in one package: gas_insurance, gas_insurance_marketplace, gas_oracle.

Modules
- gas_insurance: Policy struct, payout calculation, expiry checks.
- gas_insurance_marketplace: Post offers or requests, escrow premium/collateral, match, create policy, settle, cancel.
- gas_oracle: Allowlisted operators submit gas observations per policy and tx digest.

How it works
1. Initialize shared objects: Book and GasOracle.
2. An insurer posts an offer or a user posts a request. Funds are escrowed.
3. Accepting an offer or matching creates a Policy.
4. An operator submits gas usage into the oracle for a given policy and tx.
5. Settlement transfers payout to the insured if gas_used exceeds strike, capped by collateral and limits.
6. After expiry the insurer reclaims remaining collateral.


IDs
Testnet PACKAGE_ID: 0x205acdd30a8a741d3f7de74ed7517e526aa720e1d02789aeda87e53a0cf5dc99

Shared object IDs:
BOOK_ID (gas_insurance_marketplace::Book): 0xd49a7b1a8e205fd69aecc9fca7ebaa713258dbe7430e88145ab7b93c93715cdd

ORACLE_ID (gas_oracle::GasOracle): {oracle}
0x14011bd609a7905416bca0bfa056b269ffb1d91003cf04d2352db04fbfb580c6
