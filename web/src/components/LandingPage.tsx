import { Button } from './ui/button';
import { Card } from './ui/card';
import { Shield, Zap, TrendingUp, Users, ArrowDown, Sparkles, Lock, Clock, ChevronDown } from 'lucide-react';
import { Header } from './Header';
import { Footer } from './Footer';
import { ImageWithFallback } from './figma/ImageWithFallback';

interface LandingPageProps {
  onWalletConnect: () => void;
  onNavigateToMarketplace: () => void;
  onBackToLanding: () => void;
  isWalletConnected: boolean;
  onGetStarted: () => void;   
  onWalletDisconnect?: () => void;
}

export function LandingPage({ onWalletConnect, isWalletConnected, onBackToLanding, onNavigateToMarketplace, onGetStarted, onWalletDisconnect, }: LandingPageProps) {
  const scrollToAbout = () => {
    document.getElementById('how-it-works')?.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <div className="min-h-screen bg-gradient-main">
          <Header
            onWalletConnect={onWalletConnect}
            onWalletDisconnect={onWalletDisconnect}
            isWalletConnected={isWalletConnected}
            onNavigateToMarketplace={onNavigateToMarketplace}
          />
      
      {/* Hero Section */}
      <section className="relative min-h-screen flex items-center justify-center pt-32">
        {/* Decorative elements inspired by the reference */}
        <div className="absolute inset-0 overflow-hidden">
          <div className="absolute top-20 right-10 w-96 h-96 bg-gradient-to-br from-blue/10 to-blue-light/5 rounded-full blur-3xl"></div>
          <div className="absolute bottom-20 left-10 w-80 h-80 bg-gradient-to-br from-blue/5 to-blue-dark/10 rounded-full blur-3xl"></div>
          <div className="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-gradient-to-br from-secondary/20 to-muted/30 rounded-full blur-3xl opacity-30"></div>
        </div>
        
        <div className="relative z-10 text-center max-w-5xl mx-auto px-6">
          <div className="mb-12">
            {/* Badge */}
            <div className="inline-flex items-center space-x-2 bg-blue/10 text-blue-light px-4 py-2 rounded-full mb-8 border border-blue/20">
              <Sparkles className="w-4 h-4" />
              <span className="font-medium">Gas fee insurance for SUI</span>
            </div>
            
            <h1 className="text-7xl md:text-9xl mb-8 font-black tracking-tight">
              <span className="text-gradient-white">SuiShield</span>
            </h1>
            <p className="text-xl md:text-2xl text-muted-foreground max-w-3xl mx-auto leading-relaxed">
              Connect with insurers on our decentralized marketplace and get covered if gas fees exceed your defined threshold.
            </p>
          </div>
          
          <div className="flex flex-col sm:flex-row gap-4 justify-center items-center mb-16">
            <Button
              onClick={() => (isWalletConnected ? onGetStarted() : onWalletConnect())}
              size="lg"
              className="px-10 py-6 text-lg bg-blue hover:bg-blue-dark text-blue-foreground shadow-blue hover:shadow-lg transition-all duration-200 transform hover:scale-105 glow-blue"
            >
              Get Started
            </Button>
            <Button 
              onClick={scrollToAbout}
              variant="outline"
              size="lg"
              className="px-10 py-6 text-lg border-border text-foreground hover:bg-muted/50 transition-all duration-200"
            >
              Learn More
              <ArrowDown className="ml-2 h-5 w-5" />
            </Button>
          </div>
          
          {/* Animated scroll indicators */}
          <div className="flex justify-center items-center space-x-1 mb-16">
            <ChevronDown className="h-4 w-4 text-blue/60 animate-bounce-slow" style={{ animationDelay: '0ms' }} />
            <ChevronDown className="h-4 w-4 text-blue/40 animate-bounce-slow" style={{ animationDelay: '200ms' }} />
            <ChevronDown className="h-4 w-4 text-blue/60 animate-bounce-slow" style={{ animationDelay: '400ms' }} />
          </div>
        </div>
      </section>

      {/* About Section */}
      <section id="how-it-works" className="py-24 px-6 bg-background">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-20">
            <h2 className="text-5xl md:text-6xl mb-8 font-black tracking-tight">
              <span className="text-foreground">How It</span>
              <span className="text-gradient-blue"> Works</span>
            </h2>
            <p className="text-xl text-muted-foreground max-w-4xl mx-auto leading-relaxed">
              Our decentralized marketplace connects users who want gas fee protection 
              with insurers offering coverage, creating a transparent and efficient insurance ecosystem.
            </p>
          </div>

          {/* Features Grid */}
          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8 mb-20">
            <Card className="p-8 bg-gradient-card border-gradient shadow-soft hover:shadow-medium transition-all duration-300 group">
              <div className="w-14 h-14 bg-blue/10 rounded-2xl flex items-center justify-center mb-6 group-hover:bg-blue/20 transition-colors">
                <Shield className="h-7 w-7 text-blue" />
              </div>
              <h3 className="text-xl mb-4 font-semibold">Gas Protection</h3>
              <p className="text-muted-foreground leading-relaxed">
                Set a strike price and get coverage when gas fees exceed your threshold
              </p>
            </Card>

            <Card className="p-8 bg-gradient-card border-gradient shadow-soft hover:shadow-medium transition-all duration-300 group">
              <div className="w-14 h-14 bg-blue/10 rounded-2xl flex items-center justify-center mb-6 group-hover:bg-blue/20 transition-colors">
                <Zap className="h-7 w-7 text-blue" />
              </div>
              <h3 className="text-xl mb-4 font-semibold">Instant Coverage</h3>
              <p className="text-muted-foreground leading-relaxed">
                One-time or recurring insurance options for your transaction needs
              </p>
            </Card>

            <Card className="p-8 bg-gradient-card border-gradient shadow-soft hover:shadow-medium transition-all duration-300 group">
              <div className="w-14 h-14 bg-blue/10 rounded-2xl flex items-center justify-center mb-6 group-hover:bg-blue/20 transition-colors">
                <TrendingUp className="h-7 w-7 text-blue" />
              </div>
              <h3 className="text-xl mb-4 font-semibold">Earn as Insurer</h3>
              <p className="text-muted-foreground leading-relaxed">
                Provide liquidity and earn premiums by offering insurance coverage
              </p>
            </Card>

            <Card className="p-8 bg-gradient-card border-gradient shadow-soft hover:shadow-medium transition-all duration-300 group">
              <div className="w-14 h-14 bg-blue/10 rounded-2xl flex items-center justify-center mb-6 group-hover:bg-blue/20 transition-colors">
                <Users className="h-7 w-7 text-blue" />
              </div>
              <h3 className="text-xl mb-4 font-semibold">Decentralized</h3>
              <p className="text-muted-foreground leading-relaxed">
                Peer-to-peer marketplace with smart contract execution on SUI
              </p>
            </Card>
          </div>

          {/* Insurance Types */}
          <div id="insurance-types" className="grid md:grid-cols-2 gap-12">
            <Card className="p-10 bg-gradient-card border-gradient shadow-soft hover:shadow-medium transition-all duration-300">
              <div className="flex items-center space-x-3 mb-6">
                <div className="w-12 h-12 bg-blue/10 rounded-xl flex items-center justify-center">
                  <Clock className="h-6 w-6 text-blue" />
                </div>
                <h3 className="text-3xl font-bold">One-Time Insurance</h3>
              </div>
              <p className="text-muted-foreground mb-8 leading-relaxed text-lg">
                Perfect for single high-value transactions. Set your strike price, 
                coverage amount, and transaction date. Pay a premium and get protection 
                against gas fee spikes.
              </p>
              <ul className="space-y-3 text-muted-foreground">
                <li className="flex items-center space-x-3">
                  <div className="w-1.5 h-1.5 bg-blue rounded-full"></div>
                  <span>Single transaction coverage</span>
                </li>
                <li className="flex items-center space-x-3">
                  <div className="w-1.5 h-1.5 bg-blue rounded-full"></div>
                  <span>Custom strike price</span>
                </li>
                <li className="flex items-center space-x-3">
                  <div className="w-1.5 h-1.5 bg-blue rounded-full"></div>
                  <span>Immediate settlement</span>
                </li>
                <li className="flex items-center space-x-3">
                  <div className="w-1.5 h-1.5 bg-blue rounded-full"></div>
                  <span>Fixed premium</span>
                </li>
              </ul>
            </Card>

            <Card className="p-10 bg-gradient-card border-gradient shadow-soft hover:shadow-medium transition-all duration-300">
              <div className="flex items-center space-x-3 mb-6">
                <div className="w-12 h-12 bg-blue/10 rounded-xl flex items-center justify-center">
                  <Lock className="h-6 w-6 text-blue" />
                </div>
                <h3 className="text-3xl font-bold">Recurring Insurance</h3>
              </div>
              <p className="text-muted-foreground mb-8 leading-relaxed text-lg">
                Ideal for regular DeFi activities. Get coverage for multiple transactions 
                over a specified time period with predictable costs and ongoing protection.
              </p>
              <ul className="space-y-3 text-muted-foreground">
                <li className="flex items-center space-x-3">
                  <div className="w-1.5 h-1.5 bg-blue rounded-full"></div>
                  <span>Multiple transaction coverage</span>
                </li>
                <li className="flex items-center space-x-3">
                  <div className="w-1.5 h-1.5 bg-blue rounded-full"></div>
                  <span>Time-based policies</span>
                </li>
                <li className="flex items-center space-x-3">
                  <div className="w-1.5 h-1.5 bg-blue rounded-full"></div>
                  <span>On-chain oracle validation</span>
                </li>
                <li className="flex items-center space-x-3">
                  <div className="w-1.5 h-1.5 bg-blue rounded-full"></div>
                  <span>Automatic collateral payouts</span>
                </li>
              </ul>
            </Card>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-24 px-6 bg-gradient-to-br from-blue/5 to-blue-light/10">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-4xl md:text-5xl font-black mb-6 tracking-tight">
            Ready to Protect Your <span className="text-gradient-blue">Transactions?</span>
          </h2>
          <p className="text-xl text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
            Join thousands of users already protecting their gas fees with SuiShield's 
            decentralized insurance marketplace.
          </p>
          <Button 
            onClick={onGetStarted}
            size="lg"
            className="px-12 py-6 text-xl bg-blue hover:bg-blue-dark text-blue-foreground shadow-blue hover:shadow-lg transition-all duration-200 transform hover:scale-105 glow-blue"
          >
            Get Started Now
          </Button>
        </div>
      </section>

      <Footer />
    </div>
  );
}