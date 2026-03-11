export const SCALE = 1_000_000; // microcredits per ALEO

// Truncate address for display: aleo1abc...xyz
export function truncateAddress(address: string): string {
  if (!address || address.length < 20) return address;
  return `${address.slice(0, 10)}...${address.slice(-6)}`;
}

// Format microcredits to human-readable ALEO string
export function formatAleo(microcredits: bigint | number | string | null): string {
  if (microcredits === null || microcredits === undefined) return '-';
  const value = Number(microcredits) / SCALE;
  return value.toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  });
}

// Parse user ALEO input → microcredits bigint
export function parseAleo(input: string): bigint {
  const value = parseFloat(input);
  if (isNaN(value) || value <= 0) return BigInt(0);
  return BigInt(Math.floor(value * SCALE));
}

// Generate a random Aleo field element (120-bit, always valid)
export function randomField(): string {
  const arr = new Uint32Array(4);
  crypto.getRandomValues(arr);
  const n =
    (BigInt(arr[0]) << 88n) |
    (BigInt(arr[1]) << 56n) |
    (BigInt(arr[2]) << 28n) |
    BigInt(arr[3] & 0x0fffffff);
  return n.toString() + 'field';
}

// Rough estimate: blocks → human readable time
export function blocksToTime(blocks: number): string {
  const seconds = blocks * 10;
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const rem = minutes % 60;
  return rem > 0 ? `${hours}h ${rem}m` : `${hours}h`;
}

// Time ago from ISO string
export function timeAgo(isoString: string): string {
  const diff = Date.now() - new Date(isoString).getTime();
  const secs = Math.floor(diff / 1000);
  if (secs < 60) return `${secs}s ago`;
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m ago`;
  return `${Math.floor(mins / 60)}h ago`;
}
