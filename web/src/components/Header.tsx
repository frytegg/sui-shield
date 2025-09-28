// src/components/Header.tsx
import { Menu, X } from 'lucide-react';
import { Button } from './ui/button';
import { Logo } from './Logo';
import { useState, MouseEvent } from 'react';
import { useCurrentAccount, useDisconnectWallet } from '@mysten/dapp-kit';

interface HeaderProps {
  onWalletConnect?: () => void; // ouvre le modal
  onWalletDisconnect?: () => void; // callback optionnel côté app
  isWalletConnected?: boolean; // optionnel; si absent on lit dapp-kit
  showNavigation?: boolean;
  onNavigateToMarketplace?: () => void;
  walletAddress?: string; // optionnel; si absent on lit dapp-kit
}

export function Header({
  onWalletConnect,
  onWalletDisconnect,
  isWalletConnected,
  showNavigation = true,
  onNavigateToMarketplace,
  walletAddress,
}: HeaderProps) {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  // État réel du wallet via dapp-kit
  const account = useCurrentAccount();
  const { mutate: disconnect } = useDisconnectWallet();

  const connected = (isWalletConnected ?? !!account?.address);
  const address = account?.address ?? walletAddress;

  const formatAddress = (addr?: string) =>
    addr && addr.length > 10 ? `${addr.slice(0, 6)}...${addr.slice(-4)}` : addr ?? '';

  const scrollToSection = (sectionId: string) => {
    const el = document.getElementById(sectionId);
    if (el) el.scrollIntoView({ behavior: 'smooth' });
    setMobileMenuOpen(false);
  };

  const handleMarketplaceClick = (e: MouseEvent<HTMLButtonElement>) => {
    e.preventDefault();
    onNavigateToMarketplace?.();
    setMobileMenuOpen(false);
  };

  const handleDisconnect = () => {
    // Déconnecte le portefeuille au niveau dapp-kit
    disconnect();
    // Callback app si fourni
    onWalletDisconnect?.();
    setMobileMenuOpen(false);
  };

  const handleConnect = () => {
    onWalletConnect?.(); // ouvre le modal de connexion
    setMobileMenuOpen(false);
  };

  return (
    <header className="fixed top-0 left-0 right-0 z-50 px-4 pt-4">
      <div className="max-w-4xl mx-auto bg-background/70 backdrop-blur-xl border border-border/50 rounded-2xl shadow-medium px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <Logo />

          {/* Desktop Navigation */}
          {showNavigation && (
            <nav className="hidden md:flex items-center space-x-8">
              <button
                onClick={() => scrollToSection('insurance-types')}
                className="text-muted-foreground hover:text-foreground transition-colors"
              >
                Features
              </button>
              <button
                onClick={() => scrollToSection('how-it-works')}
                className="text-muted-foreground hover:text-foreground transition-colors"
              >
                How it Works
              </button>
              <button
                onClick={handleMarketplaceClick}
                className="text-muted-foreground hover:text-foreground transition-colors"
              >
                Marketplace
              </button>
            </nav>
          )}

          {/* Right side */}
          <div className="flex items-center space-x-4">
            {/* Wallet Status */}
            {connected ? (
              <div className="hidden sm:flex items-center space-x-2">
                <div className="flex items-center space-x-2 px-3 py-2 bg-muted rounded-lg">
                  <div className="w-2 h-2 bg-green-500 rounded-full" />
                  <span className="font-mono text-sm text-muted-foreground">
                    {formatAddress(address)}
                  </span>
                </div>
                <Button
                  type="button"
                  onClick={handleDisconnect}
                  className="bg-red-600 hover:bg-red-700 text-white px-3 py-2 rounded-lg"
                >
                  Disconnect
                </Button>
              </div>
            ) : (
              <Button
                type="button"
                onClick={handleConnect}
                className="flex items-center bg-blue hover:bg-blue-dark text-blue-foreground px-3 py-2 rounded-lg"
              >
                Connect Wallet
              </Button>
            )}

            {/* Mobile menu button */}
            {showNavigation && (
              <button
                onClick={() => setMobileMenuOpen((v) => !v)}
                className="md:hidden p-2 text-muted-foreground hover:text-foreground"
                aria-label="Toggle menu"
              >
                {mobileMenuOpen ? <X size={20} /> : <Menu size={20} />}
              </button>
            )}
          </div>
        </div>

        {/* Mobile Navigation */}
        {showNavigation && mobileMenuOpen && (
          <div className="md:hidden border-t border-border/50 bg-background/80 backdrop-blur-xl rounded-b-2xl">
            <nav className="flex flex-col space-y-4 px-4 py-6">
              <button
                onClick={() => scrollToSection('insurance-types')}
                className="text-muted-foreground hover:text-foreground transition-colors text-left"
              >
                Features
              </button>
              <button
                onClick={() => scrollToSection('how-it-works')}
                className="text-muted-foreground hover:text-foreground transition-colors text-left"
              >
                How it Works
              </button>
              <button
                onClick={handleMarketplaceClick}
                className="text-muted-foreground hover:text-foreground transition-colors text-left"
              >
                Marketplace
              </button>
              <a
                href="#docs"
                onClick={() => setMobileMenuOpen(false)}
                className="text-muted-foreground hover:text-foreground transition-colors"
              >
                Docs
              </a>

              {!connected ? (
                <Button
                  type="button"
                  onClick={handleConnect}
                  className="bg-blue hover:bg-blue-dark text-blue-foreground w-full"
                >
                  Connect Wallet
                </Button>
              ) : (
                <Button
                  type="button"
                  onClick={handleDisconnect}
                  className="bg-red-600 hover:bg-red-700 text-white w-full"
                >
                  Disconnect
                </Button>
              )}
            </nav>
          </div>
        )}
      </div>
    </header>
  );
}
