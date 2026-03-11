#!/usr/bin/env node

/**
 * Leotask - Scheduled Transfer Keeper Bot
 * =========================================
 * Only needs PRIVATE_KEY.
 *
 * How it works:
 *   1. create_transfer_test.mjs creates the on-chain transfer and registers
 *      the task with this bot via POST /api/tasks/register
 *   2. Bot polls block height every 15s
 *   3. When block >= trigger_block, bot calls execute_scheduled_transfer
 *      passing the record ciphertext — snarkos handles decryption internally
 *
 * API:
 *   POST /api/tasks/register  - Register a task (called by test script)
 *   GET  /api/tasks           - All pending tasks
 *   GET  /api/tasks/:taskId   - Single task
 *   GET  /health              - Bot status
 */

import 'dotenv/config';
import { execSync } from 'child_process';
import https from 'https';
import http from 'http';

// ═══════════════════════════════════════════════════════════════
// CONFIG
// ═══════════════════════════════════════════════════════════════

const SNARKOS = process.env.SNARKOS_PATH || 'snarkos';

const CONFIG = {
  privateKey:        process.env.PRIVATE_KEY || '',
  programId:         process.env.PROGRAM_ID || 'automation_scheduled_transferv3.aleo',
  network:           process.env.NETWORK || 'testnet',
  networkId:         process.env.NETWORK_ID || '1',
  apiEndpoint:       process.env.API_ENDPOINT || 'https://api.explorer.provable.com/v1/testnet',
  queryEndpoint:     process.env.QUERY_ENDPOINT || 'https://api.explorer.provable.com/v1',
  broadcastEndpoint: process.env.BROADCAST_ENDPOINT || 'https://api.explorer.provable.com/v1/testnet/transaction/broadcast',
  blockIntervalMs:   parseInt(process.env.BLOCK_INTERVAL || '15000'),
  apiPort:           parseInt(process.env.API_PORT || '3001'),
  frontendOrigin:    process.env.FRONTEND_ORIGIN || '*',
};

// ═══════════════════════════════════════════════════════════════
// STATE
// taskStore: Map<taskId, { taskId, recipient, amount, triggerBlock, ciphertext, registeredAt }>
// ═══════════════════════════════════════════════════════════════

const taskStore    = new Map();
let currentBlock   = 0n;
let botStartedAt   = new Date().toISOString();
let botPaused      = false;
let isExecuting    = false;

// ═══════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════

function log(tag, msg) {
  console.log(`[${new Date().toISOString().substring(11, 19)}] [${tag}] ${msg}`);
}

function logError(tag, msg) {
  console.error(`[${new Date().toISOString().substring(11, 19)}] [${tag}] ERROR: ${msg}`);
}

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

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ═══════════════════════════════════════════════════════════════
// BLOCK HEIGHT
// ═══════════════════════════════════════════════════════════════

async function fetchBlockHeight() {
  try {
    const raw = await fetchText(`${CONFIG.apiEndpoint}/block/height/latest`);
    currentBlock = BigInt(raw.trim());
    return currentBlock;
  } catch (err) {
    logError('BLOCK', `Failed: ${err.message}`);
    return currentBlock;
  }
}

// ═══════════════════════════════════════════════════════════════
// EXECUTE
// ═══════════════════════════════════════════════════════════════

async function executeTask(task) {
  log('EXECUTE', `Task ${task.taskId}`);
  log('EXECUTE', `  recipient    : ${task.recipient}`);
  log('EXECUTE', `  amount       : ${task.amount} microcredits`);
  log('EXECUTE', `  trigger_block: ${task.triggerBlock} (current: ${currentBlock})`);

  try {
    const cmd = [
      `${SNARKOS} developer execute`,
      `--private-key "${CONFIG.privateKey}"`,
      `--query "${CONFIG.queryEndpoint}"`,
      `--broadcast "${CONFIG.broadcastEndpoint}"`,
      `--network ${CONFIG.networkId}`,
      CONFIG.programId,
      'execute_scheduled_transfer',
      task.taskId,
      task.recipient,
      `${task.amount}u64`,
    ].join(' ');

    const output = execSync(cmd, {
      timeout: 300000,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    log('EXECUTE', `Task ${task.taskId} executed successfully`);
    log('EXECUTE', output.trim().substring(0, 200));
    taskStore.delete(task.taskId);
    return true;
  } catch (err) {
    logError('EXECUTE', `Failed: ${err.stderr?.substring(0, 400) || err.message}`);
    return false;
  }
}

async function checkAndExecute() {
  if (isExecuting || taskStore.size === 0) return;
  isExecuting = true;
  try {
    for (const task of taskStore.values()) {
      if (currentBlock >= BigInt(task.triggerBlock)) {
        log('EXECUTE', `Task ${task.taskId} ready — executing`);
        await executeTask(task);
        await sleep(5000);
      }
    }
  } finally {
    isExecuting = false;
  }
}

// ═══════════════════════════════════════════════════════════════
// BLOCK TICK
// ═══════════════════════════════════════════════════════════════

async function blockTick() {
  if (botPaused) return;
  try {
    const h = await fetchBlockHeight();
    const pending = [...taskStore.values()].filter(t => BigInt(t.triggerBlock) > h);
    const ready   = taskStore.size - pending.length;
    log('BLOCK', `height: ${h} | pending: ${pending.length} | ready: ${ready}`);
    await checkAndExecute();
  } catch (err) {
    logError('BLOCK', err.message);
  }
}

// ═══════════════════════════════════════════════════════════════
// HTTP API
// ═══════════════════════════════════════════════════════════════

function serializeTask(t) {
  return {
    taskId:          t.taskId,
    recipient:       t.recipient,
    amount:          t.amount,
    triggerBlock:    t.triggerBlock,
    currentBlock:    currentBlock.toString(),
    ready:           currentBlock >= BigInt(t.triggerBlock),
    blocksRemaining: BigInt(t.triggerBlock) > currentBlock
      ? (BigInt(t.triggerBlock) - currentBlock).toString()
      : '0',
    registeredAt: t.registeredAt,
  };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', c => (data += c));
    req.on('end', () => { try { resolve(JSON.parse(data)); } catch { reject(new Error('Invalid JSON')); } });
    req.on('error', reject);
  });
}

