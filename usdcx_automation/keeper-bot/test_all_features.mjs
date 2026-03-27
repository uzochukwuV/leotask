#!/usr/bin/env node

/**
 * USDCx Automation - Comprehensive Test Suite
 * =============================================
 * Tests all features: one-time, recurring, conditional, multi-party escrow
 *
 * Usage:
 *   node test_all_features.mjs                    # Run all tests
 *   node test_all_features.mjs --one-time         # Test one-time transfers only
 *   node test_all_features.mjs --recurring        # Test recurring transfers only
 *   node test_all_features.mjs --conditional      # Test conditional transfers only
 *   node test_all_features.mjs --escrow           # Test multi-party escrow only
 *   node test_all_features.mjs --stress           # Stress test with many tasks
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
  programId:         process.env.PROGRAM_ID || 'usdcx_automation_hub.aleo',
  network:           process.env.NETWORK || 'testnet',
  networkId:         process.env.NETWORK_ID || '1',
  apiEndpoint:       process.env.API_ENDPOINT || 'https://api.explorer.provable.com/v1/testnet',
  queryEndpoint:     process.env.QUERY_ENDPOINT || 'https://api.explorer.provable.com/v1',
  broadcastEndpoint: process.env.BROADCAST_ENDPOINT || 'https://api.explorer.provable.com/v1/testnet/transaction/broadcast',
  keeperBotUrl:      process.env.KEEPER_BOT_URL || 'http://localhost:3002',
  testAmount:        parseInt(process.env.TEST_AMOUNT || '1000000'),  // 1 USDCx in microcredits
  testRecipient:     process.env.TEST_RECIPIENT || 'aleo1testrecipient1234567890abcdefghijklmnopqrstuvwxyz',
};

// ═══════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════

function log(tag, msg) {
  console.log(`[${new Date().toISOString().substring(11, 19)}] [${tag}] ${msg}`);
}

function logError(tag, msg) {
  console.error(`[${new Date().toISOString().substring(11, 19)}] [${tag}] ERROR: ${msg}`);
}

function logSuccess(tag, msg) {
  console.log(`[${new Date().toISOString().substring(11, 19)}] [${tag}] ✅ ${msg}`);
}

function logSection(title) {
  console.log('');
  console.log('═'.repeat(60));
  console.log(`  ${title}`);
  console.log('═'.repeat(60));
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function generateTaskId() {
  return '0x' + Math.random().toString(16).substring(2, 18).padEnd(16, '0');
}

async function fetchBlockHeight() {
  try {
    const raw = await new Promise((resolve, reject) => {
      https.get(`${CONFIG.apiEndpoint}/block/height/latest`, (res) => {
        let data = '';
        res.on('data', c => (data += c));
        res.on('end', () => resolve(data));
      }).on('error', reject);
    });
    return BigInt(raw.trim());
  } catch (err) {
    logError('BLOCK', `Failed: ${err.message}`);
    return 0n;
  }
}

async function registerTask(endpoint, data) {
  return new Promise((resolve, reject) => {
    const url = new URL(endpoint, CONFIG.keeperBotUrl);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    };

    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', c => (body += c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(body));
        } catch {
          reject(new Error('Invalid JSON response'));
        }
      });
    });

    req.on('error', reject);
    req.write(JSON.stringify(data));
    req.end();
  });
}

async function getTask(taskId) {
  return new Promise((resolve, reject) => {
    const url = new URL(`/api/tasks/${taskId}`, CONFIG.keeperBotUrl);
    http.get(url, (res) => {
      let body = '';
      res.on('data', c => (body += c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(body));
        } catch {
          reject(new Error('Invalid JSON response'));
        }
      });
    }).on('error', reject);
  });
}

async function getAllTasks() {
  return new Promise((resolve, reject) => {
    const url = new URL('/api/tasks', CONFIG.keeperBotUrl);
    http.get(url, (res) => {
      let body = '';
      res.on('data', c => (body += c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(body));
        } catch {
          reject(new Error('Invalid JSON response'));
        }
      });
    }).on('error', reject);
  });
}

async function approveEscrow(taskId) {
  return new Promise((resolve, reject) => {
    const url = new URL(`/api/tasks/${taskId}/approve`, CONFIG.keeperBotUrl);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    };

    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', c => (body += c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(body));
        } catch {
          reject(new Error('Invalid JSON response'));
        }
      });
    });

    req.on('error', reject);
    req.end();
  });
}

// ═══════════════════════════════════════════════════════════════
// TEST: ONE-TIME TRANSFER
// ═══════════════════════════════════════════════════════════════

async function testOneTimeTransfer() {
  logSection('TEST: One-Time USDCx Transfer');

  const currentBlock = await fetchBlockHeight();
  const triggerBlock = currentBlock + 10n;
  const taskId = generateTaskId();

  log('ONE-TIME', `Creating one-time transfer task ${taskId}`);
  log('ONE-TIME', `  Amount: ${CONFIG.testAmount} USDCx`);
  log('ONE-TIME', `  Recipient: ${CONFIG.testRecipient}`);
  log('ONE-TIME', `  Trigger block: ${triggerBlock}`);

  try {
    const result = await registerTask('/api/tasks/register', {
      taskId,
      recipient: CONFIG.testRecipient,
      amount: CONFIG.testAmount,
      triggerBlock: triggerBlock.toString(),
    });

    if (result.ok) {
      logSuccess('ONE-TIME', `Task registered successfully`);
      log('ONE-TIME', `  Task ID: ${result.task.taskId}`);
      log('ONE-TIME', `  Blocks remaining: ${result.task.blocksRemaining}`);
      return { success: true, taskId };
    } else {
      logError('ONE-TIME', `Registration failed: ${result.error}`);
      return { success: false, error: result.error };
    }
  } catch (err) {
    logError('ONE-TIME', `Exception: ${err.message}`);
    return { success: false, error: err.message };
  }
}

// ═══════════════════════════════════════════════════════════════
// TEST: RECURRING TRANSFER
// ═══════════════════════════════════════════════════════════════

async function testRecurringTransfer() {
  logSection('TEST: Recurring USDCx Transfer');

  const currentBlock = await fetchBlockHeight();
  const firstTriggerBlock = currentBlock + 10n;
  const intervalBlocks = 5;
  const maxExecutions = 3;
  const amountPerExecution = CONFIG.testAmount;
  const totalAmount = amountPerExecution * maxExecutions;
  const taskId = generateTaskId();

  log('RECURRING', `Creating recurring transfer task ${taskId}`);
  log('RECURRING', `  Amount per execution: ${amountPerExecution} USDCx`);
  log('RECURRING', `  Total amount: ${totalAmount} USDCx`);
  log('RECURRING', `  Max executions: ${maxExecutions}`);
  log('RECURRING', `  Interval: ${intervalBlocks} blocks`);
  log('RECURRING', `  First trigger block: ${firstTriggerBlock}`);

  try {
    const result = await registerTask('/api/tasks/register-recurring', {
      taskId,
      recipient: CONFIG.testRecipient,
      amountPerExecution,
      firstTriggerBlock: firstTriggerBlock.toString(),
      intervalBlocks,
      maxExecutions,
    });

    if (result.ok) {
      logSuccess('RECURRING', `Task registered successfully`);
      log('RECURRING', `  Task ID: ${result.task.taskId}`);
      log('RECURRING', `  Blocks remaining: ${result.task.blocksRemaining}`);
      log('RECURRING', `  Executions: ${result.task.executionsCompleted}/${result.task.maxExecutions}`);
      return { success: true, taskId };
    } else {
      logError('RECURRING', `Registration failed: ${result.error}`);
      return { success: false, error: result.error };
    }
  } catch (err) {
    logError('RECURRING', `Exception: ${err.message}`);
    return { success: false, error: err.message };
  }
}

// ═══════════════════════════════════════════════════════════════
// TEST: CONDITIONAL TRANSFER
// ═══════════════════════════════════════════════════════════════

async function testConditionalTransfer() {
  logSection('TEST: Conditional USDCx Transfer');

  const currentBlock = await fetchBlockHeight();
  const triggerBlock = currentBlock + 10n;
  const conditionType = 1;  // price_above
  const conditionValue = 50000;  // Price must be above 50000
  const taskId = generateTaskId();

  log('CONDITIONAL', `Creating conditional transfer task ${taskId}`);
  log('CONDITIONAL', `  Amount: ${CONFIG.testAmount} USDCx`);
  log('CONDITIONAL', `  Condition: price_above ${conditionValue}`);
  log('CONDITIONAL', `  Trigger block: ${triggerBlock}`);

  try {
    const result = await registerTask('/api/tasks/register-conditional', {
      taskId,
      recipient: CONFIG.testRecipient,
      amount: CONFIG.testAmount,
      triggerBlock: triggerBlock.toString(),
      conditionType,
      conditionValue,
    });

    if (result.ok) {
      logSuccess('CONDITIONAL', `Task registered successfully`);
      log('CONDITIONAL', `  Task ID: ${result.task.taskId}`);
      log('CONDITIONAL', `  Blocks remaining: ${result.task.blocksRemaining}`);
      log('CONDITIONAL', `  Condition met: ${result.task.conditionMet}`);
      return { success: true, taskId };
    } else {
      logError('CONDITIONAL', `Registration failed: ${result.error}`);
      return { success: false, error: result.error };
    }
  } catch (err) {
    logError('CONDITIONAL', `Exception: ${err.message}`);
    return { success: false, error: err.message };
  }
}

// ═══════════════════════════════════════════════════════════════
// TEST: MULTI-PARTY ESCROW
// ═══════════════════════════════════════════════════════════════

async function testMultiPartyEscrow() {
  logSection('TEST: Multi-Party USDCx Escrow');

  const currentBlock = await fetchBlockHeight();
  const triggerBlock = currentBlock + 20n;
  const requiredApprovals = 3;
  const taskId = generateTaskId();

  log('ESCROW', `Creating multi-party escrow task ${taskId}`);
  log('ESCROW', `  Amount: ${CONFIG.testAmount} USDCx`);
  log('ESCROW', `  Required approvals: ${requiredApprovals}`);
  log('ESCROW', `  Trigger block: ${triggerBlock}`);

  try {
    const result = await registerTask('/api/tasks/register-escrow', {
      taskId,
      recipient: CONFIG.testRecipient,
      amount: CONFIG.testAmount,
      triggerBlock: triggerBlock.toString(),
      requiredApprovals,
    });

    if (result.ok) {
      logSuccess('ESCROW', `Task registered successfully`);
      log('ESCROW', `  Task ID: ${result.task.taskId}`);
      log('ESCROW', `  Blocks remaining: ${result.task.blocksRemaining}`);
      log('ESCROW', `  Approvals: ${result.task.approvalsReceived}/${result.task.requiredApprovals}`);
      log('ESCROW', `  Approved: ${result.task.isApproved}`);

      // Simulate approvals
      log('ESCROW', `Simulating ${requiredApprovals} approvals...`);
      for (let i = 0; i < requiredApprovals; i++) {
        await sleep(500);
        const approveResult = await approveEscrow(taskId);
        if (approveResult.ok) {
          log('ESCROW', `  Approval ${i + 1}/${requiredApprovals} received`);
        }
      }

      // Check final state
      const finalTask = await getTask(taskId);
      log('ESCROW', `Final state: ${finalTask.approvalsReceived}/${finalTask.requiredApprovals} approvals, approved: ${finalTask.isApproved}`);

      return { success: true, taskId };
    } else {
      logError('ESCROW', `Registration failed: ${result.error}`);
      return { success: false, error: result.error };
    }
  } catch (err) {
    logError('ESCROW', `Exception: ${err.message}`);
    return { success: false, error: err.message };
  }
}

// ═══════════════════════════════════════════════════════════════
// TEST: STRESS TEST
// ═══════════════════════════════════════════════════════════════

async function stressTest() {
  logSection('STRESS TEST: Multiple Concurrent Tasks');

  const currentBlock = await fetchBlockHeight();
  const numTasks = 10;
  const taskIds = [];

  log('STRESS', `Creating ${numTasks} concurrent tasks...`);

  for (let i = 0; i < numTasks; i++) {
    const taskId = generateTaskId();
    const triggerBlock = currentBlock + BigInt(10 + i * 5);
    const taskType = i % 4;  // Rotate through task types

    let endpoint, data;

    switch (taskType) {
      case 0:  // One-time
        endpoint = '/api/tasks/register';
        data = {
          taskId,
          recipient: CONFIG.testRecipient,
          amount: CONFIG.testAmount,
          triggerBlock: triggerBlock.toString(),
        };
        break;
      case 1:  // Recurring
        endpoint = '/api/tasks/register-recurring';
        data = {
          taskId,
          recipient: CONFIG.testRecipient,
          amountPerExecution: CONFIG.testAmount,
          firstTriggerBlock: triggerBlock.toString(),
          intervalBlocks: 5,
          maxExecutions: 2,
        };
        break;
      case 2:  // Conditional
        endpoint = '/api/tasks/register-conditional';
        data = {
          taskId,
          recipient: CONFIG.testRecipient,
          amount: CONFIG.testAmount,
          triggerBlock: triggerBlock.toString(),
          conditionType: 1,
          conditionValue: 50000,
        };
        break;
      case 3:  // Escrow
        endpoint = '/api/tasks/register-escrow';
        data = {
          taskId,
          recipient: CONFIG.testRecipient,
          amount: CONFIG.testAmount,
          triggerBlock: triggerBlock.toString(),
          requiredApprovals: 2,
        };
        break;
    }

    try {
      const result = await registerTask(endpoint, data);
      if (result.ok) {
        taskIds.push(taskId);
        log('STRESS', `  Task ${i + 1}/${numTasks} created: ${taskId.substring(0, 10)}...`);
      } else {
        logError('STRESS', `  Task ${i + 1} failed: ${result.error}`);
      }
    } catch (err) {
      logError('STRESS', `  Task ${i + 1} exception: ${err.message}`);
    }

    await sleep(100);  // Small delay between registrations
  }

  logSuccess('STRESS', `Created ${taskIds.length}/${numTasks} tasks`);

  // Check all tasks
  await sleep(1000);
  const allTasks = await getAllTasks();
  log('STRESS', `Total tasks in keeper: ${allTasks.tasks?.length || 0}`);

  return { success: true, taskIds };
}

// ═══════════════════════════════════════════════════════════════
// TEST: TASK QUERY
// ═══════════════════════════════════════════════════════════════

async function testTaskQuery() {
  logSection('TEST: Task Query API');

  try {
    // Get all tasks
    const allTasks = await getAllTasks();
    log('QUERY', `Total tasks: ${allTasks.tasks?.length || 0}`);

    // Get tasks by type
    for (let type = 0; type <= 3; type++) {
      const url = new URL(`/api/tasks/type/${type}`, CONFIG.keeperBotUrl);
      const typeTasks = await new Promise((resolve, reject) => {
        http.get(url, (res) => {
          let body = '';
          res.on('data', c => (body += c));
          res.on('end', () => {
            try {
              resolve(JSON.parse(body));
            } catch {
              reject(new Error('Invalid JSON'));
            }
          });
        }).on('error', reject);
      });

      const typeName = ['One-time', 'Recurring', 'Conditional', 'Escrow'][type];
      log('QUERY', `  ${typeName} tasks: ${typeTasks.tasks?.length || 0}`);
    }

    // Get health
    const healthUrl = new URL('/health', CONFIG.keeperBotUrl);
    const health = await new Promise((resolve, reject) => {
      http.get(healthUrl, (res) => {
        let body = '';
        res.on('data', c => (body += c));
        res.on('end', () => {
          try {
            resolve(JSON.parse(body));
          } catch {
            reject(new Error('Invalid JSON'));
          }
        });
      }).on('error', reject);
    });

    log('QUERY', `Bot status: ${health.status}`);
    log('QUERY', `Current block: ${health.currentBlock}`);
    log('QUERY', `Current price: ${health.currentPrice}`);
    log('QUERY', `Pending tasks: ${health.pendingTasks}`);

    logSuccess('QUERY', 'All query tests passed');
    return { success: true };
  } catch (err) {
    logError('QUERY', `Exception: ${err.message}`);
    return { success: false, error: err.message };
  }
}

// ═══════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════

async function main() {
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║        USDCx Automation - Comprehensive Test Suite         ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');

  const args = process.argv.slice(2);
  const runAll = args.length === 0;
  const results = {};

  // Check if keeper bot is running
  try {
    const healthUrl = new URL('/health', CONFIG.keeperBotUrl);
    await new Promise((resolve, reject) => {
      http.get(healthUrl, (res) => {
        let body = '';
        res.on('data', c => (body += c));
        res.on('end', () => resolve(body));
      }).on('error', reject);
    });
    log('MAIN', 'Keeper bot is running');
  } catch (err) {
    logError('MAIN', 'Keeper bot is not running. Please start it first.');
    log('MAIN', '  cd usdcx_automation/keeper-bot && npm start');
    process.exit(1);
  }

  // Run tests based on arguments
  if (runAll || args.includes('--one-time')) {
    results.oneTime = await testOneTimeTransfer();
    await sleep(2000);
  }

  if (runAll || args.includes('--recurring')) {
    results.recurring = await testRecurringTransfer();
    await sleep(2000);
  }

  if (runAll || args.includes('--conditional')) {
    results.conditional = await testConditionalTransfer();
    await sleep(2000);
  }

  if (runAll || args.includes('--escrow')) {
    results.escrow = await testMultiPartyEscrow();
    await sleep(2000);
  }

  if (runAll || args.includes('--stress')) {
    results.stress = await stressTest();
    await sleep(2000);
  }

  if (runAll || args.includes('--query')) {
    results.query = await testTaskQuery();
  }

  // Summary
  logSection('TEST SUMMARY');

  let passed = 0;
  let failed = 0;

  for (const [name, result] of Object.entries(results)) {
    if (result.success) {
      logSuccess(name.toUpperCase(), 'PASSED');
      passed++;
    } else {
      logError(name.toUpperCase(), `FAILED: ${result.error}`);
      failed++;
    }
  }

  console.log('');
  log('SUMMARY', `Total: ${passed + failed} | Passed: ${passed} | Failed: ${failed}`);
  console.log('');

  if (failed > 0) {
    process.exit(1);
  }
}

main().catch(err => {
  logError('MAIN', `Fatal: ${err.message}`);
  process.exit(1);
});
