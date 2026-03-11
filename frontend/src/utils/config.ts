export const PROGRAM_ID = 'automation_scheduled_transferv3.aleo';

export const NETWORK_CONFIG = {
  NETWORK: 'testnet' as const,
  EXPLORER_API: 'https://api.explorer.provable.com/v1/testnet',
  EXPLORER_TX_URL: 'https://testnet.explorer.provable.com/transaction/',
} as const;

// Keeper bot runs locally
export const BOT_API = 'http://localhost:3001';

// ~10 seconds per block on Aleo testnet
export const SECONDS_PER_BLOCK = 10;
export const BLOCKS_PER_MINUTE = 60 / SECONDS_PER_BLOCK; // 6

// Extra blocks buffer to account for ZK proof generation + confirmation time
export const PROOF_BUFFER_BLOCKS = 20;
