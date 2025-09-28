// src/components/InsuredQuestionnaire.tsx
import { useMemo, useState } from 'react';
import { Button } from './ui/button';
import { Card } from './ui/card';
import { Input } from './ui/input';
import { Label } from './ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from './ui/tabs';
import { ArrowLeft, Search, Loader2, Star } from 'lucide-react';

import { useCurrentAccount, useSuiClient } from '@mysten/dapp-kit';
import { useOffers } from '@/hooks/useOffers';
import { useExecuteTx } from '@/hooks/useExecuteTx';
import { planFundExactSui, enactFundPlan } from '@/sui/tx/coin';
import { txAcceptOffer } from '@/sui/tx/marketplace';
import { Transaction } from '@mysten/sui/transactions';

interface InsuredQuestionnaireProps { onBack: () => void; }

interface OneTimeForm {
  strikePrice: string;      // SUI
  premium: string;          // SUI
  coverageLimit: string;    // SUI
}
interface RecurringForm {
  strikePrice: string;      // SUI
  premium: string;          // SUI
  coverageLimit: string;    // SUI
  transactionCount: string;
}

// --- Utils SUI -> MIST (robuste)
const toMist = (s: string): bigint => {
  const t = (s ?? '').trim().replace(',', '.');
  if (!t) return 0n;
  if (/e/i.test(t)) {
    const n = Number(t);
    if (!isFinite(n) || n <= 0) return 0n;
    const mist = Math.floor(n * 1e9);
    return mist > 0 ? BigInt(mist) : 0n;
  }
  const [iRaw, fRaw = ''] = t.split('.');
  const i = (iRaw || '0').replace(/\D/g, '') || '0';
  const f = fRaw.replace(/\D/g, '').slice(0, 9).padEnd(9, '0');
  return BigInt(i + f);
};
const fmtSUI = (m: bigint) => `${(Number(m) / 1e9).toFixed(3)} SUI`;

// --- Parse "JJ:MM:AAAA" ou "JJ/MM/AAAA" ou "JJ-MM-AAAA" -> fin de journée UTC
function parseDateOnly(input: string): number | undefined {
  const s = (input ?? '').trim();
  if (!s) return undefined;
  const m = s.match(/^(\d{1,2})[\/:\-\.](\d{1,2})[\/:\-\.](\d{4})$/);
  if (!m) return undefined;
  const d = Number(m[1]);
  const M = Number(m[2]);
  const y = Number(m[3]);
  if (d < 1 || d > 31 || M < 1 || M > 12) return undefined;
  const ts = Date.UTC(y, M - 1, d, 23, 59, 59, 999); // deadline inclusif
  return Number.isFinite(ts) ? ts : undefined;
}

