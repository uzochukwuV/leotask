import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Layers, Repeat, ShieldAlert, Crosshair, ArrowRight } from 'lucide-react';
import { Button } from '../ui/button';
import { Input } from '../ui/input';
import { Label } from '@radix-ui/react-label';

const TABS = [
  { id: 'scheduled', label: 'One-Time', icon: <ArrowRight size={16} /> },
  { id: 'recurring', label: 'Recurring', icon: <Repeat size={16} /> },
  { id: 'conditional', label: 'Conditional', icon: <Crosshair size={16} /> },
  { id: 'escrow', label: 'Escrow', icon: <ShieldAlert size={16} /> },
];

export function TaskCreation() {
  const [activeTab, setActiveTab] = useState('scheduled');
  const [tokenType, setTokenType] = useState<'ALEO' | 'USDCx'>('ALEO');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const isUsdcx = tokenType === 'USDCx';

  return (
    <div className="max-w-4xl mx-auto w-full flex flex-col items-center justify-center min-h-[80vh]">
      <motion.div 
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className={`w-full glass-panel rounded-2xl overflow-hidden transition-all duration-500 ${isUsdcx ? 'neon-border-blue' : 'neon-border-cyan'}`}
      >
        <div className="p-8 border-b border-white/5 flex justify-between items-center bg-black/20">
          <h2 className="text-2xl font-black tracking-tighter">NEW AUTOMATION</h2>
          
          <div className="flex bg-black/40 rounded-lg p-1 border border-white/5">
            <button 
              onClick={() => setTokenType('ALEO')}
              className={`px-4 py-1.5 rounded-md text-xs font-bold tracking-widest transition-all ${!isUsdcx ? 'bg-cyan-500 text-black shadow-[0_0_10px_rgba(6,182,212,0.5)]' : 'text-zinc-500 hover:text-white'}`}
            >
              ALEO
            </button>
            <button 
              onClick={() => setTokenType('USDCx')}
              className={`px-4 py-1.5 rounded-md text-xs font-bold tracking-widest transition-all ${isUsdcx ? 'bg-blue-500 text-black shadow-[0_0_10px_rgba(59,130,246,0.5)]' : 'text-zinc-500 hover:text-white'}`}
            >
              USDCx
            </button>
          </div>
        </div>

        <div className="flex border-b border-white/5">
          {TABS.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex-1 flex flex-col items-center justify-center gap-2 py-4 text-xs font-bold tracking-widest uppercase transition-all border-b-2 ${
                activeTab === tab.id 
                  ? (isUsdcx ? 'border-blue-500 text-white bg-blue-500/5' : 'border-cyan-500 text-white bg-cyan-500/5') 
                  : 'border-transparent text-zinc-500 hover:bg-white/5 hover:text-zinc-300'
              }`}
            >
              {tab.icon}
              {tab.label}
            </button>
          ))}
        </div>

        <div className="p-8 min-h-[400px] relative">
          <AnimatePresence mode="wait">
            <motion.div
              key={activeTab}
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -20 }}
              transition={{ duration: 0.2 }}
              className="space-y-6"
            >
              {/* Common Inputs */}
              <div className="grid grid-cols-2 gap-6">
                <div className="space-y-2 col-span-2">
                  <Label className="text-xs font-bold tracking-widest text-zinc-400">Recipient Address</Label>
                  <Input placeholder="aleo1..." />
                </div>
                
                <div className="space-y-2">
                  <Label className="text-xs font-bold tracking-widest text-zinc-400">Amount ({tokenType})</Label>
                  <Input type="number" placeholder="0.00" />
                </div>

                <div className="space-y-2">
                  <Label className="text-xs font-bold tracking-widest text-zinc-400">Keeper Fee</Label>
                  <Input type="number" placeholder="0.00" defaultValue="0.05" />
                </div>
              </div>

              {/* Dynamic Inputs */}
              {activeTab === 'recurring' && (
                <div className="grid grid-cols-2 gap-6 p-6 rounded-lg bg-white/5 border border-white/5">
                  <div className="space-y-2">
                    <Label className="text-xs font-bold tracking-widest text-zinc-400">Interval Blocks</Label>
                    <Input type="number" placeholder="e.g. 5000" />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-xs font-bold tracking-widest text-zinc-400">Max Executions</Label>
                    <Input type="number" placeholder="12" />
                  </div>
                </div>
              )}

              {activeTab === 'conditional' && (
                <div className="grid grid-cols-2 gap-6 p-6 rounded-lg bg-white/5 border border-white/5">
                  <div className="space-y-2">
                    <Label className="text-xs font-bold tracking-widest text-zinc-400">Target Price</Label>
                    <Input type="number" placeholder="$100.00" />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-xs font-bold tracking-widest text-zinc-400">Oracle Address</Label>
                    <Input placeholder="aleo1oracle..." />
                  </div>
                </div>
              )}

              {activeTab === 'escrow' && (
                <div className="grid grid-cols-2 gap-6 p-6 rounded-lg bg-white/5 border border-white/5">
                  <div className="space-y-2">
                    <Label className="text-xs font-bold tracking-widest text-zinc-400">Required Approvals</Label>
                    <Input type="number" placeholder="2" />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-xs font-bold tracking-widest text-zinc-400">Party Address</Label>
                    <Input placeholder="aleo1..." />
                  </div>
                </div>
              )}

              {/* Expiry Block */}
              <div className="pt-4 border-t border-white/5 space-y-2">
                <Label className="text-xs font-bold tracking-widest text-zinc-400 flex justify-between">
                  <span>Expiry Block (Escape Hatch)</span>
                  <span className="text-zinc-600 font-mono">Current: 198420</span>
                </Label>
                <Input type="number" placeholder="e.g. 200000" />
              </div>

            </motion.div>
          </AnimatePresence>

          <div className="mt-12 flex justify-end">
            <Button 
              size="lg" 
              className={`w-full md:w-auto font-mono uppercase tracking-widest ${isUsdcx ? 'bg-blue-500 hover:bg-blue-400 text-black' : 'bg-cyan-500 hover:bg-cyan-400 text-black'}`}
              onClick={() => {
                setIsSubmitting(true);
                setTimeout(() => setIsSubmitting(false), 2000);
              }}
              disabled={isSubmitting}
            >
              {isSubmitting ? 'GENERATING PROOF...' : 'INITIALIZE_TASK'}
            </Button>
          </div>
        </div>
      </motion.div>
    </div>
  );
}
