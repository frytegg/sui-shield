import { useState } from 'react';
import { Card } from './ui/card';
import { Button } from './ui/button';
import { Input } from './ui/input';
import { Label } from './ui/label';
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from './ui/select';
import { useExecuteTx } from '../hooks/useExecuteTx';
import { txSetOperator } from '../sui/tx/oracle';

export default function OracleAdmin() {
  const [mode, setMode] = useState<'wallet'|'zk'>('wallet');
  const { execute } = useExecuteTx(mode);
  const [operator, setOperator] = useState('');

  async function onSet() {
    if (!operator) { alert('Enter operator address'); return; }
    const res = await execute(() => txSetOperator({ operator }));
    console.log('set_operator', res);
  }

  return (
    <Card className="p-6 border-primary/10 space-y-4">
      <div className="flex gap-4">
        <div className="flex-1">
          <Label>Sign mode</Label>
          <Select value={mode} onValueChange={(v) => setMode(v as any)}>
            <SelectTrigger className="mt-2"><SelectValue placeholder="Mode" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="wallet">Wallet</SelectItem>
              <SelectItem value="zk">zkLogin</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="flex-[2]">
          <Label>Operator address</Label>
          <Input className="mt-2" value={operator} onChange={(e)=>setOperator(e.target.value)} placeholder="0x..." />
        </div>
      </div>
      <div className="pt-2">
        <Button onClick={onSet} className="bg-primary hover:bg-primary/90">Set operator</Button>
      </div>
    </Card>
  );
}
