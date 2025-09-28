import { useMemo, useState } from 'react';
import { Card } from './ui/card';
import { Button } from './ui/button';
import { Input } from './ui/input';
import { Badge } from './ui/badge';
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from './ui/select';

// On suppose que ce hook existe déjà dans votre codebase et lit via events/devInspect
import { usePolicies } from '../hooks/usePolicies';

// Exécution unifiée wallet-only
import { useExecuteTx } from '../hooks/useExecuteTx';
import { txSettle, txReclaim } from '../sui/tx/marketplace';

function fmt(ms: bigint | number) {
  const n = typeof ms === 'bigint' ? Number(ms) : ms;
  return isFinite(n) && n > 0 ? new Date(n).toLocaleString() : '—';
}

export function PolicyList() {
  // Le sélecteur visuel reste, mais seul "wallet" est utilisable
  const [mode, setMode] = useState<'wallet'>('wallet');

  // Exécution wallet-only
  const { execute, isPending, error } = useExecuteTx();

  // Lecture des polices
  const { data = [], isLoading } = usePolicies(200);

  // champ txDigest par policy
  const [digests, setDigests] = useState<Record<string, string>>({});
  const setDigest = (id: string, v: string) => setDigests((m) => ({ ...m, [id]: v }));

  const rows = useMemo(
    () =>
      data.map((p: any) => ({
        id: p.policy_id.id,
        insured: p.insured,
        insurer: p.insurer,
        expiryMs: Number(p.expiry_ms),
        remainingTxs: p.remaining_txs,
        coverageLeft: p.coverage_left_mist,
        policyType: p.policy_type,
      })),
    [data],
  );

  async function onSettle(id: string) {
    const d = digests[id];
    if (!d) {
      alert('Enter tx digest to settle');
      return;
    }
    const res = await execute(() => txSettle({ policyId: id, txDigest: d }));
    console.log('settle_tx', res);
  }

  async function onReclaim(id: string) {
    const res = await execute(() => txReclaim({ policyId: id }));
    console.log('reclaim_collateral_after_expiry', res);
  }

  return (
    <div className="space-y-4">
      <div className="flex gap-4">
        <div className="text-sm text-muted-foreground">Sign mode</div>
        <Select value={mode} onValueChange={() => { /* UI only, wallet unique */ }}>
          <SelectTrigger className="w-48"><SelectValue placeholder="Mode" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="wallet">Wallet</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {isLoading && <div className="text-sm text-muted-foreground">Loading policies…</div>}

      {rows.map((r) => {
        const expired = Date.now() > r.expiryMs;
        return (
          <Card key={r.id} className="p-6 border-primary/10">
            <div className="flex justify-between items-start mb-4">
              <div>
                <div className="font-mono text-sm">{r.id}</div>
                <div className="text-sm text-muted-foreground">
                  Insured {r.insured} • Insurer {r.insurer}
                </div>
                <div className="text-sm text-muted-foreground">
                  Expires {fmt(r.expiryMs)} • Remaining txs {r.remainingTxs.toString()} • Coverage left {r.coverageLeft.toString()} MIST
                </div>
              </div>
              <Badge variant={expired ? 'destructive' : 'secondary'}>{expired ? 'Expired' : 'Active'}</Badge>
            </div>

            <div className="grid md:grid-cols-3 gap-3">
              <div className="md:col-span-2">
                <Input
                  placeholder="Covered tx digest (to settle)"
                  value={digests[r.id] ?? ''}
                  onChange={(e) => setDigest(r.id, e.target.value)}
                />
              </div>
              <div className="flex gap-2">
                <Button onClick={() => onSettle(r.id)} className="bg-primary hover:bg-primary/90" disabled={isPending}>
                  {isPending ? 'Settling…' : 'Settle'}
                </Button>
                <Button onClick={() => onReclaim(r.id)} variant="outline" disabled={!expired || isPending}>
                  {isPending ? 'Working…' : 'Reclaim'}
                </Button>
              </div>
            </div>

            {error && <div className="text-xs text-red-500 mt-2">Erreur: {error}</div>}
          </Card>
        );
      })}

      {!isLoading && rows.length === 0 && (
        <div className="text-sm text-muted-foreground">No policies found.</div>
      )}
    </div>
  );
}
