import { useState } from 'react';
import { Button } from './ui/button';
import { Card } from './ui/card';
import { Input } from './ui/input';
import { Label } from './ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from './ui/tabs';
import { ArrowLeft, Wallet, CheckCircle } from 'lucide-react';

import { Transaction } from '@mysten/sui/transactions';
import { useCurrentAccount, useSuiClient } from '@mysten/dapp-kit';
import { useExecuteTx } from '../hooks/useExecuteTx';
import { txPostOffer } from '../sui/tx/marketplace';

interface InsurerOffersProps { onBack: () => void; }

interface OneTimeOffer {
  premium: string;      // SUI
  collateral: string;   // SUI
  strikePrice: string;  // SUI
  validUntilStr: string; // "JJ:MM:AAAA"
}

interface RecurringOffer {
  premium: string;         // SUI
  collateral: string;      // SUI
  strikePrice: string;     // SUI
  validFromStr: string;    // "JJ:MM:AAAA"
  validUntilStr: string;   // "JJ:MM:AAAA"
  maxTransactions: string;
}

/** SUI -> MIST, robuste */
function toMist(s: string): bigint {
  const t = (s ?? '').trim().replace(',', '.');
  if (!t) return 0n;
  if (/e/i.test(t)) {
    const n = Number(t);
    if (!isFinite(n) || n <= 0) return 0n;
    const mist = Math.floor(n * 1e9);
    return mist > 0 ? BigInt(mist) : 0n;
  }
  const [int = '0', frac = ''] = t.split('.');
  const i = int.replace(/\D/g, '') || '0';
  const f = frac.replace(/\D/g, '').slice(0, 9).padEnd(9, '0');
  return BigInt(i + f);
}

/** Parse "JJ:MM:AAAA" | "JJ/MM/AAAA" | "JJ-MM-AAAA" -> {y,M,d} ou null */
function parseDateParts(input: string): { y: number; M: number; d: number } | null {
  const s = (input ?? '').trim();
  if (!s) return null;
  const m = s.match(/^(\d{1,2})[\/:\-\.](\d{1,2})[\/:\-\.](\d{4})$/);
  if (!m) return null;
  const d = Number(m[1]), M = Number(m[2]), y = Number(m[3]);
  if (d < 1 || d > 31 || M < 1 || M > 12) return null;
  return { y, M, d };
}
const startOfDayUTC = (p: { y: number; M: number; d: number }) =>
  Date.UTC(p.y, p.M - 1, p.d, 0, 0, 0, 0);
const endOfDayUTC = (p: { y: number; M: number; d: number }) =>
  Date.UTC(p.y, p.M - 1, p.d, 23, 59, 59, 999);

const GAS_BUDGET = 50_000_000; // 0.05 SUI

