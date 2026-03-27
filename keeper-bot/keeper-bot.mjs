#!/usr/bin/env node

/**
 * Leotask - Advanced Scheduled Transfer Keeper Bot
 * ================================================
 * Supports: One-time, recurring, conditional, and multi-party escrow transfers
 *
 * How it works:
 *   1. Test scripts create on-chain transfers and register tasks via POST /api/tasks/register
 *   2. Bot polls block height every 15s
 *   3. When conditions are met, bot executes the appropriate transfer
 *   4. For recurring tasks, bot reschedules after each execution
 *
 * API:
 *   POST /api/tasks/register           - Register a task
 *   POST /api/tasks/register-recurring - Register a recurring task
 *   POST /api/tasks/register-conditional - Register a conditional task
 *   POST /api/tasks/register-escrow    - Register a multi-party escrow
 *   POST /api/tasks/:taskId/approve    - Approve an escrow
 *   GET  /api/tasks                    - All pending tasks
 *   GET  /api/tasks/:taskId            - Single task
 *   GET  /api/tasks/type/:type         - Tasks by type
 *   GET  /health                       - Bot status
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
  programId:         process.env.PROGRAM_ID || 'automation_advanced_transferv4.aleo',
  network:           process.env.NETWORK || 'testnet',
  networkId:         process.env.NETWORK_ID || '1',
  apiEndpoint:       process.env.API_ENDPOINT || 'https://api.explorer.provable.com/v1/testnet',
  queryEndpoint:     process.env.QUERY_ENDPOINT || 'https://api.explorer.provable.com/v1',
  broadcastEndpoint: process.env.BROADCAST_ENDPOINT || 'https://api.explorer.provable.com/v1/testnet/transaction/broadcast',
  blockIntervalMs:   parseInt(process.env.BLOCK_INTERVAL || '15000'),
  apiPort:           parseInt(process.env.API_PORT || '3001'),
  frontendOrigin:    process.env.FRONTEND_ORIGIN || '*',
  priceOracleUrl:    process.env.PRICE_ORACLE_URL || '',
};

// ═══════════════════════════════════════════════════════════════
// TASK TYPES
// ═══════════════════════════════════════════════════════════════

const TASK_TYPES = {
  ONE_TIME: 0,
  RECURRING: 1,
  CONDITIONAL: 2,
  ESCROW: 3,
};

const CONDITION_TYPES = {
  NONE: 0,
  PRICE_ABOVE: 1,
  PRICE_BELOW: 2,
};

const TOKEN_TYPES = {
  ALEO: 0,
  USDCX: 1,
};

// ═══════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════

const taskStore    = new Map();
let currentBlock   = 0n;
let currentPrice   = 0n;  // For conditional transfers
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
// BLOCK HEIGHT & PRICE
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

async function fetchCurrentPrice() {
  if (!CONFIG.priceOracleUrl) return currentPrice;
  
  try {
    const raw = await fetchText(CONFIG.priceOracleUrl);
    const data = JSON.parse(raw);
    currentPrice = BigInt(data.price || 0);
    return currentPrice;
  } catch (err) {
    logError('PRICE', `Failed: ${err.message}`);
    return currentPrice;
  }
}

// ═══════════════════════════════════════════════════════════════
// EXECUTION
// ═══════════════════════════════════════════════════════════════

async function executeTask(task) {
  log('EXECUTE', `Task ${task.taskId} (type: ${task.taskType})`);
  log('EXECUTE', `  recipient    : ${task.recipient}`);
  log('EXECUTE', `  amount       : ${task.amount} microcredits`);
  log('EXECUTE', `  trigger_block: ${task.triggerBlock} (current: ${currentBlock})`);
  log('EXECUTE', `  token_type   : ${task.tokenType || 0}`);
  
  if (task.taskType === TASK_TYPES.CONDITIONAL) {
    log('EXECUTE', `  condition    : ${task.conditionType === CONDITION_TYPES.PRICE_ABOVE ? 'price_above' : 'price_below'} ${task.conditionValue}`);
    log('EXECUTE', `  current_price: ${currentPrice}`);
  }
  
  if (task.taskType === TASK_TYPES.ESCROW) {
    log('EXECUTE', `  approvals    : ${task.approvalsReceived}/${task.requiredApprovals}`);
  }

  try {
    const cmd = [
      `${SNARKOS} developer execute`,
      `--private-key "${CONFIG.privateKey}"`,
      `--query "${CONFIG.queryEndpoint}"`,
      `--broadcast "${CONFIG.broadcastEndpoint}"`,
      `--network ${CONFIG.networkId}`,
      CONFIG.programId,
      'execute_transfer',
      task.taskId,
      task.recipient,
      `${task.amount}u64`,
      `${currentPrice}u64`,  // For conditional transfers
    ].join(' ');

    const output = execSync(cmd, {
      timeout: 300000,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    log('EXECUTE', `Task ${task.taskId} executed successfully`);
    log('EXECUTE', output.trim().substring(0, 200));
    
    // Handle recurring tasks
    if (task.taskType === TASK_TYPES.RECURRING) {
      const executionsCompleted = (task.executionsCompleted || 0) + 1;
      
      if (executionsCompleted < task.maxExecutions) {
        // Schedule next execution
        const nextTrigger = BigInt(task.triggerBlock) + BigInt(task.intervalBlocks);
        task.triggerBlock = nextTrigger.toString();
        task.executionsCompleted = executionsCompleted;
        taskStore.set(task.taskId, task);
        log('EXECUTE', `Recurring task ${task.taskId} rescheduled for block ${nextTrigger}`);
      } else {
        // All executions completed
        taskStore.delete(task.taskId);
        log('EXECUTE', `Recurring task ${task.taskId} completed all ${task.maxExecutions} executions`);
      }
    } else {
      // One-time, conditional, or escrow - remove after execution
      taskStore.delete(task.taskId);
    }
    
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
      const triggerBlock = BigInt(task.triggerBlock);
      
      // Check if block height condition is met
      if (currentBlock < triggerBlock) continue;
      
      // Check task-specific conditions
      if (task.taskType === TASK_TYPES.CONDITIONAL) {
        const conditionValue = BigInt(task.conditionValue);
        
        if (task.conditionType === CONDITION_TYPES.PRICE_ABOVE) {
          if (currentPrice < conditionValue) {
            log('CONDITION', `Task ${task.taskId} waiting: price ${currentPrice} < ${conditionValue}`);
            continue;
          }
        } else if (task.conditionType === CONDITION_TYPES.PRICE_BELOW) {
          if (currentPrice > conditionValue) {
            log('CONDITION', `Task ${task.taskId} waiting: price ${currentPrice} > ${conditionValue}`);
            continue;
          }
        }
      }
      
      // Check escrow approval
      if (task.taskType === TASK_TYPES.ESCROW) {
        if (!task.isApproved) {
          log('ESCROW', `Task ${task.taskId} waiting: ${task.approvalsReceived}/${task.requiredApprovals} approvals`);
          continue;
        }
      }
      
      // All conditions met, execute
      log('EXECUTE', `Task ${task.taskId} ready — executing`);
      await executeTask(task);
      await sleep(5000);
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
    await fetchBlockHeight();
    await fetchCurrentPrice();
    
    const pending = [...taskStore.values()].filter(t => BigInt(t.triggerBlock) > currentBlock);
    const ready   = taskStore.size - pending.length;
    
    log('BLOCK', `height: ${currentBlock} | price: ${currentPrice} | pending: ${pending.length} | ready: ${ready}`);
    await checkAndExecute();
  } catch (err) {
    logError('BLOCK', err.message);
  }
}

// ═══════════════════════════════════════════════════════════════
// HTTP API
// ═══════════════════════════════════════════════════════════════

function serializeTask(t) {
  const triggerBlock = BigInt(t.triggerBlock);
  const blocksRemaining = triggerBlock > currentBlock
    ? (triggerBlock - currentBlock).toString()
    : '0';
  
  return {
    taskId:              t.taskId,
    recipient:           t.recipient,
    amount:              t.amount,
    triggerBlock:        t.triggerBlock,
    taskType:            t.taskType,
    tokenType:           t.tokenType || 0,
    currentBlock:        currentBlock.toString(),
    currentPrice:        currentPrice.toString(),
    ready:               currentBlock >= triggerBlock,
    blocksRemaining,
    registeredAt:        t.registeredAt,
    // Recurring fields
    intervalBlocks:      t.intervalBlocks,
    maxExecutions:       t.maxExecutions,
    executionsCompleted: t.executionsCompleted || 0,
    // Conditional fields
    conditionType:       t.conditionType,
    conditionValue:      t.conditionValue,
    conditionMet:        t.conditionType ? (
      t.conditionType === CONDITION_TYPES.PRICE_ABOVE
        ? currentPrice >= BigInt(t.conditionValue || 0)
        : currentPrice <= BigInt(t.conditionValue || 0)
    ) : true,
    // Escrow fields
    requiredApprovals:   t.requiredApprovals,
    approvalsReceived:   t.approvalsReceived || 0,
    isApproved:          t.isApproved || false,
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

    // POST /api/tasks/register — one-time transfer
    if (req.method === 'POST' && url.pathname === '/api/tasks/register') {
      try {
        const body = await readBody(req);
        const { taskId, recipient, amount, triggerBlock, tokenType } = body;

        if (!taskId || !recipient || !amount || !triggerBlock) {
          return json({ error: 'Missing fields: taskId, recipient, amount, triggerBlock' }, 400);
        }

        taskStore.set(taskId, {
          taskId, recipient,
          amount: amount.toString(),
          triggerBlock: triggerBlock.toString(),
          taskType: TASK_TYPES.ONE_TIME,
          tokenType: tokenType || TOKEN_TYPES.ALEO,
          registeredAt: new Date().toISOString(),
        });

        log('REGISTER', `One-time task ${taskId} | trigger: ${triggerBlock} | amount: ${amount} | recipient: ${recipient}`);
        return json({ ok: true, task: serializeTask(taskStore.get(taskId)) });
      } catch (err) {
        return json({ error: err.message }, 400);
      }
    }

    // POST /api/tasks/register-recurring — recurring transfer
    if (req.method === 'POST' && url.pathname === '/api/tasks/register-recurring') {
      try {
        const body = await readBody(req);
        const { taskId, recipient, amountPerExecution, firstTriggerBlock, intervalBlocks, maxExecutions, tokenType } = body;

        if (!taskId || !recipient || !amountPerExecution || !firstTriggerBlock || !intervalBlocks || !maxExecutions) {
          return json({ error: 'Missing fields: taskId, recipient, amountPerExecution, firstTriggerBlock, intervalBlocks, maxExecutions' }, 400);
        }

        taskStore.set(taskId, {
          taskId, recipient,
          amount: amountPerExecution.toString(),
          triggerBlock: firstTriggerBlock.toString(),
          taskType: TASK_TYPES.RECURRING,
          tokenType: tokenType || TOKEN_TYPES.ALEO,
          intervalBlocks: intervalBlocks.toString(),
          maxExecutions: parseInt(maxExecutions),
          executionsCompleted: 0,
          registeredAt: new Date().toISOString(),
        });

        log('REGISTER', `Recurring task ${taskId} | first_trigger: ${firstTriggerBlock} | interval: ${intervalBlocks} | max: ${maxExecutions} | amount: ${amountPerExecution}`);
        return json({ ok: true, task: serializeTask(taskStore.get(taskId)) });
      } catch (err) {
        return json({ error: err.message }, 400);
      }
    }

    // POST /api/tasks/register-conditional — conditional transfer
    if (req.method === 'POST' && url.pathname === '/api/tasks/register-conditional') {
      try {
        const body = await readBody(req);
        const { taskId, recipient, amount, triggerBlock, conditionType, conditionValue, tokenType } = body;

        if (!taskId || !recipient || !amount || !triggerBlock || !conditionType || conditionValue === undefined) {
          return json({ error: 'Missing fields: taskId, recipient, amount, triggerBlock, conditionType, conditionValue' }, 400);
        }

        taskStore.set(taskId, {
          taskId, recipient,
          amount: amount.toString(),
          triggerBlock: triggerBlock.toString(),
          taskType: TASK_TYPES.CONDITIONAL,
          tokenType: tokenType || TOKEN_TYPES.ALEO,
          conditionType: parseInt(conditionType),
          conditionValue: conditionValue.toString(),
          registeredAt: new Date().toISOString(),
        });

        log('REGISTER', `Conditional task ${taskId} | trigger: ${triggerBlock} | condition: ${conditionType === CONDITION_TYPES.PRICE_ABOVE ? 'price_above' : 'price_below'} ${conditionValue} | amount: ${amount}`);
        return json({ ok: true, task: serializeTask(taskStore.get(taskId)) });
      } catch (err) {
        return json({ error: err.message }, 400);
      }
    }

    // POST /api/tasks/register-escrow — multi-party escrow
    if (req.method === 'POST' && url.pathname === '/api/tasks/register-escrow') {
      try {
        const body = await readBody(req);
        const { taskId, recipient, amount, triggerBlock, requiredApprovals, tokenType } = body;

        if (!taskId || !recipient || !amount || !triggerBlock || !requiredApprovals) {
          return json({ error: 'Missing fields: taskId, recipient, amount, triggerBlock, requiredApprovals' }, 400);
        }

        taskStore.set(taskId, {
          taskId, recipient,
          amount: amount.toString(),
          triggerBlock: triggerBlock.toString(),
          taskType: TASK_TYPES.ESCROW,
          tokenType: tokenType || TOKEN_TYPES.ALEO,
          requiredApprovals: parseInt(requiredApprovals),
          approvalsReceived: 0,
          isApproved: false,
          registeredAt: new Date().toISOString(),
        });

        log('REGISTER', `Escrow task ${taskId} | trigger: ${triggerBlock} | required_approvals: ${requiredApprovals} | amount: ${amount}`);
        return json({ ok: true, task: serializeTask(taskStore.get(taskId)) });
      } catch (err) {
        return json({ error: err.message }, 400);
      }
    }

    // POST /api/tasks/:taskId/approve — approve escrow
    const approveMatch = url.pathname.match(/^\/api\/tasks\/(.+)\/approve$/);
    if (req.method === 'POST' && approveMatch) {
      try {
        const taskId = approveMatch[1];
        const task = taskStore.get(taskId);
        
        if (!task) {
          return json({ error: 'Task not found' }, 404);
        }
        
        if (task.taskType !== TASK_TYPES.ESCROW) {
          return json({ error: 'Task is not an escrow' }, 400);
        }
        
        const newApprovals = (task.approvalsReceived || 0) + 1;
        task.approvalsReceived = newApprovals;
        task.isApproved = newApprovals >= task.requiredApprovals;
        
        taskStore.set(taskId, task);
        
        log('APPROVE', `Escrow task ${taskId} approved (${newApprovals}/${task.requiredApprovals})`);
        return json({ ok: true, task: serializeTask(task) });
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
        currentPrice: currentPrice.toString(),
        pendingTasks: taskStore.size,
        tasksByType: {
          oneTime:    [...taskStore.values()].filter(t => t.taskType === TASK_TYPES.ONE_TIME).length,
          recurring:  [...taskStore.values()].filter(t => t.taskType === TASK_TYPES.RECURRING).length,
          conditional:[...taskStore.values()].filter(t => t.taskType === TASK_TYPES.CONDITIONAL).length,
          escrow:     [...taskStore.values()].filter(t => t.taskType === TASK_TYPES.ESCROW).length,
        },
        upSince:      botStartedAt,
      });
    }

    // GET /api/tasks
    if (req.method === 'GET' && url.pathname === '/api/tasks') {
      const tasks = [...taskStore.values()].map(serializeTask);
      tasks.sort((a, b) => parseInt(a.blocksRemaining) - parseInt(b.blocksRemaining));
      return json({ tasks, currentBlock: currentBlock.toString(), currentPrice: currentPrice.toString() });
    }

    // GET /api/tasks/type/:type
    const typeMatch = url.pathname.match(/^\/api\/tasks\/type\/(\d+)$/);
    if (req.method === 'GET' && typeMatch) {
      const taskType = parseInt(typeMatch[1]);
      const tasks = [...taskStore.values()]
        .filter(t => t.taskType === taskType)
        .map(serializeTask);
      tasks.sort((a, b) => parseInt(a.blocksRemaining) - parseInt(b.blocksRemaining));
      return json({ tasks, taskType, currentBlock: currentBlock.toString(), currentPrice: currentPrice.toString() });
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
    log('API', `  POST http://localhost:${CONFIG.apiPort}/api/tasks/register-recurring`);
    log('API', `  POST http://localhost:${CONFIG.apiPort}/api/tasks/register-conditional`);
    log('API', `  POST http://localhost:${CONFIG.apiPort}/api/tasks/register-escrow`);
    log('API', `  POST http://localhost:${CONFIG.apiPort}/api/tasks/:taskId/approve`);
    log('API', `  GET  http://localhost:${CONFIG.apiPort}/api/tasks`);
    log('API', `  GET  http://localhost:${CONFIG.apiPort}/api/tasks/type/:type`);
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
  console.log('║      Leotask - Advanced Scheduled Transfer Keeper Bot      ║');
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

  log('BOT', 'Fetching initial block height and price...');
  await blockTick();

  setInterval(blockTick, CONFIG.blockIntervalMs);
  log('BOT', 'Running. Waiting for tasks via POST /api/tasks/*');
}

main().catch(err => { logError('BOT', `Fatal: ${err.message}`); process.exit(1); });
