// src/OffersMarketplace.tsx
/**
 * Marketplace — design conservé. Source de données = on-chain:
 * - useOffers(): view_offers + fallback événements + compteurs.
 * - Accept: txAcceptOffer avec Coin<SUI> pris via useSuiCoins(owner).
 *
 * Docs:
 * - PTB builder: https://docs.sui.io/guides/developer/sui-101/building-ptb :contentReference[oaicite:4]{index=4}
 * - useSignAndExecuteTransaction: https://sdk.mystenlabs.com/dapp-kit/wallet-hooks/useSignAndExecuteTransaction :contentReference[oaicite:5]{index=5}
 */
import { useMemo, useState } from 'react';
import { Button } from './ui/button';
import { Card } from './ui/card';
import { Input } from './ui/input';
import { Badge } from './ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from './ui/tabs';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from './ui/select';
import { ArrowLeft, Search, TrendingUp, Clock, Shield, Star } from 'lucide-react';
import { useSuiClient} from '@mysten/dapp-kit';
import { planFundExactSui, enactFundPlan } from '@/sui/tx/coin';
import { Transaction } from '@mysten/sui/transactions';

// Wallet + exécution
import { useCurrentAccount } from '@mysten/dapp-kit';
import { useExecuteTx } from '../hooks/useExecuteTx';
// TX builder
import { txAcceptOffer } from '../sui/tx/marketplace';
// Lecture on-chain
import { useOffers } from '../hooks/useOffers';
import { useSuiCoins } from '../hooks/useSuiCoins';

// Utilitaires affichage
const mistToSui = (m: bigint) => Number(m) / 1e9;
const fmtSui = (m: bigint) => `${mistToSui(m).toFixed(3)} SUI`;

interface OffersMarketplaceProps {
  onBack: () => void;
}

