// web/src/components/CoinSelector.tsx
// Sélecteur simple qui expose un objectId choisi.

import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from './ui/select';

export function CoinSelector({
  coins, value, onChange,
}: { coins: { id: string; balance: bigint }[]; value?: string; onChange: (id: string) => void; }) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger className="w-full"><SelectValue placeholder="Choose a SUI coin" /></SelectTrigger>
      <SelectContent>
        {coins.map(c => (
          <SelectItem key={c.id} value={c.id}>
            {c.id.slice(0,10)}… — {c.balance.toString()} MIST
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
