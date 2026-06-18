import { spawn } from 'node:child_process';
import http from 'node:http';

const port = Number(process.env.PORT || 4050);
const repoDir = process.env.OMNILUX_REPO_DIR || '/repo';
const composeFile = process.env.OMNILUX_COMPOSE_FILE || 'docker-compose.truenas.yml';
const image = process.env.OMNILUX_IMAGE || 'ghcr.io/omnilux-tv/omnilux:latest';
const token = (process.env.OMNILUX_UPDATER_TOKEN || '').trim();
const healthUrl = process.env.OMNILUX_HEALTH_URL || 'http://omnilux:4000/api/health';
const healthTimeoutMs = Number(process.env.OMNILUX_HEALTH_TIMEOUT_MS || 120000);
const healthIntervalMs = Number(process.env.OMNILUX_HEALTH_INTERVAL_MS || 3000);

const state = {
  state: 'idle',
  message: 'Updater is idle.',
  image,
  startedAt: null,
  finishedAt: null,
  log: [],
};

function appendLog(line) {
  const text = String(line || '').trim();
  if (!text) return;
  state.log.push(text);
  if (state.log.length > 80) state.log.splice(0, state.log.length - 80);
}

function send(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

function authorized(req) {
  return Boolean(token) && req.headers.authorization === `Bearer ${token}`;
}

function run(command, args) {
  appendLog(`$ ${command} ${args.join(' ')}`);
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: repoDir,
      env: {
        ...process.env,
        OMNILUX_IMAGE: image,
      },
    });

    child.stdout.on('data', (chunk) => appendLog(chunk));
    child.stderr.on('data', (chunk) => appendLog(chunk));
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(`${command} exited with code ${code}`));
    });
  });
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function waitForRuntimeHealth() {
  const deadline = Date.now() + healthTimeoutMs;
  let lastError = 'Runtime health check did not complete.';

  while (Date.now() < deadline) {
    try {
      const response = await fetch(healthUrl, {
        signal: AbortSignal.timeout(Math.min(healthIntervalMs, 5000)),
      });
      if (response.ok) {
        appendLog(`Runtime health check passed at ${healthUrl}.`);
        return;
      }
      lastError = `Runtime health returned HTTP ${response.status}.`;
    } catch (error) {
      lastError = error instanceof Error ? error.message : 'Runtime health request failed.';
    }

    appendLog(`Waiting for runtime health: ${lastError}`);
    await sleep(healthIntervalMs);
  }

  throw new Error(`Runtime did not become healthy within ${healthTimeoutMs}ms: ${lastError}`);
}

async function doUpdate() {
  state.state = 'running';
  state.message = 'Pulling latest image and recreating OmniLux.';
  state.startedAt = new Date().toISOString();
  state.finishedAt = null;
  state.log = [];

  try {
    await run('docker', ['compose', '-f', composeFile, 'pull', 'omnilux']);
    await run('docker', ['compose', '-f', composeFile, 'up', '-d', '--force-recreate', 'omnilux']);
    state.message = 'Waiting for OmniLux health check after recreate.';
    await waitForRuntimeHealth();
    state.state = 'succeeded';
    state.message = 'Update completed and OmniLux passed health checks.';
  } catch (error) {
    state.state = 'failed';
    state.message = error instanceof Error ? error.message : 'Update failed.';
    appendLog(state.message);
  } finally {
    state.finishedAt = new Date().toISOString();
  }
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/healthz') {
    send(res, 200, {
      ok: true,
      tokenConfigured: Boolean(token),
      state: state.state,
    });
    return;
  }

  if (!authorized(req)) {
    send(res, token ? 401 : 503, {
      error: token ? 'Unauthorized' : 'Updater token is not configured.',
    });
    return;
  }

  if (req.method === 'GET' && req.url === '/status') {
    send(res, 200, state);
    return;
  }

  if (req.method === 'POST' && req.url === '/update') {
    if (state.state === 'running') {
      send(res, 409, { error: 'Update already running', ...state });
      return;
    }

    void doUpdate();
    send(res, 202, {
      ...state,
      state: 'running',
      message: 'Update started.',
    });
    return;
  }

  send(res, 404, { error: 'Not found' });
});

server.listen(port, '0.0.0.0', () => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    source: 'omnilux-updater',
    message: `Updater listening on ${port}`,
    tokenConfigured: Boolean(token),
  }));
});