export function InsuredQuestionnaire({ onBack }: InsuredQuestionnaireProps) {
  const [activeTab, setActiveTab] = useState<'one-time' | 'recurring'>('one-time');
  const [isLoading, setIsLoading] = useState(false);
  const [showOffers, setShowOffers] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  // One-time: params + date limite texte
  const [oneTimeForm, setOneTimeForm] = useState<OneTimeForm>({
    strikePrice: '',
    premium: '',
    coverageLimit: '',
  });
  const [oneTimeDeadlineStr, setOneTimeDeadlineStr] = useState('');
  const oneTimeDeadlineMs = useMemo(() => parseDateOnly(oneTimeDeadlineStr), [oneTimeDeadlineStr]);

  // Recurring
  const [recurringForm, setRecurringForm] = useState<RecurringForm>({
    strikePrice: '',
    premium: '',
    coverageLimit: '',
    transactionCount: '',
  });
  const [recStartStr, setRecStartStr] = useState('');
  const [recEndStr, setRecEndStr] = useState('');
  const recStartTs = useMemo(() => parseDateOnly(recStartStr), [recStartStr]);
  const recEndTs = useMemo(() => parseDateOnly(recEndStr), [recEndStr]);

  // On-chain
  const { data: allOffers, isLoading: loadingOffers, refresh } = useOffers(200);
  const account = useCurrentAccount();
  const client = useSuiClient();
  const { execute, isPending, error } = useExecuteTx();

  // Résultats filtrés/scorés
  const results = useMemo(() => {
    const wants =
      activeTab === 'one-time'
        ? {
            strikeMist: toMist(oneTimeForm.strikePrice),
            premiumMaxMist: toMist(oneTimeForm.premium),
            covMinMist: toMist(oneTimeForm.coverageLimit),
            deadlineMs: oneTimeDeadlineMs,
            recurring: false,
          }
        : {
            strikeMist: toMist(recurringForm.strikePrice),
            premiumMaxMist: toMist(recurringForm.premium),
            covMinMist: toMist(recurringForm.coverageLimit),
            startMs: recStartTs,
            endMs: recEndTs,
            recurring: true,
          };

    return allOffers
      .filter((o) => o.recurring === wants.recurring)
      .filter((o) => {
        if ((wants as any).premiumMaxMist > 0n && o.premiumMist > (wants as any).premiumMaxMist) return false;
        if ((wants as any).covMinMist > 0n && o.collateralMist < (wants as any).covMinMist) return false;
        if ((wants as any).strikeMist > 0n && o.strikeMist > (wants as any).strikeMist) return false;

        if (!wants.recurring) {
          // one-time: la date limite saisie doit être <= valid_until_ms
          if ((wants as any).deadlineMs && o.validUntilMs) {
            if ((wants as any).deadlineMs > o.validUntilMs) return false;
          }
        } else {
          if ((wants as any).endMs && o.validUntilMs) {
            if (o.validUntilMs < (wants as any).endMs) return false;
          }
        }
        return true;
      })
      .map((o) => {
        const ds = Math.abs(Number(o.strikeMist) - Number((wants as any).strikeMist ?? 0n)) / 1e9;
        const dp = Number(o.premiumMist) / 1e9;
        const cov = Number(o.collateralMist) / 1e9;
        const score = ds * 2 + dp - Math.min(cov, 100);
        return { offer: o, score };
      })
      .sort((a, b) => a.score - b.score)
      .map((x) => x.offer);
  }, [allOffers, activeTab, oneTimeForm, recurringForm, oneTimeDeadlineMs, recStartTs, recEndTs]);

  // Recherche
  const handleSearch = async () => {
    setIsLoading(true);
    setLoadError(null);
    try {
      if (recStartTs && recEndTs && recStartTs > recEndTs) {
        setRecStartStr((s) => {
          const t = recEndStr;
          setRecEndStr(s);
          return t;
        });
      }
      await refresh().catch((e: any) => {
        console.error('useOffers.refresh error:', e);
        setLoadError('Lecture on-chain indisponible. Réessayez ou ouvrez Policies/Marketplace.');
      });
      setShowOffers(true);
    } finally {
      setIsLoading(false);
    }
  };

  // Signature
  async function handleSignContract(offerId: string, premiumMist: bigint) {
    if (!account) { alert('Connectez votre wallet.'); return; }
    try {
      const plan = await planFundExactSui(client, account.address, premiumMist);
      const build = () => {
        const tx = new Transaction();
        const premiumCoin = enactFundPlan(tx, plan, premiumMist);
        return txAcceptOffer({ offerId, premium: { coinArg: premiumCoin } }, tx);
      };
      const { digest } = await execute(build);
      alert(`Offer acceptée. Digest: ${digest}`);
    } catch (e: any) {
      console.error(e);
      alert(`Échec: ${e?.message ?? String(e)}`);
    }
  }

  // Résultats
  if (showOffers) {
    return (
      <div className="min-h-screen bg-gradient-main p-6">
        <div className="max-w-4xl mx-auto">
          <div className="flex items-center mb-8">
            <Button variant="outline" onClick={() => setShowOffers(false)} className="mr-4">
              <ArrowLeft className="h-4 w-4 mr-2" />
              Back to Search
            </Button>
            <h1 className="text-3xl">Available Offers</h1>
          </div>

          {loadingOffers && <div className="text-sm text-muted-foreground mb-4">Loading on-chain offers…</div>}
          {loadError && <div className="text-xs text-red-500 mb-4">{loadError}</div>}

          <div className="space-y-4">
            {results.map((offer) => (
              <Card key={offer.id} className="p-6 border-primary/10">
                <div className="flex justify-between items-start">
                  <div className="space-y-3">
                    <div className="flex items-center space-x-4">
                      <span className="text-sm text-muted-foreground">Insurer:</span>
                      <span className="font-mono">{offer.insurer}</span>
                      <span className="bg-blue-500/10 text-blue-500 px-2 py-1 rounded text-sm inline-flex items-center">
                        <Star className="w-3 h-3 mr-1" />
                        95% reputation
                      </span>
                    </div>

                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                      <div>
                        <span className="text-muted-foreground">Premium:</span>
                        <div className="font-medium">{fmtSUI(offer.premiumMist)}</div>
                      </div>
                      <div>
                        <span className="text-muted-foreground">Coverage:</span>
                        <div className="font-medium">{fmtSUI(offer.collateralMist)}</div>
                      </div>
                      <div>
                        <span className="text-muted-foreground">Strike:</span>
                        <div className="font-medium">{fmtSUI(offer.strikeMist)}</div>
                      </div>
                      <div>
                        <span className="text-muted-foreground">Valid Until:</span>
                        <div className="font-medium">
                          {offer.validUntilMs ? new Date(offer.validUntilMs).toISOString().slice(0, 10) : '—'}
                        </div>
                      </div>
                    </div>
                  </div>

                  <Button
                    onClick={() => handleSignContract(offer.id, offer.premiumMist)}
                    className="bg-primary hover:bg-primary/90"
                    disabled={isPending}
                  >
                    {isPending ? 'Signing…' : 'Sign Contract'}
                  </Button>
                </div>

                {error && <div className="text-xs text-red-500 mt-2">Erreur: {error}</div>}
              </Card>
            ))}
          </div>

          {!loadingOffers && results.length === 0 && (
            <div className="text-sm text-muted-foreground mt-6">
              No matching offers. Adjust your filters and search again.
            </div>
          )}
        </div>
      </div>
    );
  }

  // Formulaire
  return (
    <div className="min-h-screen bg-gradient-main p-6">
      <div className="max-w-2xl mx-auto">
        <div className="flex items-center mb-8">
          <Button variant="outline" onClick={onBack} className="mr-4">
            <ArrowLeft className="h-4 w-4 mr-2" />
            Back
          </Button>
          <h1 className="text-3xl">Get Insurance Coverage</h1>
        </div>

        <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as any)} className="w-full">
          <TabsList className="grid w-full grid-cols-2 mb-8">
            <TabsTrigger value="one-time">One-Time Insurance</TabsTrigger>
            <TabsTrigger value="recurring">Recurring Insurance</TabsTrigger>
          </TabsList>

          {/* One-time */}
          <TabsContent value="one-time" className="space-y-6">
            <Card className="p-6 border-primary/10">
              <h3 className="text-xl mb-6">One-Time Coverage Details</h3>

              <div className="space-y-6">
                <div>
                  <Label htmlFor="strike-price">Strike Threshold (SUI)</Label>
                  <Input
                    id="strike-price"
                    type="text"
                    inputMode="decimal"
                    placeholder="0.001000000"
                    value={oneTimeForm.strikePrice}
                    onChange={(e) => setOneTimeForm({ ...oneTimeForm, strikePrice: e.target.value })}
                    className="mt-2"
                  />
                  <p className="text-sm text-muted-foreground mt-1">1 SUI = 1e9 MIST.</p>
                </div>

                <div>
                  <Label htmlFor="premium">Maximum Premium (SUI)</Label>
                  <Input
                    id="premium"
                    type="text"
                    inputMode="decimal"
                    placeholder="0.100000000"
                    value={oneTimeForm.premium}
                    onChange={(e) => setOneTimeForm({ ...oneTimeForm, premium: e.target.value })}
                    className="mt-2"
                  />
                </div>

                <div>
                  <Label htmlFor="coverage-limit">Coverage Limit (SUI)</Label>
                  <Input
                    id="coverage-limit"
                    type="text"
                    inputMode="decimal"
                    placeholder="10.000000000"
                    value={oneTimeForm.coverageLimit}
                    onChange={(e) => setOneTimeForm({ ...oneTimeForm, coverageLimit: e.target.value })}
                    className="mt-2"
                  />
                </div>

                <div>
                  <Label htmlFor="tx-deadline">Transaction deadline (JJ:MM:AAAA)</Label>
                  <Input
                    id="tx-deadline"
                    type="text"
                    inputMode="numeric"
                    placeholder="31:12:2025"
                    value={oneTimeDeadlineStr}
                    onChange={(e) => setOneTimeDeadlineStr(e.target.value)}
                    className="mt-2"
                  />
                  {oneTimeDeadlineStr && oneTimeDeadlineMs === undefined && (
                    <p className="text-xs text-red-500 mt-1">Format invalide. Exemple: 31:12:2025</p>
                  )}
                </div>
              </div>
            </Card>
          </TabsContent>

          {/* Recurring */}
          <TabsContent value="recurring" className="space-y-6">
            <Card className="p-6 border-primary/10">
              <h3 className="text-xl mb-6">Recurring Coverage Details</h3>

              <div className="space-y-6">
                <div>
                  <Label htmlFor="recurring-strike-price">Strike Threshold (SUI)</Label>
                  <Input
                    id="recurring-strike-price"
                    type="text"
                    inputMode="decimal"
                    placeholder="0.001000000"
                    value={recurringForm.strikePrice}
                    onChange={(e) => setRecurringForm({ ...recurringForm, strikePrice: e.target.value })}
                    className="mt-2"
                  />
                </div>

                <div>
                  <Label htmlFor="recurring-premium">Maximum Premium (SUI)</Label>
                  <Input
                    id="recurring-premium"
                    type="text"
                    inputMode="decimal"
                    placeholder="0.500000000"
                    value={recurringForm.premium}
                    onChange={(e) => setRecurringForm({ ...recurringForm, premium: e.target.value })}
                    className="mt-2"
                  />
                </div>

                <div>
                  <Label htmlFor="recurring-coverage-limit">Coverage Limit (SUI)</Label>
                  <Input
                    id="recurring-coverage-limit"
                    type="text"
                    inputMode="decimal"
                    placeholder="50.000000000"
                    value={recurringForm.coverageLimit}
                    onChange={(e) => setRecurringForm({ ...recurringForm, coverageLimit: e.target.value })}
                    className="mt-2"
                  />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <Label htmlFor="start-date">Start (JJ:MM:AAAA)</Label>
                    <Input
                      id="start-date"
                      type="text"
                      inputMode="numeric"
                      placeholder="01:01:2026"
                      value={recStartStr}
                      onChange={(e) => setRecStartStr(e.target.value)}
                      className="mt-2"
                    />
                    {recStartStr && recStartTs === undefined && (
                      <p className="text-xs text-red-500 mt-1">Format invalide. Exemple: 01:01:2026</p>
                    )}
                  </div>

                  <div>
                    <Label htmlFor="end-date">End (JJ:MM:AAAA)</Label>
                    <Input
                      id="end-date"
                      type="text"
                      inputMode="numeric"
                      placeholder="31:01:2026"
                      value={recEndStr}
                      onChange={(e) => setRecEndStr(e.target.value)}
                      className="mt-2"
                    />
                    {recEndStr && recEndTs === undefined && (
                      <p className="text-xs text-red-500 mt-1">Format invalide. Exemple: 31:01:2026</p>
                    )}
                    {recStartTs && recEndTs && recStartTs > recEndTs && (
                      <p className="text-xs text-red-500 mt-1">La date de début doit précéder la date de fin.</p>
                    )}
                  </div>
                </div>

                <div>
                  <Label htmlFor="transaction-count">Expected Transaction Count</Label>
                  <Input
                    id="transaction-count"
                    type="number"
                    inputMode="numeric"
                    placeholder="20"
                    value={recurringForm.transactionCount}
                    onChange={(e) => setRecurringForm({ ...recurringForm, transactionCount: e.target.value })}
                    className="mt-2"
                  />
                </div>
              </div>
            </Card>
          </TabsContent>
        </Tabs>

        <div className="flex justify-center mt-8">
          <Button
            onClick={handleSearch}
            disabled={
              isLoading || loadingOffers ||
              (activeTab === 'one-time' && oneTimeDeadlineStr !== '' && oneTimeDeadlineMs === undefined) ||
              (activeTab === 'recurring' && (
                (recStartStr !== '' && recStartTs === undefined) ||
                (recEndStr !== '' && recEndTs === undefined) ||
                (recStartTs && recEndTs && recStartTs > recEndTs)
              ))
            }
            className="px-12 py-3 bg-primary hover:bg-primary/90"
            size="lg"
          >
            {(isLoading || loadingOffers) ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Searching...
              </>
            ) : (
              <>
                <Search className="mr-2 h-4 w-4" />
                Search for Offers
              </>
            )}
          </Button>
        </div>
      </div>
    </div>
  );
}
