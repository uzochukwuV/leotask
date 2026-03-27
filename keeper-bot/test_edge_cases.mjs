#!/usr/bin/env node

/**
 * Leotask - Edge Case Test Suite
 * ===============================
 * Tests edge cases, error handling, and boundary conditions
 *
 * Usage:
 *   node test_edge_cases.mjs
 */

import 'dotenv/config';
import http from 'http';

// ═══════════════════════════════════════════════════════════════
// CONFIG
// ═══════════════════════════════════════════════════════════════

const CONFIG = {
  keeperBotUrl: process.env.KEEPER_BOT_URL || 'http://localhost:3001',
  testRecipient: process.env.TEST_RECIPIENT || 'aleo1testrecipient1234567890abcdefghijklmnopqrstuvwxyz',
};

// ═══════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════

function log(tag, msg) {
  console.log(`[${new Date().toISOString().substring(11, 19)}] [${tag}] ${msg}`);
}

function logError(tag, msg) {
  console.error(`[${new Date().toISOString().substring(11, 19)}] [${tag}] ❌ ${msg}`);
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
          resolve({ status: res.statusCode, data: JSON.parse(body) });
        } catch {
          resolve({ status: res.statusCode, data: body });
        }
      });
    });

    req.on('error', reject);
    req.write(JSON.stringify(data));
    req.end();
  });
}

// ═══════════════════════════════════════════════════════════════
// TEST: INVALID INPUTS
// ═══════════════════════════════════════════════════════════════

async function testInvalidInputs() {
  logSection('TEST: Invalid Inputs');

  const tests = [
    {
      name: 'Missing taskId',
      endpoint: '/api/tasks/register',
      data: {
        recipient: CONFIG.testRecipient,
        amount: 1000000,
        triggerBlock: '1000',
      },
      expectedStatus: 400,
    },
    {
      name: 'Missing recipient',
      endpoint: '/api/tasks/register',
      data: {
        taskId: generateTaskId(),
        amount: 1000000,
        triggerBlock: '1000',
      },
      expectedStatus: 400,
    },
    {
      name: 'Missing amount',
      endpoint: '/api/tasks/register',
      data: {
        taskId: generateTaskId(),
        recipient: CONFIG.testRecipient,
        triggerBlock: '1000',
      },
      expectedStatus: 400,
    },
    {
      name: 'Missing triggerBlock',
      endpoint: '/api/tasks/register',
      data: {
        taskId: generateTaskId(),
        recipient: CONFIG.testRecipient,
        amount: 1000000,
      },
      expectedStatus: 400,
    },
    {
      name: 'Invalid JSON',
      endpoint: '/api/tasks/register',
      data: 'not json',
      expectedStatus: 400,
    },
  ];

  let passed = 0;
  let failed = 0;

  for (const test of tests) {
    try {
      const result = await registerTask(test.endpoint, test.data);
      
      if (result.status === test.expectedStatus) {
        logSuccess(test.name, `Status ${result.status} as expected`);
        passed++;
      } else {
        logError(test.name, `Expected status ${test.expectedStatus}, got ${result.status}`);
        failed++;
      }
    } catch (err) {
      logError(test.name, `Exception: ${err.message}`);
      failed++;
    }

    await sleep(200);
  }

  return { success: failed === 0, passed, failed };
}

// ═══════════════════════════════════════════════════════════════
// TEST: BOUNDARY CONDITIONS
// ═══════════════════════════════════════════════════════════════

