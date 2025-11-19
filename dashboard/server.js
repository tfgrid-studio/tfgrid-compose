#!/usr/bin/env node

// TFGrid Compose - Local Dashboard Backend (Phase 1)
// Thin HTTP API over existing tfgrid-compose state and commands.

const express = require('express');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const { exec } = require('child_process');
const util = require('util');
const { randomUUID } = require('crypto');
const YAML = require('yaml');

const execAsync = util.promisify(exec);

const DASHBOARD_ROOT = __dirname;
const HOME_DIR = process.env.HOME || process.env.USERPROFILE || '';
const CONFIG_DIR = path.join(HOME_DIR, '.config', 'tfgrid-compose');
const TFGRID_COMPOSE_BIN = process.env.TFGRID_COMPOSE_BIN || 'tfgrid-compose';
const PORT_FILE = path.join(DASHBOARD_ROOT, 'dashboard-port');
const COMMANDS_SCHEMA_ENV = process.env.TFGRID_COMMANDS_SCHEMA || '';
const DEFAULT_COMMANDS_SCHEMA_PATH = path.join(DASHBOARD_ROOT, '..', 'core', 'commands-schema.json');
const COMMANDS_SCHEMA_PATH = COMMANDS_SCHEMA_ENV || DEFAULT_COMMANDS_SCHEMA_PATH;

const app = express();

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(DASHBOARD_ROOT, 'public')));

// Simple in-memory job table for long-running operations (deployments)
const jobs = new Map();
// In-memory interactive shell sessions for ssh-like connections
const shells = new Map();

let commandsSchemaCache = null;

function log(...args) {
  // Prefix logs so they are recognizable when run from tfgrid-compose
  console.log('[tfgrid-dashboard]', ...args);
}

function readFileIfExists(p) {
  try {
    return fs.readFileSync(p, 'utf8');
  } catch (err) {
    return null;
  }
}

function getRegistryPath() {
  const userRegistry = path.join(HOME_DIR, '.config', 'tfgrid-compose', 'registry', 'apps.yaml');
  if (fs.existsSync(userRegistry)) return userRegistry;

  log('Registry file not found at', userRegistry);
  return null;
}

function getDeploymentsRegistryPath() {
  const p = path.join(HOME_DIR, '.config', 'tfgrid-compose', 'deployments.yaml');
  return fs.existsSync(p) ? p : null;
}

async function getApps() {
  const registryPath = getRegistryPath();
  if (!registryPath) return [];

  const content = readFileIfExists(registryPath);
  if (!content) return [];

  let doc;
  try {
    doc = YAML.parse(content);
  } catch (err) {
    log('Failed to parse registry YAML:', err.message);
    return [];
  }

  const official = (doc && doc.apps && doc.apps.official) || [];
  const community = (doc && doc.apps && doc.apps.community) || [];
  const allApps = [...official, ...community];

  return allApps.map((app) => ({
    name: app.name,
    description: app.description,
    pattern: app.pattern,
    status: app.status,
    tags: app.tags || [],
    maintainer: app.maintainer || null,
  }));
}

async function getDeployments() {
  const deploymentsPath = getDeploymentsRegistryPath();
  if (!deploymentsPath) return [];

  const content = readFileIfExists(deploymentsPath);
  if (!content) return [];

  let doc;
  try {
    doc = YAML.parse(content);
  } catch (err) {
    log('Failed to parse deployments.yaml:', err.message);
    return [];
  }

  const deployments = doc.deployments || {};
  return Object.keys(deployments).map((id) => {
    const d = deployments[id] || {};
    return {
      id,
      app_name: d.app_name || null,
      vm_ip: d.vm_ip || null,
      mycelium_ip: d.mycelium_ip || null,
      contract_id: d.contract_id || null,
      status: d.status || null,
      created_at: d.created_at || null,
    };
  });
}

const PREFERENCES_PATH = path.join(CONFIG_DIR, 'preferences.yaml');

async function ensurePreferencesFile() {
  if (fs.existsSync(PREFERENCES_PATH)) return;
  try {
    // Trigger CLI to create preferences file with defaults
    await execAsync(`${TFGRID_COMPOSE_BIN} preferences --status`, {
      cwd: HOME_DIR || process.cwd(),
    });
  } catch (err) {
    log('Warning: failed to auto-create preferences file via CLI:', err.message || err);
  }
}

