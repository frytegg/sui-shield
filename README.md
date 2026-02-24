# SuiShield

Decentralized gas fee insurance marketplace on the Sui blockchain. Users protect their transactions from unpredictable gas costs by purchasing coverage from on-chain insurers.

Built at the **EPFL SUI 2025 Hackathon**.

## Tech Stack

- **Smart Contracts** - Sui Move (marketplace, insurance policies, oracle)
- **Frontend** - React 18, TypeScript, Vite, Tailwind CSS
- **Sui SDK** - @mysten/dapp-kit, @mysten/sui
- **UI** - Radix UI, Recharts, Lucide icons

## How It Works

1. **Insurers** post coverage offers with configurable premiums, strike prices, and collateral
2. **Users** browse the marketplace and accept offers to create on-chain policies
3. An **oracle system** records actual gas usage per transaction
4. **Settlement** automatically pays out if gas exceeds the insured strike price

Supports both one-time and recurring (window) policies.

## Getting Started

```bash
# Frontend
cd web
npm install
npm run dev        # http://localhost:3000

# Smart contracts
cd move/gas_insurance_mvp
sui move build
sui move test
```

## Project Structure

```
move/gas_insurance_mvp/sources/
  gas_insurance.move            # Policy struct & settlement logic
  gas_insurance_marketplace.move # Offers, requests, acceptance flows
  gas_oracle.move               # Gas observation oracle

web/src/
  components/     # React UI (marketplace, questionnaire, oracle)
  hooks/          # useExecuteTx, useOffers, usePolicies
  sui/            # Chain config, read queries, transaction builders
```

## Deployed Contracts (Sui Testnet)

- **Package**: `0x205acdd...cf5dc99`
- **Marketplace Book**: `0xd49a7b1...3715cdd`
- **Oracle**: `0x14011bd...fb580c6`
