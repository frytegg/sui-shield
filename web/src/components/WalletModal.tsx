// src/components/WalletModal.tsx
import { Dialog, DialogContent, DialogHeader, DialogTitle } from './ui/dialog';
import { Button } from './ui/button';
import { ConnectButton, useCurrentAccount } from '@mysten/dapp-kit';
import { useEffect } from 'react';

interface WalletModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConnected: () => void;
}

export function WalletModal({ isOpen, onClose, onConnected }: WalletModalProps) {
  const wallet = useCurrentAccount();

  useEffect(() => {
    if (wallet?.address) onConnected();
  }, [wallet?.address, onConnected]);

  if (!isOpen) return null;

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-md bg-card border-primary/20">
        <DialogHeader>
          <DialogTitle className="text-center text-2xl">Connect</DialogTitle>
        </DialogHeader>

        {/* 2 boutons de même taille, espacés */}
        <div className="grid grid-cols-1 gap-3">
          <div className="w-full">
            <ConnectButton
              connectText="Connect Wallet"
              className="w-full h-11 justify-center"
              style={{ width: '100%' }}
            />
          </div>
        </div>

        {wallet?.address && (
          <div className="mt-2 text-xs text-muted-foreground text-center">
            Connected: <span className="font-mono">{wallet?.address}</span>
          </div>
        )}

        <div className="mt-3 flex justify-center">
          <Button variant="ghost" onClick={onClose}>Close</Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
