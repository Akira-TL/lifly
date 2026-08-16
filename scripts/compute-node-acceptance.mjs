#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import {
  createDecipheriv,
  createPrivateKey,
  createPublicKey,
  hkdfSync,
  randomBytes,
  randomUUID,
} from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline/promises';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const bundledRuntimeRoot = resolve(projectRoot, 'runtime');
const apiBase = process.env.LIFLY_API_BASE_URL ?? 'https://lifly.babelbeast.com/api/v1';
const opaqueHelper = process.env.LIFLY_OPAQUE_CLIENT_HELPER
  ?? firstExistingPath(
    resolve(bundledRuntimeRoot, 'lifly-opaque-helper'),
    resolve(projectRoot, 'build/runtime/lifly-opaque-helper'),
  );
const bridgePath = process.env.LIFLY_LOCAL_CORE_BRIDGE_PATH
  ?? firstExistingPath(
    resolve(bundledRuntimeRoot, 'local-core-bridge/client_flutter'),
    resolve(projectRoot, 'apps/client_flutter/build/runtime/local-core-bridge/client_flutter'),
  );
const localMcpRoot = process.env.LIFLY_LOCAL_MCP_ROOT
  ?? firstExistingPath(
    resolve(bundledRuntimeRoot, 'local-mcp'),
    resolve(projectRoot, 'services/local-mcp'),
  );
const providerProjectDir = process.env.LIFLY_AI_PROVIDER_PROJECT_DIR
  ?? firstExistingPath(
    resolve(bundledRuntimeRoot, 'provider-api'),
    resolve(projectRoot, 'services/api'),
  );
const ollamaEndpoint = process.env.LIFLY_LOCAL_AI_ENDPOINT ?? 'http://127.0.0.1:11434';
const ollamaModel = process.env.LIFLY_LOCAL_AI_MODEL ?? 'qwen3.5:4b';
const deviceIdStatePath = process.env.LIFLY_ACCEPTANCE_DEVICE_ID_FILE
  ?? resolve(homedir(), '.local/state/lifly/compute-node-acceptance-device-id');
const deviceKeyStatePath = process.env.LIFLY_ACCEPTANCE_DEVICE_KEY_FILE
  ?? resolve(dirname(deviceIdStatePath), 'compute-node-acceptance-x25519.key');

const args = new Set(process.argv.slice(2));
if (args.has('--help') || args.has('-h')) {
  console.log(`Usage: node scripts/compute-node-acceptance.mjs [--check-env]\n\nInteractive mode prompts for phone and password, authenticates a stable Desktop device with OPAQUE, unwraps the Password Key Envelope in memory, and starts the encrypted Compute Node worker.\n\nEnvironment overrides:\n  LIFLY_API_BASE_URL\n  LIFLY_OPAQUE_CLIENT_HELPER\n  LIFLY_LOCAL_CORE_BRIDGE_PATH\n  LIFLY_LOCAL_AI_ENDPOINT\n  LIFLY_LOCAL_AI_MODEL\n  LIFLY_COMPUTE_NODE_MAKE_DEFAULT=true|false\n  LIFLY_ACCEPTANCE_DEVICE_ID_FILE\n  LIFLY_ACCEPTANCE_DEVICE_KEY_FILE`);
  process.exit(0);
}

await checkEnvironment();
if (args.has('--check-env')) {
  console.log('COMPUTE_NODE_ACCEPTANCE_ENV=PASS');
  process.exit(0);
}

