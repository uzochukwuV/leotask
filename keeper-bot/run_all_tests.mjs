#!/usr/bin/env node

/**
 * Leotask - Test Runner
 * =====================
 * Runs all test suites and generates a comprehensive report
 *
 * Usage:
 *   node run_all_tests.mjs              # Run all tests
 *   node run_all_tests.mjs --quick      # Run quick tests only
 *   node run_all_tests.mjs --report     # Generate HTML report
 */

import 'dotenv/config';
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ═══════════════════════════════════════════════════════════════
// CONFIG
// ═══════════════════════════════════════════════════════════════

const CONFIG = {
  testSuites: [
    {
      name: 'Feature Tests',
      file: 'test_all_features.mjs',
      args: [],
      description: 'Tests all new features: one-time, recurring, conditional, escrow, USDCx',
    },
    {
      name: 'Edge Case Tests',
      file: 'test_edge_cases.mjs',
      args: [],
      description: 'Tests edge cases, error handling, and boundary conditions',
    },
  ],
  quickTestSuites: [
    {
      name: 'Quick Feature Tests',
      file: 'test_all_features.mjs',
      args: ['--one-time', '--recurring'],
      description: 'Quick test of core features',
    },
  ],
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

// ═══════════════════════════════════════════════════════════════
// TEST RUNNER
// ═══════════════════════════════════════════════════════════════

async function runTestSuite(suite) {
  log('RUNNER', `Starting: ${suite.name}`);
  log('RUNNER', `  Description: ${suite.description}`);
  log('RUNNER', `  File: ${suite.file}`);

  const startTime = Date.now();
  let output = '';
  let error = '';
  let exitCode = 0;

  try {
    const cmd = `node ${suite.file} ${suite.args.join(' ')}`;
    log('RUNNER', `  Command: ${cmd}`);

    output = execSync(cmd, {
      cwd: __dirname,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: 300000,  // 5 minutes
    });
  } catch (err) {
    error = err.stderr || err.message;
    exitCode = err.status || 1;
    output = err.stdout || '';
  }

  const duration = Date.now() - startTime;
  const success = exitCode === 0;

  if (success) {
    logSuccess('RUNNER', `${suite.name} completed in ${duration}ms`);
  } else {
    logError('RUNNER', `${suite.name} failed in ${duration}ms`);
  }

  return {
    name: suite.name,
    description: suite.description,
    file: suite.file,
    success,
    exitCode,
    duration,
    output,
    error,
  };
}

// ═══════════════════════════════════════════════════════════════
// REPORT GENERATOR
// ═══════════════════════════════════════════════════════════════

function generateTextReport(results) {
  let report = '';
  report += '╔════════════════════════════════════════════════════════════╗\n';
  report += '║        Leotask - Test Report                               ║\n';
  report += '╚════════════════════════════════════════════════════════════╝\n';
  report += '\n';
  report += `Generated: ${new Date().toISOString()}\n`;
  report += '\n';

  const totalTests = results.length;
  const passedTests = results.filter(r => r.success).length;
  const failedTests = results.filter(r => !r.success).length;
  const totalDuration = results.reduce((sum, r) => sum + r.duration, 0);

  report += 'Summary:\n';
  report += `  Total:    ${totalTests}\n`;
  report += `  Passed:   ${passedTests}\n`;
  report += `  Failed:   ${failedTests}\n`;
  report += `  Duration: ${totalDuration}ms\n`;
  report += '\n';

  report += '═'.repeat(60) + '\n';
  report += 'Test Results:\n';
  report += '═'.repeat(60) + '\n';
  report += '\n';

  for (const result of results) {
    const status = result.success ? '✅ PASSED' : '❌ FAILED';
    report += `${status} - ${result.name}\n`;
    report += `  Description: ${result.description}\n`;
    report += `  Duration: ${result.duration}ms\n`;
    report += `  Exit Code: ${result.exitCode}\n`;

    if (!result.success && result.error) {
      report += `  Error:\n`;
      report += `    ${result.error.split('\n').join('\n    ')}\n`;
    }

    report += '\n';
  }

  return report;
}

function generateHtmlReport(results) {
  const totalTests = results.length;
  const passedTests = results.filter(r => r.success).length;
  const failedTests = results.filter(r => !r.success).length;
  const totalDuration = results.reduce((sum, r) => sum + r.duration, 0);

  let html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Leotask Test Report</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
      max-width: 1200px;
      margin: 0 auto;
      padding: 20px;
      background: #f5f5f5;
    }
    .header {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 30px;
      border-radius: 10px;
      margin-bottom: 20px;
    }
    .header h1 {
      margin: 0 0 10px 0;
    }
    .summary {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 15px;
      margin-bottom: 20px;
    }
    .summary-card {
      background: white;
      padding: 20px;
      border-radius: 10px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      text-align: center;
    }
    .summary-card h3 {
      margin: 0 0 10px 0;
      color: #666;
      font-size: 14px;
    }
    .summary-card .value {
      font-size: 32px;
      font-weight: bold;
    }
    .summary-card.passed .value { color: #10b981; }
    .summary-card.failed .value { color: #ef4444; }
    .summary-card.total .value { color: #3b82f6; }
    .summary-card.duration .value { color: #8b5cf6; }
    .test-suite {
      background: white;
      padding: 20px;
      border-radius: 10px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      margin-bottom: 15px;
    }
    .test-suite h2 {
      margin: 0 0 15px 0;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .test-suite .status {
      font-size: 14px;
      padding: 4px 8px;
      border-radius: 4px;
    }
    .test-suite .status.passed {
      background: #d1fae5;
      color: #065f46;
    }
    .test-suite .status.failed {
      background: #fee2e2;
      color: #991b1b;
    }
    .test-suite .description {
      color: #666;
      margin-bottom: 15px;
    }
    .test-suite .details {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 10px;
      font-size: 14px;
    }
    .test-suite .details .label {
      color: #999;
    }
    .test-suite .error {
      margin-top: 15px;
      padding: 15px;
      background: #fee2e2;
      border-radius: 5px;
      font-family: monospace;
      font-size: 12px;
      white-space: pre-wrap;
      overflow-x: auto;
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>Leotask Test Report</h1>
    <p>Generated: ${new Date().toISOString()}</p>
  </div>

  <div class="summary">
    <div class="summary-card total">
      <h3>Total Tests</h3>
      <div class="value">${totalTests}</div>
    </div>
    <div class="summary-card passed">
      <h3>Passed</h3>
      <div class="value">${passedTests}</div>
    </div>
    <div class="summary-card failed">
      <h3>Failed</h3>
      <div class="value">${failedTests}</div>
    </div>
    <div class="summary-card duration">
      <h3>Duration</h3>
      <div class="value">${totalDuration}ms</div>
    </div>
  </div>
`;

  for (const result of results) {
    const statusClass = result.success ? 'passed' : 'failed';
    const statusText = result.success ? 'PASSED' : 'FAILED';

    html += `
  <div class="test-suite">
    <h2>
      ${result.name}
      <span class="status ${statusClass}">${statusText}</span>
    </h2>
    <div class="description">${result.description}</div>
    <div class="details">
      <div>
        <div class="label">Duration</div>
        <div>${result.duration}ms</div>
      </div>
      <div>
        <div class="label">Exit Code</div>
        <div>${result.exitCode}</div>
      </div>
    </div>`;

    if (!result.success && result.error) {
      html += `
    <div class="error">${result.error}</div>`;
    }

    html += `
  </div>
`;
  }

  html += `
</body>
</html>`;

  return html;
}

// ═══════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════

async function main() {
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║        Leotask - Test Runner                               ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');

  const args = process.argv.slice(2);
  const quickMode = args.includes('--quick');
  const generateReport = args.includes('--report');

  const testSuites = quickMode ? CONFIG.quickTestSuites : CONFIG.testSuites;

  log('RUNNER', `Running ${testSuites.length} test suite(s)...`);
  if (quickMode) {
    log('RUNNER', 'Quick mode enabled');
  }

  const results = [];

  for (const suite of testSuites) {
    const result = await runTestSuite(suite);
    results.push(result);
    await sleep(1000);
  }

  // Generate reports
  logSection('GENERATING REPORTS');

  const textReport = generateTextReport(results);
  console.log(textReport);

  // Save text report
  const textReportPath = path.join(__dirname, 'test-report.txt');
  fs.writeFileSync(textReportPath, textReport);
  log('REPORT', `Text report saved to: ${textReportPath}`);

  if (generateReport) {
    const htmlReport = generateHtmlReport(results);
    const htmlReportPath = path.join(__dirname, 'test-report.html');
    fs.writeFileSync(htmlReportPath, htmlReport);
    log('REPORT', `HTML report saved to: ${htmlReportPath}`);
  }

  // Exit with error code if any tests failed
  const allPassed = results.every(r => r.success);
  if (!allPassed) {
    logError('RUNNER', 'Some tests failed');
    process.exit(1);
  } else {
    logSuccess('RUNNER', 'All tests passed');
  }
}

main().catch(err => {
  logError('RUNNER', `Fatal: ${err.message}`);
  process.exit(1);
});
