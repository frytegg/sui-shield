import { PropsWithChildren, useMemo } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SuiClientProvider, createNetworkConfig, WalletProvider } from '@mysten/dapp-kit';
import '@mysten/dapp-kit/dist/index.css';
import { RPC_URL } from '../sui/config';

const { networkConfig } = createNetworkConfig({
  custom: { url: RPC_URL },
});

export function AppProviders({ children }: PropsWithChildren) {
  const qc = useMemo(() => new QueryClient(), []);
  return (
    <QueryClientProvider client={qc}>
      <SuiClientProvider networks={networkConfig} defaultNetwork="custom">
        {/* Fournit le WalletContext pour ConnectButton et useCurrentAccount */}
        <WalletProvider autoConnect>{children}</WalletProvider>
      </SuiClientProvider>
    </QueryClientProvider>
  );
}
