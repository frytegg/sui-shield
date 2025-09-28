// src/components/RoleModal.tsx
import { Dialog, DialogContent, DialogHeader, DialogTitle } from './ui/dialog';
import { Card } from './ui/card';
import { Shield, TrendingUp, Search } from 'lucide-react';

type Role = 'insured' | 'insurer' | 'marketplace';

export function RoleModal({
  open,
  onOpenChange,
  onSelect,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  onSelect: (r: Role) => void;
}) {
  // Note: `RoleSelector` exists as an alternate (non-modal) UI but was
  // intentionally commented out in the codebase in favor of this dialog-based
  // `RoleModal` for a more polished UX.
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg bg-card border-primary/20">
        <DialogHeader>
          <DialogTitle className="text-center text-2xl">Choose your role</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <Card
            className="p-6 cursor-pointer hover:bg-accent/50 transition-colors border-primary/10 hover:border-primary/30"
            onClick={() => onSelect('insured')}
          >
            <div className="flex items-start space-x-4">
              <Shield className="h-8 w-8 text-primary mt-1" />
              <div>
                <h3 className="text-lg mb-1">I want to be insured</h3>
                <p className="text-sm text-muted-foreground">
                  Protect transactions from gas spikes. Set a strike and get coverage.
                </p>
              </div>
            </div>
          </Card>

          <Card
            className="p-6 cursor-pointer hover:bg-accent/50 transition-colors border-primary/10 hover:border-primary/30"
            onClick={() => onSelect('insurer')}
          >
            <div className="flex items-start space-x-4">
              <TrendingUp className="h-8 w-8 text-primary mt-1" />
              <div>
                <h3 className="text-lg mb-1">I provide insurance</h3>
                <p className="text-sm text-muted-foreground">
                  Earn premiums by offering gas insurance. Set terms and rates.
                </p>
              </div>
            </div>
          </Card>

          <Card
            className="p-6 cursor-pointer hover:bg-accent/50 transition-colors border-primary/10 hover:border-primary/30"
            onClick={() => onSelect('marketplace')}
          >
            <div className="flex items-start space-x-4">
              <Search className="h-8 w-8 text-primary mt-1" />
              <div>
                <h3 className="text-lg mb-1">Browse marketplace</h3>
                <p className="text-sm text-muted-foreground">
                  Browse offers and pick the best coverage.
                </p>
              </div>
            </div>
          </Card>
        </div>
      </DialogContent>
    </Dialog>
  );
}