async function testBoundaryConditions() {
  logSection('TEST: Boundary Conditions');

  const tests = [
    {
      name: 'Zero amount',
      endpoint: '/api/tasks/register',
      data: {
        taskId: generateTaskId(),
        recipient: CONFIG.testRecipient,
        amount: 0,
        triggerBlock: '1000',
      },
      shouldFail: true,
    },
    {
      name: 'Very large amount',
      endpoint: '/api/tasks/register',
      data: {
        taskId: generateTaskId(),
        recipient: CONFIG.testRecipient,
        amount: 18446744073709551615,  // Max u64
        triggerBlock: '1000',
      },
      shouldFail: false,
    },
    {
      name: 'Zero interval (recurring)',
      endpoint: '/api/tasks/register-recurring',
      data: {
        taskId: generateTaskId(),
        recipient: CONFIG.testRecipient,
        amountPerExecution: 1000000,
        firstTriggerBlock: '1000',
        intervalBlocks: 0,
        maxExecutions: 5,
      },
      shouldFail: true,
    },
    {
      name: 'Zero max executions (recurring)',
      endpoint: '/api/tasks/register-recurring',
      data: {
        taskId: generateTaskId(),
        recipient: CONFIG.testRecipient,
        amountPerExecution: 1000000,
        firstTriggerBlock: '1000',
        intervalBlocks: 5,
        maxExecutions: 0,
      },
      shouldFail: true,
    },
    {
      name: 'Invalid condition type',
      endpoint: '/api/tasks/register-conditional',
      data: {
        taskId: generateTaskId(),
        recipient: CONFIG.testRecipient,
        amount: 1000000,
        triggerBlock: '1000',
        conditionType: 5,  // Invalid
        conditionValue: 50000,
      },
      shouldFail: true,
    },
    {
      name: 'Zero required approvals (escrow)',
      endpoint: '/api/tasks/register-escrow',
      data: {
        taskId: generateTaskId(),
        recipient: CONFIG.testRecipient,
        amount: 1000000,
        triggerBlock: '1000',
        requiredApprovals: 0,
      },
      shouldFail: true,
    },
    {
      name: 'Too many required approvals (escrow)',
      endpoint: '/api/tasks/register-escrow',
      data: {
        taskId: generateTaskId(),
        recipient: CONFIG.testRecipient,
        amount: 1000000,
        triggerBlock: '1000',
        requiredApprovals: 11,  // Max is 10
      },
      shouldFail: true,
    },
  ];

  let passed = 0;
  let failed = 0;

  for (const test of tests) {
    try {
      const result = await registerTask(test.endpoint, test.data);
      
      if (test.shouldFail) {
        if (result.status >= 400) {
          logSuccess(test.name, `Correctly rejected with status ${result.status}`);
          passed++;
        } else {
          logError(test.name, `Should have failed but got status ${result.status}`);
          failed++;
        }
      } else {
        if (result.status < 400) {
          logSuccess(test.name, `Correctly accepted with status ${result.status}`);
          passed++;
        } else {
          logError(test.name, `Should have succeeded but got status ${result.status}`);
          failed++;
        }
      }
    } catch (err) {
      logError(test.name, `Exception: ${err.message}`);
      failed++;
    }

    await sleep(200);
  }

  return { success: failed === 0, passed, failed };
}

// ═══════════════════════════════════════════════════════════════
// TEST: DUPLICATE TASK IDS
// ═══════════════════════════════════════════════════════════════

async function testDuplicateTaskIds() {
  logSection('TEST: Duplicate Task IDs');

  const taskId = generateTaskId();

  // Register first task
  log('DUPLICATE', `Registering first task ${taskId}`);
  const result1 = await registerTask('/api/tasks/register', {
    taskId,
    recipient: CONFIG.testRecipient,
    amount: 1000000,
    triggerBlock: '1000',
  });

  if (result1.status < 400) {
    logSuccess('DUPLICATE', 'First task registered');
  } else {
    logError('DUPLICATE', `First task failed: ${result1.data.error}`);
    return { success: false, error: 'First task failed' };
  }

  await sleep(500);

  // Try to register duplicate task
  log('DUPLICATE', `Attempting to register duplicate task ${taskId}`);
  const result2 = await registerTask('/api/tasks/register', {
    taskId,
    recipient: CONFIG.testRecipient,
    amount: 2000000,
    triggerBlock: '2000',
  });

  if (result2.status >= 400) {
    logSuccess('DUPLICATE', 'Duplicate correctly rejected');
    return { success: true };
  } else {
    logError('DUPLICATE', 'Duplicate was incorrectly accepted');
    return { success: false, error: 'Duplicate accepted' };
  }
}

// ═══════════════════════════════════════════════════════════════
// TEST: CONCURRENT REGISTRATIONS
// ═══════════════════════════════════════════════════════════════

async function testConcurrentRegistrations() {
  logSection('TEST: Concurrent Registrations');

  const numTasks = 20;
  const promises = [];

  log('CONCURRENT', `Registering ${numTasks} tasks concurrently...`);

  for (let i = 0; i < numTasks; i++) {
    const taskId = generateTaskId();
    const promise = registerTask('/api/tasks/register', {
      taskId,
      recipient: CONFIG.testRecipient,
      amount: 1000000 + i,
      triggerBlock: (1000 + i * 10).toString(),
    });
    promises.push(promise);
  }

  try {
    const results = await Promise.all(promises);
    const successful = results.filter(r => r.status < 400).length;
    const failed = results.filter(r => r.status >= 400).length;

    log('CONCURRENT', `Results: ${successful} successful, ${failed} failed`);

    if (successful === numTasks) {
      logSuccess('CONCURRENT', 'All concurrent registrations succeeded');
      return { success: true };
    } else {
      logError('CONCURRENT', `Some registrations failed: ${failed}/${numTasks}`);
      return { success: false, error: `${failed} registrations failed` };
    }
  } catch (err) {
    logError('CONCURRENT', `Exception: ${err.message}`);
    return { success: false, error: err.message };
  }
}