const rl = createInterface({ input: process.stdin, output: process.stdout });
let password = '';
try {
  const phone = (await rl.question('手机号: ')).trim();
  if (!phone) throw new Error('手机号不能为空');
  password = await hiddenQuestion(rl, '密码: ');
  if (!password) throw new Error('密码不能为空');

  console.log('正在进行 OPAQUE Desktop 登录…');
  const loginStart = invokeOpaque('client_login_start', { password });
  const start = await api('/auth/login/start', {
    method: 'POST',
    body: {
      phone,
      region: 'CN',
      client_request: requiredString(loginStart.client_request, 'client_request'),
    },
  });
  if (start.protocol !== 'opaque-rfc9807' || start.protocol_version !== 1) {
    throw new Error('服务端 OPAQUE 协议版本不匹配');
  }

  const loginFinish = invokeOpaque('client_login_finish', {
    password,
    client_state: requiredString(loginStart.client_state, 'client_state'),
    server_response: requiredString(start.server_response, 'server_response'),
  });
  password = '';

  const deviceId = loadOrCreateDeviceId();
  const { privateKeyRaw, publicKeyRaw } = loadOrCreateDeviceKey();

  const makeDefaultComputeNode =
    String(process.env.LIFLY_COMPUTE_NODE_MAKE_DEFAULT ?? 'true').toLowerCase() !== 'false';

  const session = await api('/auth/login/finish', {
    method: 'POST',
    body: {
      flow_id: requiredString(start.flow_id, 'flow_id'),
      client_finish: requiredString(loginFinish.client_message, 'client_message'),
      device: {
        device_id: deviceId,
        display_name: 'Lifly Desktop Compute Node',
        platform: 'linux',
        public_key: publicKeyRaw.toString('base64'),
        capability_report: {
          protocol_version: 1,
          capabilities: ['local_ai', 'local_mcp', 'background_executor'],
          supported_tools: [],
        },
        make_default_compute_node: makeDefaultComputeNode,
      },
    },
  });
  const accessToken = requiredString(session.access_token, 'access_token');
  const accountId = requiredString(session.account?.account_id, 'account.account_id');
  if (session.device?.device_id !== deviceId || session.device?.trust_state !== 'trusted') {
    throw new Error('服务端没有返回预期的 Trusted Desktop Device');
  }
  if (makeDefaultComputeNode && session.device?.is_default_compute_node !== true) {
    throw new Error('服务端未将 Desktop Device 设为默认计算节点');
  }

  const envelopeResponse = await api('/sync/key-envelope/password', {
    token: accessToken,
  });
  const envelope = envelopeResponse.data;
  if (!envelope || envelope.account_id !== accountId) {
    throw new Error('Password Key Envelope account mismatch');
  }
  const exportKey = decodeBase64Url(requiredString(loginFinish.export_key, 'export_key'));
  const adk = unwrapPasswordEnvelope(envelope, exportKey);
  exportKey.fill(0);
  if (adk.length !== 32) throw new Error('Account Data Key length mismatch');

  console.log(`Desktop Device 已认证: ${deviceId}`);
  console.log(`Device Key 版本: ${Number(session.device?.key_version ?? 1)}`);
  console.log('能力: local_ai, local_mcp, background_executor');
  console.log(`默认计算节点: ${session.device?.is_default_compute_node === true ? '是' : '否'}`);
  console.log('正在启动 encrypted Compute Node worker…');

  const worker = spawn('bash', ['scripts/compute-node-start.sh'], {
    cwd: projectRoot,
    env: {
      ...process.env,
      LIFLY_LOCAL_CORE_BRIDGE_PATH: bridgePath,
      LIFLY_LOCAL_MCP_ROOT: localMcpRoot,
      LIFLY_AI_PROVIDER_PROJECT_DIR: providerProjectDir,
      LIFLY_API_BASE_URL: apiBase,
      LIFLY_LOCAL_AI_PROVIDER: 'ollama',
      LIFLY_LOCAL_AI_ENDPOINT: ollamaEndpoint,
      LIFLY_LOCAL_AI_MODEL: ollamaModel,
    },
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  worker.stdin.end(`${JSON.stringify({
    account_id: accountId,
    account_data_key_base64: adk.toString('base64'),
    account_data_key_version: Number(envelope.key_version ?? 1),
    device_id: deviceId,
    private_key_base64: privateKeyRaw.toString('base64'),
    access_token: accessToken,
    api_base_url: apiBase,
  })}\n`);
  adk.fill(0);
  privateKeyRaw.fill(0);

  let ready = false;
  worker.stdout.setEncoding('utf8');
  worker.stderr.setEncoding('utf8');
  worker.stdout.on('data', (chunk) => {
    process.stdout.write(chunk);
    if (!ready && chunk.includes('encrypted Compute Node worker started')) {
      ready = true;
      console.log('COMPUTE_NODE_ACCEPTANCE_READY=PASS');
      console.log('现在回到 Web → 设置 → 账号与设备，确认 Desktop 节点出现。');
    }
  });
  worker.stderr.on('data', (chunk) => process.stderr.write(chunk));
  worker.on('exit', (code, signal) => {
    if (!ready) {
      console.error(`Compute Node worker 提前退出: code=${code} signal=${signal ?? 'none'}`);
      process.exitCode = code && code !== 0 ? code : 1;
    }
  });
  process.on('SIGINT', () => {
    worker.kill('SIGINT');
  });
} finally {
  password = '';
  rl.close();
}

async function checkEnvironment() {
  if (spawnSync('uv', ['--version'], { stdio: 'ignore' }).status !== 0) {
    throw new Error('uv 不可用；Desktop Compute Node 的本地 AI Provider runtime 需要 uv');
  }
  if (!existsSync(opaqueHelper)) throw new Error(`OPAQUE helper 不存在: ${opaqueHelper}`);
  if (!existsSync(bridgePath)) throw new Error(`Local Core bridge 不存在: ${bridgePath}`);
  if (!existsSync(resolve(localMcpRoot, 'dist/services/local-mcp/src/relay-worker-main.js'))) {
    throw new Error(`Compute Node worker 不存在: ${localMcpRoot}`);
  }
  if (!existsSync(resolve(providerProjectDir, 'pyproject.toml'))) {
    throw new Error(`AI Provider runtime 不存在: ${providerProjectDir}`);
  }
  const health = await fetch(`${apiBase}/health`);
  if (!health.ok) throw new Error(`公网 API 不可用: HTTP ${health.status}`);
  const tagsResponse = await fetch(`${ollamaEndpoint.replace(/\/$/, '')}/api/tags`);
  if (!tagsResponse.ok) throw new Error(`Ollama 不可用: HTTP ${tagsResponse.status}`);
  const tags = await tagsResponse.json();
  const models = Array.isArray(tags.models) ? tags.models : [];
  if (!models.some((item) => item?.name === ollamaModel || item?.model === ollamaModel)) {
    throw new Error(`Ollama 模型未安装: ${ollamaModel}`);
  }
}

async function hiddenQuestion(rl, prompt) {
  const canHide = process.stdin.isTTY && process.stdout.isTTY;
  if (!canHide) return (await rl.question(prompt)).trim();
  process.stdout.write(prompt);
  spawnSync('stty', ['-echo'], { stdio: ['inherit', 'ignore', 'ignore'] });
  try {
    const value = await rl.question('');
    process.stdout.write('\n');
    return value.trim();
  } finally {
    spawnSync('stty', ['echo'], { stdio: ['inherit', 'ignore', 'ignore'] });
  }
}

function loadOrCreateDeviceId() {
  if (existsSync(deviceIdStatePath)) {
    const stored = readFileSync(deviceIdStatePath, 'utf8').trim();
    if (/^[0-9a-f-]{36}$/i.test(stored)) {
      chmodSync(deviceIdStatePath, 0o600);
      return stored;
    }
    throw new Error(`Desktop device_id 状态文件无效: ${deviceIdStatePath}`);
  }
  const deviceId = randomUUID();
  mkdirSync(dirname(deviceIdStatePath), { recursive: true, mode: 0o700 });
  writeFileSync(deviceIdStatePath, `${deviceId}\n`, { mode: 0o600 });
  return deviceId;
}

function loadOrCreateDeviceKey() {
  let privateKeyRaw;
  if (existsSync(deviceKeyStatePath)) {
    privateKeyRaw = Buffer.from(readFileSync(deviceKeyStatePath, 'utf8').trim(), 'base64');
    if (privateKeyRaw.length !== 32) {
      privateKeyRaw.fill(0);
      throw new Error(`Desktop X25519 key 状态文件无效: ${deviceKeyStatePath}`);
    }
    chmodSync(deviceKeyStatePath, 0o600);
  } else {
    privateKeyRaw = randomBytes(32);
    mkdirSync(dirname(deviceKeyStatePath), { recursive: true, mode: 0o700 });
    writeFileSync(deviceKeyStatePath, `${privateKeyRaw.toString('base64')}\n`, { mode: 0o600 });
  }

  const privateKey = createPrivateKey({
    key: Buffer.concat([
      Buffer.from('302e020100300506032b656e04220420', 'hex'),
      privateKeyRaw,
    ]),
    format: 'der',
    type: 'pkcs8',
  });
  const publicDer = createPublicKey(privateKey).export({ format: 'der', type: 'spki' });
  const publicKeyRaw = Buffer.from(publicDer).subarray(-32);
  if (publicKeyRaw.length !== 32) {
    privateKeyRaw.fill(0);
    throw new Error('X25519 public key derivation failed');
  }
  return { privateKeyRaw, publicKeyRaw };
}

function invokeOpaque(operation, payload) {
  const request = JSON.stringify({
    protocol: 'opaque-rfc9807',
    protocol_version: 1,
    operation,
    ...payload,
  });
  const result = spawnSync(opaqueHelper, [], {
    input: request,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  if (result.status !== 0) {
    throw new Error(`OPAQUE helper failed during ${operation}`);
  }
  const decoded = JSON.parse(result.stdout);
  if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) {
    throw new Error('OPAQUE helper returned invalid JSON');
  }
  return decoded;
}

async function api(path, { method = 'GET', body, token } = {}) {
  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let data = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`${method} ${path} 返回非 JSON，HTTP ${response.status}`);
  }
  if (!response.ok) {
    const detail = typeof data?.detail === 'string' ? data.detail : `HTTP ${response.status}`;
    throw new Error(`${method} ${path} 失败：${detail}`);
  }
  return data;
}

function unwrapPasswordEnvelope(envelope, exportKey) {
  if (Number(envelope.encryption_version) !== 1) {
    throw new Error(`不支持的 Password Key Envelope version: ${envelope.encryption_version}`);
  }
  const accountId = requiredString(envelope.account_id, 'envelope.account_id');
  const keyVersion = Number(envelope.key_version);
  if (!Number.isInteger(keyVersion) || keyVersion < 1) {
    throw new Error('Password Key Envelope key_version 无效');
  }
  const salt = Buffer.from(`lifly/adk-wrapping-key/v1/account/${accountId}`, 'utf8');
  const info = Buffer.from(`lifly/adk-wrapping-key/v1/key-version/${keyVersion}`, 'utf8');
  const wrappingKey = Buffer.from(hkdfSync('sha256', exportKey, salt, info, 32));
  const nonce = decodeBase64Url(requiredString(envelope.nonce, 'envelope.nonce'));
  const sealed = decodeBase64Url(requiredString(envelope.ciphertext, 'envelope.ciphertext'));
  if (sealed.length <= 16) throw new Error('Password Key Envelope ciphertext truncated');
  const cipherText = sealed.subarray(0, sealed.length - 16);
  const tag = sealed.subarray(sealed.length - 16);
  const aad = Buffer.from(JSON.stringify({
    domain: 'lifly/password-key-envelope/v1',
    account_id: accountId,
    key_version: keyVersion,
    encryption_version: 1,
  }), 'utf8');
  try {
    const decipher = createDecipheriv('aes-256-gcm', wrappingKey, nonce);
    decipher.setAAD(aad);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(cipherText), decipher.final()]);
  } finally {
    wrappingKey.fill(0);
  }
}

function decodeBase64Url(value) {
  return Buffer.from(value, 'base64url');
}

function firstExistingPath(...candidates) {
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  return candidates[0];
}

function requiredString(value, name) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`${name} 缺失`);
  }
  return value;
}
