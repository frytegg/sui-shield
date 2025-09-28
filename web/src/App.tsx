// src/App.tsx
import { useCallback, useMemo, useState } from 'react';
import { LandingPage } from './components/LandingPage';
import { WalletModal } from './components/WalletModal';
import { InsuredQuestionnaire } from './components/InsuredQuestionnaire';
import { InsurerOffers } from './components/InsurerOffers';
import { OffersMarketplace } from './components/OffersMarketplace';
import { PolicyList } from './components/PolicyList';
import OracleSubmitForm from './components/OracleSubmitForm';
import OracleAdmin from './components/OracleAdmin';
import { RoleModal } from './components/RoleModal';

import { useCurrentAccount } from '@mysten/dapp-kit';
import { createPortal } from 'react-dom';

// Boutons d’accès rapide — forçage d’affichage, z-index maximal, fallback sans Portal
function AdminButtons(props: {
  onPolicies: () => void;
  onOracle: () => void;
  onOracleAdmin: () => void;
}) {
  const content = (
    <div
      style={{
        position: 'fixed',
        bottom: 16,
        right: 16,
        zIndex: 2147483647, // max int pour passer devant tout
        display: 'flex',
        gap: 8,
        pointerEvents: 'auto',
      }}
    >
      <button
        style={{ padding: '8px 12px', fontSize: 12, borderRadius: 6, background: '#222', color: '#fff', border: '1px solid #444' }}
        onClick={props.onPolicies}
      >
        Policies
      </button>
      <button
        style={{ padding: '8px 12px', fontSize: 12, borderRadius: 6, background: '#222', color: '#fff', border: '1px solid #444' }}
        onClick={props.onOracle}
      >
        Oracle
      </button>
      <button
        style={{ padding: '8px 12px', fontSize: 12, borderRadius: 6, background: '#222', color: '#fff', border: '1px solid #444' }}
        onClick={props.onOracleAdmin}
      >
        Oracle Admin
      </button>
    </div>
  );

  // Si document.body est dispo, utilise Portal. Sinon, rend inline.
  const target = typeof document !== 'undefined' ? document.body : null;
  return target ? createPortal(content, target) : content;
}


// + Ajout de la vue 'oracleAdmin'
type View =
  | 'landing'
  | 'questionnaire'
  | 'insurer'
  | 'marketplace'
  | 'policies'
  | 'oracle'
  | 'oracleAdmin';

export default function App() {
  const [currentView, setCurrentView] = useState<View>('landing');
  const [showWalletModal, setShowWalletModal] = useState(false);
  const [showRoleModal, setShowRoleModal] = useState(false);
  const [openRoleAfterConnect, setOpenRoleAfterConnect] = useState(false);

  const wallet = useCurrentAccount();
  const isConnected = useMemo(() => !!wallet?.address, [wallet?.address]);

  // Déconnexion simple
  const handleWalletDisconnect = () => {
    try {
      // @ts-ignore
      if (wallet && typeof (wallet as any).disconnect === 'function') {
        // @ts-ignore
        (wallet as any).disconnect();
        return;
      }
    } catch (e) {
      console.warn('Wallet disconnect attempt failed', e);
    }
    window.location.reload();
  };

  // Ouvre la modale de connexion
  const handleWalletConnect = () => setShowWalletModal(true);

  // “Get started” => RoleModal si connecté, sinon connexion puis RoleModal
  const handleGetStarted = () => {
    if (isConnected) setShowRoleModal(true);
    else {
      setOpenRoleAfterConnect(true);
      setShowWalletModal(true);
    }
  };

  // Callback depuis WalletModal quand un compte est détecté
  const handleConnected = useCallback(() => {
    setShowWalletModal(false);
    if (openRoleAfterConnect) {
      setShowRoleModal(true);
      setOpenRoleAfterConnect(false);
    }
  }, [openRoleAfterConnect]);

  // Sélection d’un rôle
  const handleSelectRole = (role: 'insured' | 'insurer' | 'marketplace') => {
    setShowRoleModal(false);
    if (role === 'insured') setCurrentView('questionnaire');
    if (role === 'insurer') setCurrentView('insurer');
    if (role === 'marketplace') setCurrentView('marketplace');
  };

  const handleBackToLanding = () => setCurrentView('landing');

  return (
    <div className="min-h-screen bg-background">
      {currentView === 'landing' && (
        <LandingPage
          onWalletConnect={handleWalletConnect}
          onNavigateToMarketplace={() => setCurrentView('marketplace')}
          isWalletConnected={isConnected}
          onBackToLanding={handleBackToLanding}
          onGetStarted={handleGetStarted}
          onWalletDisconnect={handleWalletDisconnect}
        />
      )}

      {currentView === 'questionnaire' && (
        <InsuredQuestionnaire onBack={handleBackToLanding} />
      )}
      {currentView === 'insurer' && (
        <InsurerOffers onBack={handleBackToLanding} />
      )}
      {currentView === 'marketplace' && (
        <OffersMarketplace onBack={handleBackToLanding} />
      )}

      {/* Page Policies */}
      {currentView === 'policies' && (
        <div className="max-w-6xl mx-auto p-6">
          <PolicyList />
        </div>
      )}

      {/* Page Oracle (soumission uniquement) */}
      {currentView === 'oracle' && (
        <div className="max-w-2xl mx-auto p-6">
          <OracleSubmitForm />
        </div>
      )}

      {/* Page Oracle Admin (séparée) */}
      {currentView === 'oracleAdmin' && (
        <div className="max-w-2xl mx-auto p-6">
          <OracleAdmin />
        </div>
      )}

      {/* Connexion wallet uniquement */}
      <WalletModal
        isOpen={showWalletModal}
        onClose={() => setShowWalletModal(false)}
        onConnected={handleConnected}
      />

      {/* Popup rôles */}
      <RoleModal
        open={showRoleModal}
        onOpenChange={setShowRoleModal}
        onSelect={handleSelectRole}
      />

      {/* Boutons flottants d’accès rapide */}
      <AdminButtons
        onPolicies={() => setCurrentView('policies')}
        onOracle={() => setCurrentView('oracle')}
        onOracleAdmin={() => setCurrentView('oracleAdmin')}
      />
    </div>
  );
}