export function OffersMarketplace({ onBack }: OffersMarketplaceProps) {
  const [activeTab, setActiveTab] = useState<'one-time' | 'recurring'>('one-time');
  const [searchTerm, setSearchTerm] = useState('');
  const [sortBy, setSortBy] = useState<'reputation' | 'premium' | 'collateral'>('reputation');

  // Data on-chain
  const { data: offers, isLoading, counts } = useOffers(120);

  // Wallet + coins + executor
  const account = useCurrentAccount();
  const { pickAny } = useSuiCoins(account?.address);
  const { execute, isPending, error } = useExecuteTx();

  // Tri + filtre texte
  const filtered = useMemo(() => {
    const base = offers.filter((o) =>
      o.insurer.toLowerCase().includes(searchTerm.toLowerCase()) ||
      fmtSui(o.premiumMist).toLowerCase().includes(searchTerm.toLowerCase()),
    );

    const sorted = [...base].sort((a, b) => {
      if (sortBy === 'reputation') return 0; // réputation fictive non on-chain
      if (sortBy === 'premium') return Number(a.premiumMist - b.premiumMist);
      if (sortBy === 'collateral') return Number(b.collateralMist - a.collateralMist);
      return 0;
    });

    return {
      oneTime: sorted.filter((o) => !o.recurring),
      recurring: sorted.filter((o) => o.recurring),
    };
  }, [offers, searchTerm, sortBy]);

  const repColor = (r: number) =>
    r >= 98 ? 'text-green-500 bg-green-500/10'
    : r >= 95 ? 'text-blue-500 bg-blue-500/10'
    : r >= 90 ? 'text-yellow-500 bg-yellow-500/10'
    : 'text-red-500 bg-red-500/10';

async function handleSignContract(offer: { id: string; premiumMist: bigint }) {
  if (!account) { alert('Connectez votre wallet.'); return; }
  try {
    // 1) Plan hors-PTB
    const plan = await planFundExactSui(client, account.address, offer.premiumMist);

    // 2) Build PTB: enact plan → exact coin, puis accept_offer
    const build = () => {
      const tx = new Transaction();
      const premiumCoin = enactFundPlan(tx, plan, offer.premiumMist);
      return txAcceptOffer(
        { offerId: offer.id, premium: { coinArg: premiumCoin } },
        tx,
      );
    };

    const { digest } = await execute(build);
    alert(`Offer acceptée. Digest: ${digest}`);
  } catch (e: any) {
    console.error(e);
    alert(`Échec: ${e?.message ?? String(e)}`);
  }
}
  return (
    <div className="min-h-screen bg-gradient-main p-6">
      <div className="max-w-6xl mx-auto">
        <div className="flex items-center mb-8">
          <Button variant="outline" onClick={onBack} className="mr-4">
            <ArrowLeft className="h-4 w-4 mr-2" />
            Back
          </Button>
          <h1 className="text-3xl">Insurance Marketplace</h1>
        </div>

        <div className="flex flex-col md:flex-row gap-4 mb-6">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search by insurer address or premium..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10"
            />
          </div>

          <Select value={sortBy} onValueChange={(v) => setSortBy(v as any)}>
            <SelectTrigger className="w-[200px]">
              <SelectValue placeholder="Sort by" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="reputation">Reputation</SelectItem>
              <SelectItem value="premium">Premium (Low to High)</SelectItem>
              <SelectItem value="collateral">Collateral (High to Low)</SelectItem>
            </SelectContent>
          </Select>
        </div>

        <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as any)} className="w-full">
          <TabsList className="grid w-full grid-cols-2 mb-8">
            <TabsTrigger value="one-time" className="flex items-center">
              <Clock className="mr-2 h-4 w-4" />
              One-Time Offers ({filtered.oneTime.length})
            </TabsTrigger>
            <TabsTrigger value="recurring" className="flex items-center">
              <TrendingUp className="mr-2 h-4 w-4" />
              Recurring Offers ({filtered.recurring.length})
            </TabsTrigger>
          </TabsList>

          <TabsContent value="one-time" className="space-y-4">
            {isLoading && <div className="text-sm text-muted-foreground">Loading offers…</div>}
            {!isLoading && filtered.oneTime.map((offer) => (
              <Card key={offer.id} className="p-6 border-primary/10 hover:border-primary/30 transition-colors">
                <div className="flex justify-between items-start mb-4">
                  <div className="flex items-center space-x-3">
                    <div className="w-10 h-10 rounded-full bg-gradient-to-r from-primary to-accent flex items-center justify-center">
                      <Shield className="h-5 w-5 text-primary-foreground" />
                    </div>
                    <div>
                      <div className="flex items-center space-x-2">
                        <span className="font-mono text-sm">{offer.insurer}</span>
                        <Badge className={`${repColor(95)} border-0`}>
                          <Star className="h-3 w-3 mr-1" />
                          95%
                        </Badge>
                      </div>
                      <div className="text-sm text-muted-foreground">
                        {fmtSui(offer.collateralMist)} total covered • 0 active contracts
                      </div>
                    </div>
                  </div>

                  <Button onClick={() => handleSignContract(offer)} className="bg-primary hover:bg-primary/90" disabled={isPending}>
                    {isPending ? 'Signing…' : 'Sign Contract'}
                  </Button>
                </div>

                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div className="bg-card/50 p-3 rounded-lg">
                    <div className="text-sm text-muted-foreground">Premium</div>
                    <div className="text-lg font-medium text-green-500">{fmtSui(offer.premiumMist)}</div>
                  </div>
                  <div className="bg-card/50 p-3 rounded-lg">
                    <div className="text-sm text-muted-foreground">Coverage</div>
                    <div className="text-lg font-medium">{fmtSui(offer.collateralMist)}</div>
                  </div>
                  <div className="bg-card/50 p-3 rounded-lg">
                    <div className="text-sm text-muted-foreground">Strike Price</div>
                    <div className="text-lg font-medium">{fmtSui(offer.strikeMist)}</div>
                  </div>
                  <div className="bg-card/50 p-3 rounded-lg">
                    <div className="text-sm text-muted-foreground">Valid Until</div>
                    <div className="text-lg font-medium">{offer.validUntilMs ? new Date(offer.validUntilMs).toISOString().slice(0,10) : '—'}</div>
                  </div>
                </div>

                {error && <div className="text-xs text-red-500 mt-2">Erreur: {error}</div>}
              </Card>
            ))}
            {!isLoading && filtered.oneTime.length === 0 && (
              <div className="text-center py-12">
                <Search className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
                <h3 className="text-xl mb-2">No offers found</h3>
                <p className="text-muted-foreground">Try adjusting your search criteria or check back later for new offers.</p>
              </div>
            )}
          </TabsContent>

          <TabsContent value="recurring" className="space-y-4">
            {isLoading && <div className="text-sm text-muted-foreground">Loading offers…</div>}
            {!isLoading && filtered.recurring.map((offer) => (
              <Card key={offer.id} className="p-6 border-primary/10 hover:border-primary/30 transition-colors">
                <div className="flex justify-between items-start mb-4">
                  <div className="flex items-center space-x-3">
                    <div className="w-10 h-10 rounded-full bg-gradient-to-r from-primary to-accent flex items-center justify-center">
                      <TrendingUp className="h-5 w-5 text-primary-foreground" />
                    </div>
                    <div>
                      <div className="flex items-center space-x-2">
                        <span className="font-mono text-sm">{offer.insurer}</span>
                        <Badge className={`${repColor(95)} border-0`}>
                          <Star className="h-3 w-3 mr-1" />
                          95%
                        </Badge>
                      </div>
                      <div className="text-sm text-muted-foreground">
                        {fmtSui(offer.collateralMist)} total covered • 0 active contracts
                      </div>
                    </div>
                  </div>

                  <Button onClick={() => handleSignContract(offer.id)} className="bg-primary hover:bg-primary/90" disabled={isPending}>
                    {isPending ? 'Signing…' : 'Sign Contract'}
                  </Button>
                </div>

                <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
                  <div className="bg-card/50 p-3 rounded-lg">
                    <div className="text-sm text-muted-foreground">Premium</div>
                    <div className="text-lg font-medium text-green-500">{fmtSui(offer.premiumMist)}</div>
                  </div>
                  <div className="bg-card/50 p-3 rounded-lg">
                    <div className="text-sm text-muted-foreground">Coverage</div>
                    <div className="text-lg font-medium">{fmtSui(offer.collateralMist)}</div>
                  </div>
                  <div className="bg-card/50 p-3 rounded-lg">
                    <div className="text-sm text-muted-foreground">Strike Price</div>
                    <div className="text-lg font-medium">{fmtSui(offer.strikeMist)}</div>
                  </div>
                  <div className="bg-card/50 p-3 rounded-lg">
                    <div className="text-sm text-muted-foreground">Coverage Period</div>
                    <div className="text-sm font-medium">— to {offer.validUntilMs ? new Date(offer.validUntilMs).toISOString().slice(0,10) : '—'}</div>
                  </div>
                  <div className="bg-card/50 p-3 rounded-lg">
                    <div className="text-sm text-muted-foreground">Max Transactions</div>
                    <div className="text-lg font-medium">—</div>
                  </div>
                </div>

                {error && <div className="text-xs text-red-500 mt-2">Erreur: {error}</div>}
              </Card>
            ))}
            {!isLoading && filtered.recurring.length === 0 && (
              <div className="text-center py-12">
                <Search className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
                <h3 className="text-xl mb-2">No offers found</h3>
                <p className="text-muted-foreground">Try adjusting your search criteria or check back later for new offers.</p>
              </div>
            )}
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
}