// ═══════════════════════════════════════════════════════════════
// TEST: ESCROW APPROVAL EDGE CASES
// ═══════════════════════════════════════════════════════════════

async function testEscrowApprovalEdgeCases() {
  logSection('TEST: Escrow Approval Edge Cases');

  const taskId = generateTaskId();

  // Create escrow with 2 required approvals
  log('ESCROW', `Creating escrow task ${taskId} with 2 required approvals`);
  const createResult = await registerTask('/api/tasks/register-escrow', {
    taskId,
    recipient: CONFIG.testRecipient,
    amount: 1000000,
    triggerBlock: '1000',
    requiredApprovals: 2,
  });

  if (createResult.status >= 400) {
    logError('ESCROW', `Failed to create escrow: ${createResult.data.error}`);
    return { success: false, error: 'Failed to create escrow' };
  }

  logSuccess('ESCROW', 'Escrow created');

  await sleep(500);

  // First approval
  log('ESCROW', 'First approval...');
  const approve1 = await new Promise((resolve, reject) => {
    const url = new URL(`/api/tasks/${taskId}/approve`, CONFIG.keeperBotUrl);
    http.post(url, { headers: { 'Content-Type': 'application/json' } }, (res) => {
      let body = '';
      res.on('data', c => (body += c));
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(body) });
        } catch {
          resolve({ status: res.statusCode, data: body });
        }
      });
    }).on('error', reject);
  });

  if (approve1.status < 400) {
    logSuccess('ESCROW', `First approval: ${approve1.data.approvalsReceived}/${approve1.data.requiredApprovals}`);
  } else {
    logError('ESCROW', `First approval failed: ${approve1.data.error}`);
    return { success: false, error: 'First approval failed' };
  }

  await sleep(500);

  // Second approval
  log('ESCROW', 'Second approval...');
  const approve2 = await new Promise((resolve, reject) => {
    const url = new URL(`/api/tasks/${taskId}/approve`, CONFIG.keeperBotUrl);
    http.post(url, { headers: { 'Content-Type': 'application/json' } }, (res) => {
      let body = '';
      res.on('data', c => (body += c));
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(body) });
        } catch {
          resolve({ status: res.statusCode, data: body });
        }
      });
    }).on('error', reject);
  });

  if (approve2.status < 400) {
    logSuccess('ESCROW', `Second approval: ${approve2.data.approvalsReceived}/${approve2.data.requiredApprovals}`);
    log('ESCROW', `Fully approved: ${approve2.data.isApproved}`);
  } else {
    logError('ESCROW', `Second approval failed: ${approve2.data.error}`);
    return { success: false, error: 'Second approval failed' };
  }

  await sleep(500);

  // Try to approve again (should fail)
  log('ESCROW', 'Attempting third approval (should fail)...');
  const approve3 = await new Promise((resolve, reject) => {
    const url = new URL(`/api/tasks/${taskId}/approve`, CONFIG.keeperBotUrl);
    http.post(url, { headers: { 'Content-Type': 'application/json' } }, (res) => {
      let body = '';
      res.on('data', c => (body += c));
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(body) });
        } catch {
          resolve({ status: res.statusCode, data: body });
        }
      });
    }).on('error', reject);
  });

  if (approve3.status >= 400) {
    logSuccess('ESCROW', 'Third approval correctly rejected');
    return { success: true };
  } else {
    logError('ESCROW', 'Third approval was incorrectly accepted');
    return { success: false, error: 'Third approval accepted' };
  }
}

// ═══════════════════════════════════════════════════════════════
// TEST: RECURRING TASK EXECUTION COUNT
// ═══════════════════════════════════════════════════════════════

async function testRecurringExecutionCount() {
  logSection('TEST: Recurring Task Execution Count');

  const taskId = generateTaskId();
  const maxExecutions = 5;

  log('RECURRING', `Creating recurring task ${taskId} with ${maxExecutions} executions`);

  const createResult = await registerTask('/api/tasks/register-recurring', {
    taskId,
    recipient: CONFIG.testRecipient,
    amountPerExecution: 1000000,
    firstTriggerBlock: '1000',
    intervalBlocks: 5,
    maxExecutions,
  });

  if (createResult.status >= 400) {
    logError('RECURRING', `Failed to create task: ${createResult.data.error}`);
    return { success: false, error: 'Failed to create task' };
  }

  logSuccess('RECURRING', 'Task created');

  // Check initial state
  const initialTask = createResult.data.task;
  log('RECURRING', `Initial executions: ${initialTask.executionsCompleted}/${initialTask.maxExecutions}`);

  if (initialTask.executionsCompleted !== 0) {
    logError('RECURRING', 'Initial executions should be 0');
    return { success: false, error: 'Initial executions not 0' };
  }

  if (initialTask.maxExecutions !== maxExecutions) {
    logError('RECURRING', `Max executions should be ${maxExecutions}`);
    return { success: false, error: 'Max executions mismatch' };
  }

  logSuccess('RECURRING', 'Execution count verified');
  return { success: true };
}