async function getPreferences() {
  await ensurePreferencesFile();

  if (!fs.existsSync(PREFERENCES_PATH)) {
    return {
      whitelist: { nodes: [], farms: [] },
      blacklist: { nodes: [], farms: [] },
      preferences: { max_cpu_usage: null, max_disk_usage: null, min_uptime_days: null },
      metadata: { created: null, last_updated: null },
    };
  }

  const content = readFileIfExists(PREFERENCES_PATH);
  if (!content) {
    return {
      whitelist: { nodes: [], farms: [] },
      blacklist: { nodes: [], farms: [] },
      preferences: { max_cpu_usage: null, max_disk_usage: null, min_uptime_days: null },
      metadata: { created: null, last_updated: null },
    };
  }

  let doc;
  try {
    doc = YAML.parse(content) || {};
  } catch (err) {
    log('Failed to parse preferences.yaml:', err.message);
    return {
      whitelist: { nodes: [], farms: [] },
      blacklist: { nodes: [], farms: [] },
      preferences: { max_cpu_usage: null, max_disk_usage: null, min_uptime_days: null },
      metadata: { created: null, last_updated: null },
    };
  }

  const wl = doc.whitelist || {};
  const bl = doc.blacklist || {};
  const prefs = doc.preferences || {};
  const meta = doc.metadata || {};

  return {
    whitelist: {
      nodes: Array.isArray(wl.nodes) ? wl.nodes : [],
      farms: Array.isArray(wl.farms) ? wl.farms : [],
    },
    blacklist: {
      nodes: Array.isArray(bl.nodes) ? bl.nodes : [],
      farms: Array.isArray(bl.farms) ? bl.farms : [],
    },
    preferences: {
      max_cpu_usage: prefs.max_cpu_usage ?? null,
      max_disk_usage: prefs.max_disk_usage ?? null,
      min_uptime_days: prefs.min_uptime_days ?? null,
    },
    metadata: {
      created: meta.created ?? null,
      last_updated: meta.last_updated ?? null,
    },
  };
}

