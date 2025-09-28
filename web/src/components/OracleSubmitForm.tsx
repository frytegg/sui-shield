// src/OracleSubmitForm.tsx
/**
 * OracleSubmitForm — envoie une observation de gas.
 *
 * Quoi: construit une PTB avec txSubmitObservation, signe+exécute via useExecuteTx.
 * UI: inchangée. Champs: policyId, txDigest, gasUsed (SUI → MIST).
 *
 * Docs:
 * - useSignAndExecuteTransaction: https://sdk.mystenlabs.com/dapp-kit/wallet-hooks/useSignAndExecuteTransaction :contentReference[oaicite:5]{index=5}
 * - PTB builder: https://docs.sui.io/guides/developer/sui-101/building-ptb :contentReference[oaicite:6]{index=6}
 */
import { useState } from 'react';
import { Button } from './ui/button';
import { Card } from './ui/card';
import { Input } from './ui/input';
import { Label } from './ui/label';
import { CheckCircle } from 'lucide-react';
import { useCurrentAccount } from '@mysten/dapp-kit';
import { useExecuteTx } from '@/hooks/useExecuteTx';
import { txSubmitObservation } from '@/sui/tx/oracle';

function toMist(s: string): bigint {
  const [i, f = ''] = s.trim().split('.');
  const f9 = (f + '000000000').slice(0, 9);
  const digs = (i || '0') + f9;
  return BigInt(digs.replace(/^0+(?=\d)/, '') || '0');
}

export default function OracleSubmitForm() {
  const acct = useCurrentAccount();
  const { execute, isPending, error } = useExecuteTx();

  const [policyId, setPolicyId] = useState('');
  const [txDigest, setTxDigest] = useState('');
  const [gasUsed, setGasUsed] = useState(''); // SUI
  const [ok, setOk] = useState<string | null>(null);

  async function onSubmit() {
    if (!acct) { alert('Connectez votre wallet.'); return; }
    setOk(null);
    try {
      const gasMist = toMist(gasUsed || '0');
      const { digest } = await execute(() =>
        txSubmitObservation({ policyId: policyId.trim(), txDigest: txDigest.trim(), gasUsedMist: gasMist }),
      );
      setOk(digest);
    } catch (e: any) {
      console.error(e);
    }
  }

  return (
    <div className="max-w-xl mx-auto">
      <Card className="p-6 border-primary/10">
        <h3 className="text-xl mb-4">Submit Gas Observation</h3>

        <div className="space-y-4">
          <div>
            <Label htmlFor="policy">Policy ID</Label>
            <Input id="policy" placeholder="0x..." value={policyId} onChange={(e) => setPolicyId(e.target.value)} className="mt-2" />
          </div>

          <div>
            <Label htmlFor="digest">Transaction Digest</Label>
            <Input id="digest" placeholder="CE1Z...abc" value={txDigest} onChange={(e) => setTxDigest(e.target.value)} className="mt-2" />
          </div>

          <div>
            <Label htmlFor="gas">Gas Used (SUI)</Label>
            <Input id="gas" placeholder="0.001234" value={gasUsed} onChange={(e) => setGasUsed(e.target.value)} className="mt-2" />
            <p className="text-xs text-muted-foreground mt-1">1 SUI = 1e9 MIST</p>
          </div>

          <Button onClick={onSubmit} disabled={isPending}>{isPending ? 'Submitting…' : 'Submit Observation'}</Button>

          {error && <div className="text-xs text-red-500">Erreur: {error}</div>}
          {ok && (
            <div className="flex items-center gap-2 text-green-600 text-sm">
              <CheckCircle className="w-4 h-4" /> Submitted. Digest: <code>{ok}</code>
            </div>
          )}
        </div>
      </Card>
    </div>
  );
}