export function InsurerOffers({ onBack }: InsurerOffersProps) {
  const [activeTab, setActiveTab] = useState<'one-time' | 'recurring'>('one-time');
  const [isSubmitted, setIsSubmitted] = useState(false);
  const [lastDigest, setLastDigest] = useState<string | null>(null);

  const [oneTimeOffer, setOneTimeOffer] = useState<OneTimeOffer>({
    premium: '',
    collateral: '',
    strikePrice: '',
    validUntilStr: '',
  });

  const [recurringOffer, setRecurringOffer] = useState<RecurringOffer>({
    premium: '',
    collateral: '',
    strikePrice: '',
    validFromStr: '',
    validUntilStr: '',
    maxTransactions: '',
  });

  const account = useCurrentAccount();
  const client = useSuiClient(); // gardé si besoin ailleurs
  const { execute, isPending, error } = useExecuteTx();

  // Validation
  const oneUntilParts = parseDateParts(oneTimeOffer.validUntilStr);
  const recFromParts = parseDateParts(recurringOffer.validFromStr);
  const recUntilParts = parseDateParts(recurringOffer.validUntilStr);

  const oneValid =
    !!oneTimeOffer.premium && !!oneTimeOffer.collateral && !!oneTimeOffer.strikePrice && !!oneUntilParts;

  const recValid =
    !!recurringOffer.premium &&
    !!recurringOffer.collateral &&
    !!recurringOffer.strikePrice &&
    !!recFromParts &&
    !!recUntilParts &&
    (recurringOffer.maxTransactions || '0') !== '' &&
    (!recFromParts || !recUntilParts || startOfDayUTC(recFromParts) <= endOfDayUTC(recUntilParts));

  async function handleSubmitOffer() {
    if (!account) {
      alert('Connectez votre wallet.');
      return;
    }

    try {
      if (activeTab === 'one-time') {
        const premiumMist = toMist(oneTimeOffer.premium);
        const collateralMist = toMist(oneTimeOffer.collateral);
        const strikeMist = toMist(oneTimeOffer.strikePrice);
        const validUntilMs = oneUntilParts ? endOfDayUTC(oneUntilParts) : 0;

        if (collateralMist <= 0n) throw new Error('Collateral doit être > 0');

        const tx = new Transaction();
        tx.setGasBudget(GAS_BUDGET);

        // Collatéral directement scindé depuis la pièce de gas choisie par le wallet
        const collateralCoin = tx.splitCoins(tx.gas, [tx.pure.u64(collateralMist)]);

        txPostOffer(
          {
            premiumMist,
            strikeMist,
            validUntilMs,
            recurring: false,
            maxTransactions: 1,
            validFromMs: 0,
            collateralMist,
            collateral: { coinArg: collateralCoin },
          },
          tx,
        );

        const { digest } = await execute(() => tx);
        setLastDigest(digest);
        setIsSubmitted(true);
      } else {
        const premiumMist = toMist(recurringOffer.premium);
        const collateralMist = toMist(recurringOffer.collateral);
        const strikeMist = toMist(recurringOffer.strikePrice);
        const validFromMs = recFromParts ? startOfDayUTC(recFromParts) : 0;
        const validUntilMs = recUntilParts ? endOfDayUTC(recUntilParts) : 0;
        const maxTransactions = Number(recurringOffer.maxTransactions || '0');

        if (validFromMs && validUntilMs && validFromMs > validUntilMs) {
          alert('La date de début doit précéder la date de fin.');
          return;
        }
        if (collateralMist <= 0n) throw new Error('Collateral doit être > 0');

        const tx = new Transaction();
        tx.setGasBudget(GAS_BUDGET);

        const collateralCoin = tx.splitCoins(tx.gas, [tx.pure.u64(collateralMist)]);

        txPostOffer(
          {
            premiumMist,
            strikeMist,
            validUntilMs,
            recurring: true,
            maxTransactions,
            validFromMs,
            collateralMist,
            collateral: { coinArg: collateralCoin },
          },
          tx,
        );

        const { digest } = await execute(() => tx);
        setLastDigest(digest);
        setIsSubmitted(true);
      }
    } catch (e: any) {
      console.error(e);
      alert(`Échec: ${e?.message ?? String(e)}`);
    }
  }

  if (isSubmitted) {
    return (
      <div className="min-h-screen bg-gradient-main flex items-center justify-center p-6">
        <Card className="p-8 text-center max-w-md border-green-500/20">
          <CheckCircle className="h-16 w-16 text-green-500 mx-auto mb-4" />
          <h2 className="text-2xl mb-2">Offer Submitted Successfully!</h2>
          <p className="text-muted-foreground mb-6">Your insurance offer has been posted to the marketplace.</p>
          {lastDigest && (
            <p className="text-sm mb-4">
              <a
                className="underline"
                href={`https://suiscan.xyz/testnet/tx/${lastDigest}`}
                target="_blank"
                rel="noreferrer"
              >
                View on SuiScan (testnet)
              </a>
            </p>
          )}
          <div className="flex gap-2 justify-center">
            <Button onClick={onBack} variant="outline">Back to Dashboard</Button>
          </div>
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-main p-6">
      <div className="max-w-2xl mx-auto">
        <div className="flex items-center mb-8">
          <Button variant="outline" onClick={onBack} className="mr-4">
            <ArrowLeft className="h-4 w-4 mr-2" /> Back
          </Button>
          <h1 className="text-3xl">Create Insurance Offer</h1>
        </div>

        <div className="mb-6 p-4 bg-blue-500/10 border border-blue-500/20 rounded-lg">
          <h3 className="text-lg mb-2">How Insurer Offers Work</h3>
          <p className="text-sm text-muted-foreground">
            As an insurer, you provide liquidity by offering gas fee insurance. Set your premium,
            collateral, and strike price. When users accept, you earn the premium and cover above strike.
          </p>
        </div>

        <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as any)} className="w-full">
          <TabsList className="grid w-full grid-cols-2 mb-8">
            <TabsTrigger value="one-time">One-Time Offer</TabsTrigger>
            <TabsTrigger value="recurring">Recurring Offer</TabsTrigger>
          </TabsList>

            {/* One-time */}
            <TabsContent value="one-time" className="space-y-6">
              <Card className="p-6 border-primary/10">
                <h3 className="text-xl mb-6">One-Time Insurance Offer</h3>

                <div className="space-y-6">
                  <div>
                    <Label htmlFor="one-time-premium">Premium (SUI)</Label>
                    <Input
                      id="one-time-premium"
                      type="text"
                      inputMode="decimal"
                      placeholder="0.100000000"
                      value={oneTimeOffer.premium}
                      onChange={(e) => setOneTimeOffer({ ...oneTimeOffer, premium: e.target.value })}
                      className="mt-2"
                    />
                    <p className="text-sm text-muted-foreground mt-1">1 SUI = 1e9 MIST.</p>
                  </div>

                  <div>
                    <Label htmlFor="one-time-collateral">Collateral (SUI)</Label>
                    <Input
                      id="one-time-collateral"
                      type="text"
                      inputMode="decimal"
                      placeholder="10.000000000"
                      value={oneTimeOffer.collateral}
                      onChange={(e) => setOneTimeOffer({ ...oneTimeOffer, collateral: e.target.value })}
                      className="mt-2"
                    />
                  </div>

                  <div>
                    <Label htmlFor="one-time-strike">Strike Price (SUI)</Label>
                    <Input
                      id="one-time-strike"
                      type="text"
                      inputMode="decimal"
                      placeholder="0.001000000"
                      value={oneTimeOffer.strikePrice}
                      onChange={(e) => setOneTimeOffer({ ...oneTimeOffer, strikePrice: e.target.value })}
                      className="mt-2"
                    />
                  </div>

                  <div>
                    <Label htmlFor="one-time-until">Offer Valid Until (JJ:MM:AAAA)</Label>
                    <Input
                      id="one-time-until"
                      type="text"
                      inputMode="numeric"
                      placeholder="31:12:2025"
                      value={oneTimeOffer.validUntilStr}
                      onChange={(e) => setOneTimeOffer({ ...oneTimeOffer, validUntilStr: e.target.value })}
                      className="mt-2"
                    />
                    {oneTimeOffer.validUntilStr && !parseDateParts(oneTimeOffer.validUntilStr) && (
                      <p className="text-xs text-red-500 mt-1">Format invalide. Exemple: 31:12:2025</p>
                    )}
                  </div>
                </div>
              </Card>
            </TabsContent>

            {/* Recurring */}
            <TabsContent value="recurring" className="space-y-6">
              <Card className="p-6 border-primary/10">
                <h3 className="text-xl mb-6">Recurring Insurance Offer</h3>

                <div className="space-y-6">
                  <div>
                    <Label htmlFor="recurring-premium">Premium (SUI)</Label>
                    <Input
                      id="recurring-premium"
                      type="text"
                      inputMode="decimal"
                      placeholder="0.500000000"
                      value={recurringOffer.premium}
                      onChange={(e) => setRecurringOffer({ ...recurringOffer, premium: e.target.value })}
                      className="mt-2"
                    />
                  </div>

                  <div>
                    <Label htmlFor="recurring-collateral">Collateral (SUI)</Label>
                    <Input
                      id="recurring-collateral"
                      type="text"
                      inputMode="decimal"
                      placeholder="50.000000000"
                      value={recurringOffer.collateral}
                      onChange={(e) => setRecurringOffer({ ...recurringOffer, collateral: e.target.value })}
                      className="mt-2"
                    />
                  </div>

                  <div>
                    <Label htmlFor="recurring-strike">Strike Price (SUI)</Label>
                    <Input
                      id="recurring-strike"
                      type="text"
                      inputMode="decimal"
                      placeholder="0.001000000"
                      value={recurringOffer.strikePrice}
                      onChange={(e) => setRecurringOffer({ ...recurringOffer, strikePrice: e.target.value })}
                      className="mt-2"
                    />
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <Label htmlFor="rec-start">Coverage Start (JJ:MM:AAAA)</Label>
                      <Input
                        id="rec-start"
                        type="text"
                        inputMode="numeric"
                        placeholder="01:01:2026"
                        value={recurringOffer.validFromStr}
                        onChange={(e) => setRecurringOffer({ ...recurringOffer, validFromStr: e.target.value })}
                        className="mt-2"
                      />
                      {recurringOffer.validFromStr && !parseDateParts(recurringOffer.validFromStr) && (
                        <p className="text-xs text-red-500 mt-1">Format invalide. Exemple: 01:01:2026</p>
                      )}
                    </div>

                    <div>
                      <Label htmlFor="rec-end">Coverage End (JJ:MM:AAAA)</Label>
                      <Input
                        id="rec-end"
                        type="text"
                        inputMode="numeric"
                        placeholder="31:01:2026"
                        value={recurringOffer.validUntilStr}
                        onChange={(e) => setRecurringOffer({ ...recurringOffer, validUntilStr: e.target.value })}
                        className="mt-2"
                      />
                      {recurringOffer.validUntilStr && !parseDateParts(recurringOffer.validUntilStr) && (
                        <p className="text-xs text-red-500 mt-1">Format invalide. Exemple: 31:01:2026</p>
                      )}
                      {parseDateParts(recurringOffer.validFromStr) &&
                        parseDateParts(recurringOffer.validUntilStr) &&
                        startOfDayUTC(parseDateParts(recurringOffer.validFromStr)!) >
                          endOfDayUTC(parseDateParts(recurringOffer.validUntilStr)!) && (
                          <p className="text-xs text-red-500 mt-1">La date de début doit précéder la date de fin.</p>
                        )}
                    </div>
                  </div>

                  <div>
                    <Label htmlFor="max-transactions">Maximum Transactions</Label>
                    <Input
                      id="max-transactions"
                      type="number"
                      inputMode="numeric"
                      placeholder="20"
                      value={recurringOffer.maxTransactions}
                      onChange={(e) => setRecurringOffer({ ...recurringOffer, maxTransactions: e.target.value })}
                      className="mt-2"
                    />
                  </div>
                </div>
              </Card>
            </TabsContent>
        </Tabs>

        <div className="flex justify-center mt-8">
          <Button
            onClick={handleSubmitOffer}
            className="px-12 py-3 bg-primary hover:bg-primary/90"
            size="lg"
            disabled={isPending || (activeTab === 'one-time' ? !oneValid : !recValid)}
          >
            <Wallet className="mr-2 h-4 w-4" />
            {isPending ? 'Signing…' : 'Sign & Submit Offer'}
          </Button>
        </div>

        {error && <div className="mt-4 text-sm text-red-500">Erreur: {error}</div>}

        <div className="mt-6 p-4 bg-yellow-500/10 border border-yellow-500/20 rounded-lg">
          <p className="text-sm text-muted-foreground">
            <strong>Note:</strong> Le collatéral est scindé depuis la pièce de gas. Assurez un solde suffisant.
          </p>
        </div>
      </div>
    </div>
  );
}
