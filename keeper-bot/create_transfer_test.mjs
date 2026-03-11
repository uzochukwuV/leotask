#!/usr/bin/env node
/**
 * create_transfer_test.mjs
 * ========================
 * Creates a scheduled transfer on testnet using the caller's PUBLIC credits balance,
 * then registers it with the keeper bot for auto-execution.
 *
 * Required in .env:
 *   PRIVATE_KEY    - sender's private key (must have public credits balance on testnet)
 *
 * Optional:
 *   RECIPIENT      - who receives the funds (default: sender's address)
 *   AMOUNT         - microcredits to send (default: 1000000 = 1 credit)
 *   TRIGGER_BLOCKS - blocks ahead to schedule (default: 50 ≈ ~8 min, must be > proof gen time ~15 blocks)
 */

import 'dotenv/config';
import { execSync } from 'child_process';
import https from 'https';
import http from 'http';

const SNARKOS        = process.env.SNARKOS_PATH || 'snarkos';
const PRIVATE_KEY    = process.env.PRIVATE_KEY || '';
const PROGRAM_ID     = process.env.PROGRAM_ID || 'automation_scheduled_transferv3.aleo';
const NETWORK_ID     = process.env.NETWORK_ID || '1';
const QUERY_ENDPOINT = process.env.QUERY_ENDPOINT || 'https://api.explorer.provable.com/v1';
const BROADCAST      = process.env.BROADCAST_ENDPOINT || 'https://api.explorer.provable.com/v1/testnet/transaction/broadcast';
const API_ENDPOINT   = process.env.API_ENDPOINT || 'https://api.explorer.provable.com/v1/testnet';
const BOT_PORT       = process.env.API_PORT || '3001';

if (!PRIVATE_KEY) { console.error('ERROR: PRIVATE_KEY not set in .env'); process.exit(1); }

// ─────────────────────────────────────────────────────────────────────────────

function fetchText(url) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith('https') ? https : http;
    client.get(url, { headers: { Accept: 'application/json' } }, (res) => {
      let data = '';
      res.on('data', c => (data += c));
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

function postJson(url, body) {
  return new Promise((resolve, reject) => {
    const data   = JSON.stringify(body);
    const urlObj = new URL(url);
    const client = urlObj.protocol === 'https:' ? https : http;
    const req = client.request({
      hostname: urlObj.hostname,
      port:     urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
      path:     urlObj.pathname,
      method:   'POST',
      headers:  { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) },
    }, (res) => {
      let d = '';
      res.on('data', c => (d += c));
      res.on('end', () => { try { resolve(JSON.parse(d)); } catch { resolve(d); } });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function randomField() {
  const hi = BigInt(Math.floor(Math.random() * 0xFFFFFFFF));
  const lo = BigInt(Math.floor(Math.random() * 0xFFFFFFFFFFFF));
  return ((hi << 48n) | lo).toString() + 'field';
}

// Extract transaction ID from snarkos output (looks for at1...)
function parseTxId(snarkosOutput) {
  const m = snarkosOutput.match(/\bat1[a-z0-9]+/);
  return m?.[0] || null;
}

// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║       Leotask - Create Scheduled Transfer (Test)           ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');

  let currentBlock = 0;
  let triggerBlock;
  const triggerBlocks = parseInt(process.env.TRIGGER_BLOCKS || '50');

  if (process.env.TRIGGER_BLOCK) {
    triggerBlock = parseInt(process.env.TRIGGER_BLOCK);
    console.log(`Trigger block : ${triggerBlock} (manual override)`);
  } else {
    try {
      currentBlock = parseInt((await fetchText(`${API_ENDPOINT}/block/height/latest`)).trim());
      triggerBlock = currentBlock + triggerBlocks;
      console.log(`Current block : ${currentBlock}`);
      console.log(`Trigger block : ${triggerBlock} (+${triggerBlocks} blocks ≈ ~${Math.round(triggerBlocks * 10 / 60)} min)`);
    } catch (err) {
      console.error(`ERROR: Could not fetch block height: ${err.message}`);
      console.error('');
      console.error('DNS may be broken in WSL2. Fix with:');
      console.error('  echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf');
      console.error('');
      console.error('Or set TRIGGER_BLOCK=<absolute_block> in .env to skip this fetch.');
      process.exit(1);
    }
  }
  console.log('');

  const recipient = process.env.RECIPIENT || 'aleo1yauy6n5v8h3nhef3s3um0y8l4ejr2su23xayp3l782t0w0yf9u8q7y8twh';
  const amount    = process.env.AMOUNT    || '1000000';
  const taskId    = randomField();

  console.log(`task_id      : ${taskId}`);
  console.log(`recipient    : ${recipient}`);
  console.log(`amount       : ${amount} microcredits (${(parseInt(amount) / 1_000_000).toFixed(6)} credits)`);
  console.log(`trigger_block: ${triggerBlock}`);
  console.log('');
  console.log('Broadcasting... (ZK proof generation ~30-120s)');
  console.log('');

  const cmd = [
    `"${SNARKOS}" developer execute`,
    `--private-key "${PRIVATE_KEY}"`,
    `--query "${QUERY_ENDPOINT}"`,
    `--broadcast "${BROADCAST}"`,
    `--network ${NETWORK_ID}`,
    PROGRAM_ID,
    'create_scheduled_transfer',
    taskId,
    recipient,
    `${amount}u64`,
    `${triggerBlock}u32`,
  ].join(' ');

  let snarkosOutput = '';
  try {
    // Merge stderr into stdout so we capture the full transaction JSON
    const result = execSync(cmd + ' 2>&1', {
      timeout: 300000,
      encoding: 'utf8',
    });
    snarkosOutput = result;
    console.log('Transaction broadcast successfully!');
    console.log(snarkosOutput.trim().substring(0, 300));
    console.log('');
  } catch (err) {
    const output = (err.stdout || '') + (err.stderr || '') || err.message;
    console.error('FAILED:');
    console.error(output.substring(0, 800));
    process.exit(1);
  }

  const txId = parseTxId(snarkosOutput);
  if (txId) console.log(`Transaction ID: ${txId}`);

  console.log(`Registering with keeper bot at http://localhost:${BOT_PORT}...`);

  try {
    const result = await postJson(`http://localhost:${BOT_PORT}/api/tasks/register`, {
      taskId, recipient, amount, triggerBlock,
    });
    console.log('Registered:', JSON.stringify(result, null, 2));
    console.log('');
    console.log(`Bot will execute transfer at block ${triggerBlock}`);
    console.log(`Watch: curl http://localhost:${BOT_PORT}/api/tasks`);
  } catch (err) {
    console.error(`Bot unreachable: ${err.message}`);
    console.error('Start the bot first: node keeper-bot.mjs');
  }
}

main().catch(err => { console.error('Fatal:', err.message); process.exit(1); });
