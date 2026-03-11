#!/usr/bin/env node

/**
 * Leotask Keeper Bot Manager
 * ==========================
 * Always-on process manager for keeper-bot.mjs.
 * Auto-restarts the bot on crash.
 *
 * API endpoints:
 *   GET  /health    - Manager health
 *   GET  /status    - Bot running state + last 30 log lines
 *   POST /start     - Start the bot
 *   POST /stop      - Stop the bot
 *   POST /restart   - Stop then start
 *   GET  /api/*     - Proxied to keeper-bot (tasks, etc.)
 *   GET  /bot-health - Proxied to keeper-bot /health
 */

import 'dotenv/config';
import http from 'http';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const CONFIG = {
  managerPort:    parseInt(process.env.MANAGER_PORT || process.env.PORT || '3000'),
  botPort:        parseInt(process.env.API_PORT || '3001'),
  frontendOrigin: process.env.FRONTEND_ORIGIN || 'http://localhost:5173',
  botScript:      process.env.BOT_SCRIPT || path.join(__dirname, 'keeper-bot.mjs'),
  logLines:       100,
};

// ═══════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════

let botProcess   = null;
let botStartedAt = null;
let botStoppedAt = null;
let recentLogs   = [];
let restartCount = 0;
let autoRestart  = true;

function log(msg) {
  const ts = new Date().toISOString().substring(11, 19);
  console.log(`[${ts}] [MGR] ${msg}`);
}

function pushLog(line) {
  recentLogs.push({ ts: new Date().toISOString(), line });
  if (recentLogs.length > CONFIG.logLines) recentLogs.shift();
}

// ═══════════════════════════════════════════════════════════════
// BOT LIFECYCLE
// ═══════════════════════════════════════════════════════════════

function isRunning() {
  return botProcess !== null && !botProcess.killed;
}

function startBot() {
  if (isRunning()) {
    log('Bot already running, ignoring start');
    return { ok: false, reason: 'already_running' };
  }

  log(`Starting: node ${CONFIG.botScript}`);
  botProcess = spawn('node', [CONFIG.botScript], {
    env: { ...process.env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  botStartedAt = new Date().toISOString();
  restartCount++;

  botProcess.stdout.on('data', (data) => {
    data.toString().split('\n').filter(Boolean).forEach(l => {
      process.stdout.write(`[BOT] ${l}\n`);
      pushLog(l);
    });
  });

  botProcess.stderr.on('data', (data) => {
    data.toString().split('\n').filter(Boolean).forEach(l => {
      process.stderr.write(`[BOT:ERR] ${l}\n`);
      pushLog(`[ERR] ${l}`);
    });
  });

  botProcess.on('exit', (code, signal) => {
    botStoppedAt = new Date().toISOString();
    log(`Bot exited — code: ${code}, signal: ${signal}`);
    botProcess = null;

    if (autoRestart && code !== 0 && signal !== 'SIGTERM') {
      log('Bot crashed — auto-restarting in 5s...');
      setTimeout(() => { if (!isRunning()) startBot(); }, 5000);
    }
  });

  botProcess.on('error', (err) => {
    log(`Spawn error: ${err.message}`);
    botProcess = null;
  });

  log(`Bot started (PID ${botProcess.pid})`);
  return { ok: true };
}

function stopBot() {
  if (!isRunning()) {
    log('Bot not running, ignoring stop');
    return { ok: false, reason: 'not_running' };
  }
  autoRestart = false;
  botProcess.kill('SIGTERM');
  log(`Bot stopped (PID ${botProcess.pid})`);
  setTimeout(() => { autoRestart = true; }, 3000);
  return { ok: true };
}

async function restartBot() {
  stopBot();
  await new Promise(r => setTimeout(r, 2000));
  return startBot();
}

// ═══════════════════════════════════════════════════════════════
// PROXY to keeper-bot
// ═══════════════════════════════════════════════════════════════

function proxyToBot(req, res) {
  return new Promise((resolve) => {
    const options = {
      hostname: 'localhost',
      port:     CONFIG.botPort,
      path:     req.url,
      method:   req.method,
      headers:  { ...req.headers, host: `localhost:${CONFIG.botPort}` },
    };

    const proxyReq = http.request(options, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
      proxyRes.on('end', resolve);
    });

    proxyReq.on('error', () => {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Bot not responding', running: isRunning() }));
      resolve();
    });

    req.method === 'GET' ? proxyReq.end() : req.pipe(proxyReq);
  });
}

// ═══════════════════════════════════════════════════════════════
// HTTP SERVER
// ═══════════════════════════════════════════════════════════════

const managerStartedAt = new Date().toISOString();

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', CONFIG.frontendOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  const url  = new URL(req.url, `http://localhost:${CONFIG.managerPort}`);
  const json = (data, code = 200) => {
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(data));
  };

  if (url.pathname === '/health' && req.method === 'GET') {
    return json({
      manager:      'ok',
      botRunning:   isRunning(),
      botPid:       botProcess?.pid ?? null,
      botStartedAt,
      botStoppedAt,
      restartCount,
      upSince:      managerStartedAt,
    });
  }

  if (url.pathname === '/status' && req.method === 'GET') {
    return json({
      running:      isRunning(),
      pid:          botProcess?.pid ?? null,
      startedAt:    botStartedAt,
      stoppedAt:    botStoppedAt,
      restartCount,
      recentLogs:   recentLogs.slice(-30),
    });
  }

  if (url.pathname === '/start' && req.method === 'POST') {
    return json({ running: isRunning(), ...startBot() });
  }

  if (url.pathname === '/stop' && req.method === 'POST') {
    return json({ running: isRunning(), ...stopBot() });
  }

  if (url.pathname === '/restart' && req.method === 'POST') {
    return json({ running: isRunning(), ...await restartBot() });
  }

  // Proxy /api/* and /bot-health to the keeper bot
  if (url.pathname.startsWith('/api/') || url.pathname === '/bot-health') {
    if (!isRunning()) return json({ error: 'Bot is not running', running: false }, 503);
    if (url.pathname === '/bot-health') req.url = '/health';
    return proxyToBot(req, res);
  }

  res.writeHead(404); res.end();
});

server.listen(CONFIG.managerPort, () => {
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║           Leotask Keeper Bot Manager                       ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');
  log(`Manager listening on port ${CONFIG.managerPort}`);
  log(`Bot script: ${CONFIG.botScript}`);
  log(`Bot port:   ${CONFIG.botPort}`);
  log('');
  log('Endpoints:');
  log(`  GET  http://localhost:${CONFIG.managerPort}/health`);
  log(`  GET  http://localhost:${CONFIG.managerPort}/status`);
  log(`  POST http://localhost:${CONFIG.managerPort}/start`);
  log(`  POST http://localhost:${CONFIG.managerPort}/stop`);
  log(`  POST http://localhost:${CONFIG.managerPort}/restart`);
  log(`  GET  http://localhost:${CONFIG.managerPort}/api/tasks    (proxied)`);
  log(`  GET  http://localhost:${CONFIG.managerPort}/bot-health   (proxied)`);
  console.log('');

  log('Auto-starting bot...');
  startBot();
});

server.on('error', err => log(`Server error: ${err.message}`));

process.on('SIGTERM', () => {
  log('Manager shutting down...');
  autoRestart = false;
  if (isRunning()) botProcess.kill('SIGTERM');
  server.close(() => process.exit(0));
});