function loadCommandsSchema() {
  if (commandsSchemaCache) return commandsSchemaCache;

  try {
    const raw = fs.readFileSync(COMMANDS_SCHEMA_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    commandsSchemaCache = parsed;
    log('Loaded commands schema from', COMMANDS_SCHEMA_PATH);
    return parsed;
  } catch (err) {
    log('Failed to load commands schema from', COMMANDS_SCHEMA_PATH, '-', err.message);
    commandsSchemaCache = { version: 1, commands: [] };
    return commandsSchemaCache;
  }
}

function buildCliArgsFromCommand(def, payload) {
  const cliArgs = [];
  const argValues = (payload && payload.args) || {};
  const flagValues = (payload && payload.flags) || {};

  // Positional arguments in defined order
  (def.args || []).forEach((argDef) => {
    const val = argValues[argDef.name];
    if (val === undefined || val === null || val === '') {
      // Leave missing args for CLI to validate (required vs optional)
      return;
    }
    cliArgs.push(String(val));
  });

  // Flags
  (def.flags || []).forEach((flagDef) => {
    const name = flagDef.name;
    const val = flagValues[name];

    if (flagDef.type === 'boolean') {
      if (val === true) {
        cliArgs.push(`--${name}`);
      }
    } else {
      if (val !== undefined && val !== null && String(val) !== '') {
        cliArgs.push(`--${name}=${val}`);
      }
    }
  });

  return cliArgs;
}

function spawnJob(command, args) {
  const { spawn } = require('child_process');

  const jobId = randomUUID();
  const proc = spawn(command, args, {
    cwd: HOME_DIR || process.cwd(),
    env: { ...process.env },
    shell: false,
  });

  const job = {
    id: jobId,
    command: [command, ...args].join(' '),
    status: 'running',
    created_at: new Date().toISOString(),
    completed_at: null,
    exit_code: null,
    deployment_id: null,
    logs: [],
  };

  jobs.set(jobId, job);

  proc.stdout.on('data', (chunk) => {
    const text = chunk.toString();
    job.logs.push(text);

    // Try to capture deployment ID from standard orchestrator log line
    const match = text.match(/Registered deployment: ([a-f0-9]{16})/);
    if (match && !job.deployment_id) {
      job.deployment_id = match[1];
    }
  });

  proc.stderr.on('data', (chunk) => {
    const text = chunk.toString();
    job.logs.push(text);
  });

  proc.on('close', (code) => {
    job.exit_code = code;
    job.status = code === 0 ? 'completed' : 'failed';
    job.completed_at = new Date().toISOString();
  });

  proc.on('error', (err) => {
    job.exit_code = -1;
    job.status = 'failed';
    job.completed_at = new Date().toISOString();
    job.logs.push(`ERROR: ${err.message}`);
  });

  return job;
}

function createShellSession(deploymentId) {
  const { spawn } = require('child_process');

  const sessionId = randomUUID();
  const proc = spawn(TFGRID_COMPOSE_BIN, ['ssh', deploymentId], {
    cwd: HOME_DIR || process.cwd(),
    env: { ...process.env },
    shell: false,
  });

  const session = {
    id: sessionId,
    deployment_id: deploymentId,
    proc,
    streams: new Set(),
    buffer: [],
    closed: false,
  };

  function broadcastChunk(chunk) {
    const text = chunk.toString();
    session.buffer.push(text);
    session.streams.forEach((res) => {
      text.split(/\r?\n/).forEach((line) => {
        res.write(`data: ${line}\n\n`);
      });
    });
  }

  proc.stdout.on('data', (chunk) => {
    broadcastChunk(chunk);
  });

  proc.stderr.on('data', (chunk) => {
    broadcastChunk(chunk);
  });

  proc.on('close', (code) => {
    session.closed = true;
    session.streams.forEach((res) => {
      res.write(`event: close\n`);
      res.write(`data: ${code}\n\n`);
      res.end();
    });
    session.streams.clear();
    shells.delete(sessionId);
  });

  proc.on('error', (err) => {
    session.closed = true;
    session.streams.forEach((res) => {
      res.write('event: close\n');
      res.write(`data: ERROR: ${err.message}\n\n`);
      res.end();
    });
    session.streams.clear();
    shells.delete(sessionId);
  });

  shells.set(sessionId, session);
  log('Started shell session', sessionId, 'for deployment', deploymentId);
  return session;
}

// Routes

// List available tfgrid-compose commands from shared schema
app.get('/api/commands', (req, res) => {
  try {
    const schema = loadCommandsSchema();
    res.json(schema);
  } catch (err) {
    log('Error in /api/commands:', err.message || err);
    res.status(500).json({ error: 'Failed to load commands schema' });
  }
});

// Read-only preferences view (whitelist/blacklist + basic thresholds)
app.get('/api/preferences', async (req, res) => {
  try {
    const prefs = await getPreferences();
    res.json(prefs);
  } catch (err) {
    log('Error in /api/preferences:', err.message || err);
    res.status(500).json({ error: 'Failed to load preferences' });
  }
});

// List registry apps
app.get('/api/apps', async (req, res) => {
  try {
    const apps = await getApps();
    res.json({ apps });
  } catch (err) {
    log('Error in /api/apps:', err);
    res.status(500).json({ error: 'Failed to load apps' });
  }
});

// Generic command runner (spawns tfgrid-compose with args/flags from schema)
app.post('/api/commands/run', (req, res) => {
  try {
    const schema = loadCommandsSchema();
    const commands = (schema && schema.commands) || [];
    const body = req.body || {};
    const commandId = body.commandId;

    if (!commandId || typeof commandId !== 'string') {
      return res.status(400).json({ error: 'commandId is required' });
    }

    const commandDef = commands.find((c) => c.id === commandId || c.command === commandId);
    if (!commandDef) {
      return res.status(404).json({ error: `Unknown command: ${commandId}` });
    }

    const cliArgs = [commandDef.command, ...buildCliArgsFromCommand(commandDef, body)];
    const job = spawnJob(TFGRID_COMPOSE_BIN, cliArgs);
    log('Started generic command job', job.id, '->', job.command);

    res.status(202).json({
      job_id: job.id,
      status: job.status,
      command: job.command,
    });
  } catch (err) {
    log('Error in /api/commands/run:', err.message || err);
    res.status(500).json({ error: 'Failed to start command', details: err.message || String(err) });
  }
});

// Start interactive shell session (tfgrid-compose ssh <deploymentId>)
app.post('/api/deployments/:id/shell', (req, res) => {
  const id = req.params.id;
  try {
    const session = createShellSession(id);
    res.status(201).json({ session_id: session.id, deployment_id: session.deployment_id });
  } catch (err) {
    log('Error in /api/deployments/:id/shell:', err.message || err);
    res.status(500).json({ error: 'Failed to start shell session', details: err.message || String(err) });
  }
});

// Stream shell output via Server-Sent Events
app.get('/api/shells/:id/stream', (req, res) => {
  const id = req.params.id;
  const session = shells.get(id);
  if (!session || session.closed) {
    res.status(404).end();
    return;
  }

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders && res.flushHeaders();

  session.streams.add(res);

  // Replay buffered output for late joiners
  if (session.buffer.length) {
    session.buffer.forEach((chunk) => {
      chunk.split(/\r?\n/).forEach((line) => {
        res.write(`data: ${line}\n\n`);
      });
    });
  }

  req.on('close', () => {
    session.streams.delete(res);
  });
});

// Send input to shell session stdin
app.post('/api/shells/:id/input', (req, res) => {
  const id = req.params.id;
  const session = shells.get(id);
  if (!session || session.closed) {
    return res.status(404).json({ error: 'Shell session not found' });
  }

  const body = req.body || {};
  const data = typeof body.data === 'string' ? body.data : '';
  try {
    if (data) session.proc.stdin.write(data);
    res.status(204).end();
  } catch (err) {
    log('Error writing to shell stdin:', err.message || err);
    res.status(500).json({ error: 'Failed to send input' });
  }
});

// Close shell session explicitly
app.post('/api/shells/:id/close', (req, res) => {
  const id = req.params.id;
  const session = shells.get(id);
  if (session && !session.closed) {
    try {
      session.proc.kill();
    } catch (err) {
      log('Error killing shell session', id, '-', err.message || err);
    }
  }
  shells.delete(id);
  res.status(204).end();
});

// List deployments
app.get('/api/deployments', async (req, res) => {
  try {
    const deployments = await getDeployments();
    res.json({ deployments });
  } catch (err) {
    log('Error in /api/deployments:', err);
    res.status(500).json({ error: 'Failed to load deployments' });
  }
});

// Get single deployment metadata
app.get('/api/deployments/:id', async (req, res) => {
  try {
    const deployments = await getDeployments();
    const deployment = deployments.find((d) => d.id === req.params.id);
    if (!deployment) {
      return res.status(404).json({ error: 'Deployment not found' });
    }
    res.json({ deployment });
  } catch (err) {
    log('Error in /api/deployments/:id:', err);
    res.status(500).json({ error: 'Failed to load deployment' });
  }
});

// Get address/URLs for a deployment (wraps tfgrid-compose address)
app.get('/api/deployments/:id/address', async (req, res) => {
  const id = req.params.id;
  try {
    const { stdout, stderr } = await execAsync(`${TFGRID_COMPOSE_BIN} address ${id}`, {
      cwd: HOME_DIR || process.cwd(),
    });

    res.json({
      output: stdout,
      error: stderr || null,
    });
  } catch (err) {
    log('Error running address for', id, '-', err.message);
    res.status(500).json({ error: 'Failed to get address', details: err.message });
  }
});

// Start a deployment job (tfgrid-compose up <appName>)
app.post('/api/deployments', (req, res) => {
  const body = req.body || {};
  const appName = body.appName;

  if (!appName || typeof appName !== 'string') {
    return res.status(400).json({ error: 'appName is required' });
  }

  const job = spawnJob(TFGRID_COMPOSE_BIN, ['up', appName]);
  log('Started deployment job', job.id, 'for app', appName);

  res.status(202).json({
    job_id: job.id,
    status: job.status,
    command: job.command,
  });
});

// Get job status/logs
app.get('/api/jobs/:id', (req, res) => {
  const job = jobs.get(req.params.id);
  if (!job) {
    return res.status(404).json({ error: 'Job not found' });
  }

  res.json({
    id: job.id,
    status: job.status,
    command: job.command,
    created_at: job.created_at,
    completed_at: job.completed_at,
    exit_code: job.exit_code,
    deployment_id: job.deployment_id,
    logs: job.logs,
  });
});

// Create project on a specific deployment (tfgrid-compose select + create)
app.post('/api/deployments/:id/create', async (req, res) => {
  const id = req.params.id;
  const body = req.body || {};
  const projectName = body.projectName;

  if (!projectName || typeof projectName !== 'string') {
    return res.status(400).json({ error: 'projectName is required' });
  }

  try {
    await execAsync(`${TFGRID_COMPOSE_BIN} select ${id}`, {
      cwd: HOME_DIR || process.cwd(),
    });
  } catch (err) {
    log('Error selecting deployment for create', id, '-', err.message);
    return res.status(500).json({ error: 'Failed to select deployment', details: err.message });
  }

  const job = spawnJob(TFGRID_COMPOSE_BIN, ['create', projectName]);
  log('Started create job', job.id, 'for deployment', id, 'project', projectName);

  res.status(202).json({
    job_id: job.id,
    status: job.status,
    command: job.command,
  });
});

// Run project on a specific deployment (tfgrid-compose select + run)
app.post('/api/deployments/:id/run', async (req, res) => {
  const id = req.params.id;
  const body = req.body || {};
  const projectName = body.projectName;

  if (!projectName || typeof projectName !== 'string') {
    return res.status(400).json({ error: 'projectName is required' });
  }

  try {
    await execAsync(`${TFGRID_COMPOSE_BIN} select ${id}`, {
      cwd: HOME_DIR || process.cwd(),
    });
  } catch (err) {
    log('Error selecting deployment for run', id, '-', err.message);
    return res.status(500).json({ error: 'Failed to select deployment', details: err.message });
  }

  const job = spawnJob(TFGRID_COMPOSE_BIN, ['run', projectName]);
  log('Started run job', job.id, 'for deployment', id, 'project', projectName);

  res.status(202).json({
    job_id: job.id,
    status: job.status,
    command: job.command,
  });
});

// Publish project on a specific deployment (tfgrid-compose select + publish)
app.post('/api/deployments/:id/publish', async (req, res) => {
  const id = req.params.id;
  const body = req.body || {};
  const projectName = body.projectName;

  if (!projectName || typeof projectName !== 'string') {
    return res.status(400).json({ error: 'projectName is required' });
  }

  try {
    await execAsync(`${TFGRID_COMPOSE_BIN} select ${id}`, {
      cwd: HOME_DIR || process.cwd(),
    });
  } catch (err) {
    log('Error selecting deployment for publish', id, '-', err.message);
    return res.status(500).json({ error: 'Failed to select deployment', details: err.message });
  }

  const job = spawnJob(TFGRID_COMPOSE_BIN, ['publish', projectName]);
  log('Started publish job', job.id, 'for deployment', id, 'project', projectName);

  res.status(202).json({
    job_id: job.id,
    status: job.status,
    command: job.command,
  });
});

// Fallback route - serve SPA shell
app.get('*', (req, res) => {
  res.sendFile(path.join(DASHBOARD_ROOT, 'public', 'index.html'));
});

function writePortFile(port) {
  try {
    fs.writeFileSync(PORT_FILE, String(port), 'utf8');
  } catch (err) {
    log('Failed to write port file:', err.message);
  }
}

function startServer(port, remainingTries) {
  const server = app.listen(port, () => {
    log(`Dashboard server started on http://localhost:${port}`);
    log(`Config directory: ${CONFIG_DIR}`);
    log(`TFGRID_COMPOSE_BIN: ${TFGRID_COMPOSE_BIN}`);
    const registryPath = getRegistryPath();
    const deploymentsPath = getDeploymentsRegistryPath();
    log(`Registry path: ${registryPath || 'not found'}`);
    log(`Deployments registry path: ${deploymentsPath || 'not found'}`);
    writePortFile(port);
  });

  server.on('error', (err) => {
    if (err && err.code === 'EADDRINUSE' && remainingTries > 0) {
      const nextPort = port + 1;
      log(`Port ${port} in use, trying ${nextPort}...`);
      startServer(nextPort, remainingTries - 1);
    } else {
      log('Failed to start dashboard server:', err && err.message ? err.message : err);
      process.exit(1);
    }
  });
}

const BASE_PORT = parseInt(process.env.TFGRID_DASHBOARD_PORT || '43100', 10);
startServer(BASE_PORT, 20);