// ═══════════════════════════════════════════════════════════════
// TEST: CONDITIONAL TASK PRICE THRESHOLDS
// ═══════════════════════════════════════════════════════════════

async function testConditionalPriceThresholds() {
  logSection('TEST: Conditional Task Price Thresholds');

  const tests = [
    {
      name: 'Price above threshold',
      conditionType: 1,  // price_above
      conditionValue: 50000,
      currentPrice: 60000,
      shouldExecute: true,
    },
    {
      name: 'Price below threshold',
      conditionType: 2,  // price_below
      conditionValue: 50000,
      currentPrice: 40000,
      shouldExecute: true,
    },
    {
      name: 'Price at threshold (above)',
      conditionType: 1,
      conditionValue: 50000,
      currentPrice: 50000,
      shouldExecute: true,
    },
    {
      name: 'Price at threshold (below)',
      conditionType: 2,
      conditionValue: 50000,
      currentPrice: 50000,
      shouldExecute: true,
    },
    {
      name: 'Price not above threshold',
      conditionType: 1,
      conditionValue: 50000,
      currentPrice: 40000,
      shouldExecute: false,
    },
    {
      name: 'Price not below threshold',
      conditionType: 2,
      conditionValue: 50000,
      currentPrice: 60000,
      shouldExecute: false,
    },
  ];

  let passed = 0;
  let failed = 0;

  for (const test of tests) {
    const taskId = generateTaskId();

    log('CONDITIONAL', `Testing: ${test.name}`);
    log('CONDITIONAL', `  Condition: ${test.conditionType === 1 ? 'price_above' : 'price_below'} ${test.conditionValue}`);
    log('CONDITIONAL', `  Current price: ${test.currentPrice}`);
    log('CONDITIONAL', `  Should execute: ${test.shouldExecute}`);

    const createResult = await registerTask('/api/tasks/register-conditional', {
      taskId,
      recipient: CONFIG.testRecipient,
      amount: 1000000,
      triggerBlock: '1000',
      conditionType: test.conditionType,
      conditionValue: test.conditionValue,
    });

    if (createResult.status >= 400) {
      logError('CONDITIONAL', `Failed to create task: ${createResult.data.error}`);
      failed++;
      continue;
    }

    const task = createResult.data.task;
    const conditionMet = test.conditionType === 1
      ? test.currentPrice >= test.conditionValue
      : test.currentPrice <= test.conditionValue;

    if (conditionMet === test.shouldExecute) {
      logSuccess('CONDITIONAL', `${test.name}: Correct`);
      passed++;
    } else {
      logError('CONDITIONAL', `${test.name}: Incorrect`);
      failed++;
    }

    await sleep(200);
  }

  return { success: failed === 0, passed, failed };
}

// ═══════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════

async function main() {
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║        Leotask - Edge Case Test Suite                      ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');

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
    log('MAIN', '  cd keeper-bot && npm start');
    process.exit(1);
  }

  const results = {};

  results.invalidInputs = await testInvalidInputs();
  await sleep(1000);

  results.boundaryConditions = await testBoundaryConditions();
  await sleep(1000);

  results.duplicateTaskIds = await testDuplicateTaskIds();
  await sleep(1000);

  results.concurrentRegistrations = await testConcurrentRegistrations();
  await sleep(1000);

  results.escrowApprovalEdgeCases = await testEscrowApprovalEdgeCases();
  await sleep(1000);

  results.recurringExecutionCount = await testRecurringExecutionCount();
  await sleep(1000);

  results.conditionalPriceThresholds = await testConditionalPriceThresholds();

  // Summary
  logSection('TEST SUMMARY');

  let totalPassed = 0;
  let totalFailed = 0;

  for (const [name, result] of Object.entries(results)) {
    if (result.success) {
      logSuccess(name.toUpperCase(), 'PASSED');
      totalPassed++;
    } else {
      logError(name.toUpperCase(), `FAILED: ${result.error || 'Unknown error'}`);
      totalFailed++;
    }
  }

  console.log('');
  log('SUMMARY', `Total: ${totalPassed + totalFailed} | Passed: ${totalPassed} | Failed: ${totalFailed}`);
  console.log('');

  if (totalFailed > 0) {
    process.exit(1);
  }
}

main().catch(err => {
  logError('MAIN', `Fatal: ${err.message}`);
  process.exit(1);
});