function startApiServer() {
  const server = http.createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', CONFIG.frontendOrigin);
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

    const url  = new URL(req.url, `http://localhost:${CONFIG.apiPort}`);
    const json = (data, code = 200) => {
      res.writeHead(code, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(data, null, 2));
    };

    // POST /api/tasks/register — called by create_transfer_test.mjs
    if (req.method === 'POST' && url.pathname === '/api/tasks/register') {
      try {
        const body = await readBody(req);
        const { taskId, recipient, amount, triggerBlock } = body;

        if (!taskId || !recipient || !amount || !triggerBlock) {
          return json({ error: 'Missing fields: taskId, recipient, amount, triggerBlock' }, 400);
        }

        taskStore.set(taskId, {
          taskId, recipient,
          amount: amount.toString(),
          triggerBlock: triggerBlock.toString(),
          registeredAt: new Date().toISOString(),
        });

        log('REGISTER', `Task ${taskId} | trigger: ${triggerBlock} | amount: ${amount} | recipient: ${recipient}`);
        return json({ ok: true, task: serializeTask(taskStore.get(taskId)) });
      } catch (err) {
        return json({ error: err.message }, 400);
      }
    }

    // GET /health
    if (req.method === 'GET' && url.pathname === '/health') {
      return json({
        status:       'ok',
        paused:       botPaused,
        programId:    CONFIG.programId,
        currentBlock: currentBlock.toString(),
        pendingTasks: taskStore.size,
        upSince:      botStartedAt,
      });
    }

    // GET /api/tasks
    if (req.method === 'GET' && url.pathname === '/api/tasks') {
      const tasks = [...taskStore.values()].map(serializeTask);
      tasks.sort((a, b) => parseInt(a.blocksRemaining) - parseInt(b.blocksRemaining));
      return json({ tasks, currentBlock: currentBlock.toString() });
    }

    // GET /api/tasks/:taskId
    const m = url.pathname.match(/^\/api\/tasks\/(.+)$/);
    if (req.method === 'GET' && m) {
      const task = taskStore.get(m[1]);
      if (!task) return json({ error: 'Not found' }, 404);
      return json(serializeTask(task));
    }

    res.writeHead(404); res.end();
  });

  server.listen(CONFIG.apiPort, () => {
    log('API', `Listening on port ${CONFIG.apiPort}`);
    log('API', `  POST http://localhost:${CONFIG.apiPort}/api/tasks/register`);
    log('API', `  GET  http://localhost:${CONFIG.apiPort}/api/tasks`);
    log('API', `  GET  http://localhost:${CONFIG.apiPort}/health`);
  });
  server.on('error', err => logError('API', err.message));
}

// ═══════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════

async function main() {
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║          Leotask - Scheduled Transfer Keeper Bot           ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');
  log('BOT', `Program : ${CONFIG.programId}`);
  log('BOT', `Network : ${CONFIG.network}`);
  log('BOT', `Polling : every ${CONFIG.blockIntervalMs / 1000}s`);
  console.log('');

  if (!CONFIG.privateKey) {
    logError('BOT', 'PRIVATE_KEY not set in .env');
    process.exit(1);
  }

  startApiServer();

  log('BOT', 'Fetching initial block height...');
  await blockTick();

  setInterval(blockTick, CONFIG.blockIntervalMs);
  log('BOT', 'Running. Waiting for tasks via POST /api/tasks/register');
}

main().catch(err => { logError('BOT', `Fatal: ${err.message}`); process.exit(1); });
