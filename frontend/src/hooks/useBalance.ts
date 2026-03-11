import { useState, useEffect, useCallback } from 'react';
import { useWallet } from '@provablehq/aleo-wallet-adaptor-react';
import { NETWORK_CONFIG } from '@/utils/config';

export function useBalance() {
  const { address, connected } = useWallet();
  const [publicBalance, setPublicBalance] = useState<bigint | null>(null);
  const [loading, setLoading] = useState(false);

  const fetchBalance = useCallback(async () => {
    if (!address || !connected) { setPublicBalance(null); return; }
    setLoading(true);
    try {
      const res = await fetch(
        `${NETWORK_CONFIG.EXPLORER_API}/program/credits.aleo/mapping/account/${address}`
      );
      if (res.ok) {
        const text = await res.text();
        const match = text.match(/(\d+)u64/);
        setPublicBalance(match ? BigInt(match[1]) : BigInt(0));
      } else if (res.status === 404) {
        setPublicBalance(BigInt(0));
      }
    } catch {
      setPublicBalance(null);
    } finally {
      setLoading(false);
    }
  }, [address, connected]);

  useEffect(() => { fetchBalance(); }, [fetchBalance]);
  useEffect(() => {
    if (!connected) return;
    const id = setInterval(fetchBalance, 30000);
    return () => clearInterval(id);
  }, [connected, fetchBalance]);

  return { publicBalance, loading, refresh: fetchBalance };
}
