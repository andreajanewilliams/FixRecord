import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import sharp from 'sharp';
import handler from '../.test-dist/api/generate-report.js';

const originalFetch = globalThis.fetch;
const originalEnvironment = { ...process.env };
const jpeg = (await sharp({ create: { width: 4, height: 4, channels: 3, background: '#ffffff' } }).jpeg().toBuffer()).toString('base64');

before(() => {
  delete process.env.VERCEL;
  delete process.env.UPSTASH_REDIS_REST_URL;
  delete process.env.UPSTASH_REDIS_REST_TOKEN;
  delete process.env.UPSTASH_REDIS_REST_KV_REST_API_URL;
  delete process.env.UPSTASH_REDIS_REST_KV_REST_API_TOKEN;
  delete process.env.OPENAI_MODEL;
  process.env.OPENAI_API_KEY = 'test-only-key';
  process.env.AI_ACCESS_CODES = 'test-code-12345678901234567890';
  delete process.env.AI_PRO_ACCESS_CODES;
});

after(() => {
  globalThis.fetch = originalFetch;
  process.env = originalEnvironment;
});

function request(overrides = {}) {
  return {
    method: 'POST', headers: { 'x-fixrecord-access-code': 'test-code-12345678901234567890' }, socket: { remoteAddress: '127.0.0.1' },
    body: {
      installId: crypto.randomUUID(), jobTitle: 'Kitchen Sink Repair', issueDescription: 'A leaking connection',
      roughNotes: '', materials: [], locale: 'en-ZA',
      ...overrides
    }
  };
}

function response() {
  return {
    statusCode: 200, body: undefined,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; }
  };
}

function freshAccessCode(pro = false) {
  const code = `test-${crypto.randomUUID()}`;
  if (pro) process.env.AI_PRO_ACCESS_CODES = [process.env.AI_PRO_ACCESS_CODES, code].filter(Boolean).join(',');
  else process.env.AI_ACCESS_CODES += `,${code}`;
  return code;
}

test('Luna request includes labelled photos and keeps the access code out of model input', async () => {
  const req = request({ beforeImage: jpeg, afterImage: jpeg });
  const res = response();
  let upstream;
  globalThis.fetch = async (url, options) => {
    assert.equal(url, 'https://api.openai.com/v1/responses');
    upstream = JSON.parse(options.body);
    return new Response(JSON.stringify({
      status: 'completed',
      output: [{ content: [{ type: 'output_text', text: JSON.stringify({ reportedIssue: 'Leak reported', workCompleted: 'Visible connector changed', completionNotes: '', professionalSummary: 'The supplied photos show a visible change to the connector. Testing details were not provided.' }) }] }]
    }), { status: 200 });
  };
  await handler(req, res);
  assert.equal(res.statusCode, 200);
  assert.match(res.body.professionalSummary, /Testing details were not provided/);
  assert.equal(upstream.model, 'gpt-6-luna');
  assert.equal(upstream.reasoning.effort, 'none');
  assert.equal(upstream.store, false);
  const content = upstream.input[0].content;
  assert.deepEqual(content.map(x => x.type), ['input_text', 'input_text', 'input_image', 'input_text', 'input_image']);
  for (const part of [content[2], content[4]]) {
    assert.match(part.image_url, /^data:image\/jpeg;base64,/);
    const bytes = Buffer.from(part.image_url.split(',')[1], 'base64');
    assert.equal((await sharp(bytes).metadata()).format, 'jpeg');
  }
  assert.ok(!JSON.stringify(upstream).includes(req.headers['x-fixrecord-access-code']));
  assert.ok(!JSON.stringify(upstream).includes(req.body.installId));
});

test('rejects requests with no work evidence or invalid image data before spending quota', async () => {
  globalThis.fetch = async () => { throw new Error('invalid inputs must not reach the model'); };
  for (const overrides of [{}, { installId: 'invalid', roughNotes: 'Replaced the washer.' }, { beforeImage: Buffer.from('not a jpeg').toString('base64') }, { beforeImage: Buffer.from([0xff, 0xd8, 0xff, 0xd9]).toString('base64') }]) {
    const req = request(overrides);
    const res = response();
    await handler(req, res);
    assert.equal(res.statusCode, 400);
  }
});

test('limits an IP before decoding another photo', async () => {
  for (let count = 0; count < 31; count++) {
    const req = request({ beforeImage: Buffer.from([0xff, 0xd8, 0xff, 0xd9]).toString('base64') });
    req.socket.remoteAddress = '192.0.2.77';
    const res = response();
    await handler(req, res);
    assert.equal(res.statusCode, count < 30 ? 400 : 429);
  }
});

test('returns a setup error without an API key and rejects incomplete model output', async () => {
  const req = request({ roughNotes: 'Replaced the washer.' });
  delete process.env.OPENAI_API_KEY;
  const missing = response();
  await handler(req, missing);
  assert.equal(missing.statusCode, 503);
  process.env.OPENAI_API_KEY = 'test-only-key';
  globalThis.fetch = async () => new Response(JSON.stringify({ status: 'incomplete', output: [] }), { status: 200 });
  const incomplete = response();
  await handler(req, incomplete);
  assert.equal(incomplete.statusCode, 502);
});

test('Free allows three AI requests per month, including retries on one job', async () => {
  const req = request({ roughNotes: 'Replaced the washer.' });
  req.headers['x-fixrecord-access-code'] = freshAccessCode();
  req.socket.remoteAddress = '192.0.2.78';
  let modelCalls = 0;
  globalThis.fetch = async () => {
    modelCalls++;
    return new Response(JSON.stringify({ status: 'completed', output: [{ content: [{ type: 'output_text', text: JSON.stringify({ reportedIssue: '', workCompleted: '', completionNotes: '', professionalSummary: 'Washer replaced.' }) }] }] }), { status: 200 });
  };
  for (let count = 1; count <= 4; count++) {
    const res = response();
    await handler(req, res);
    assert.equal(res.statusCode, count <= 3 ? 200 : 429);
  }
  assert.equal(modelCalls, 3);
});

test('an installation cannot claim Pro by changing subscriber IDs', async () => {
  const code = freshAccessCode();
  const installId = crypto.randomUUID();
  let modelCalls = 0;
  globalThis.fetch = async () => {
    modelCalls++;
    return new Response(JSON.stringify({ status: 'completed', output: [{ content: [{ type: 'output_text', text: JSON.stringify({ reportedIssue: '', workCompleted: '', completionNotes: '', professionalSummary: 'Washer replaced.' }) }] }] }), { status: 200 });
  };
  for (let count = 1; count <= 4; count++) {
    const req = request({ roughNotes: 'Replaced the washer.' });
    req.headers['x-fixrecord-access-code'] = code;
    req.body.installId = installId;
    req.body.revenueCatAppUserId = 'claimed-pro-id';
    req.socket.remoteAddress = '192.0.2.81';
    const res = response();
    await handler(req, res);
    assert.equal(res.statusCode, count <= 3 ? 200 : 429);
  }
  assert.equal(modelCalls, 3);
});

test('missing or unknown access codes never call OpenAI', async () => {
  globalThis.fetch = async () => { throw new Error('unauthorised request reached a service'); };
  for (const code of [undefined, 'unknown-code-12345678901234567890']) {
    const req = request({ roughNotes: 'Replaced the washer.' });
    req.socket.remoteAddress = '192.0.2.82';
    if (code === undefined) delete req.headers['x-fixrecord-access-code'];
    else req.headers['x-fixrecord-access-code'] = code;
    const res = response();
    await handler(req, res);
    assert.equal(res.statusCode, 401);
  }
});

test('code check distinguishes accepted and unknown codes without using an AI request', async () => {
  globalThis.fetch = async () => { throw new Error('code check must not reach the model'); };
  const accepted = request();
  accepted.socket.remoteAddress = '192.0.2.83';
  accepted.body = {};
  const acceptedResponse = response();
  await handler(accepted, acceptedResponse);
  assert.equal(acceptedResponse.statusCode, 400);

  const unknown = request();
  unknown.socket.remoteAddress = '192.0.2.84';
  unknown.headers['x-fixrecord-access-code'] = 'unknown-code-12345678901234567890';
  unknown.body = {};
  const unknownResponse = response();
  await handler(unknown, unknownResponse);
  assert.equal(unknownResponse.statusCode, 401);
});

test('hosted Redis quota blocks a fourth Free request before OpenAI is called', async () => {
  process.env.VERCEL = '1';
  process.env.UPSTASH_REDIS_REST_KV_REST_API_URL = 'https://example.upstash.io';
  process.env.UPSTASH_REDIS_REST_KV_REST_API_TOKEN = 'test-only-token';
  const counters = new Map();
  const req = request({ roughNotes: 'Replaced the washer.' });
  req.headers['x-fixrecord-access-code'] = freshAccessCode();
  req.headers['x-vercel-forwarded-for'] = '192.0.2.80';
  let modelCalls = 0;
  globalThis.fetch = async (url, options) => {
    if (url === 'https://example.upstash.io/pipeline') {
      assert.equal(options.headers.Authorization, 'Bearer test-only-token');
      const commands = JSON.parse(options.body);
      return new Response(JSON.stringify(commands.map(([command, key, ...args]) => {
        if (command === 'EVAL') {
          const [, monthlyKey, totalKey, limit, totalLimit] = args;
          assert.equal(totalLimit, 1000);
          assert.match(key, /total >= tonumber\(ARGV\[2\]\)/);
          if ((counters.get(monthlyKey) ?? 0) >= limit || (counters.get(totalKey) ?? 0) >= totalLimit) return { result: 0 };
          counters.set(monthlyKey, (counters.get(monthlyKey) ?? 0) + 1);
          counters.set(totalKey, (counters.get(totalKey) ?? 0) + 1);
          return { result: 1 };
        }
        if (command === 'INCR') {
          const value = (counters.get(key) ?? 0) + 1;
          counters.set(key, value);
          return { result: value };
        }
        return { result: 1 };
      })), { status: 200 });
    }
    assert.equal(url, 'https://api.openai.com/v1/responses');
    modelCalls++;
    return new Response(JSON.stringify({ status: 'completed', output: [{ content: [{ type: 'output_text', text: JSON.stringify({ reportedIssue: '', workCompleted: '', completionNotes: '', professionalSummary: 'Washer replaced.' }) }] }] }), { status: 200 });
  };
  try {
    for (let count = 1; count <= 4; count++) {
      const res = response();
      await handler(req, res);
      assert.equal(res.statusCode, count <= 3 ? 200 : 429);
    }
    assert.equal(modelCalls, 3);
    // A second installation shares the code but gets its own allowance.
    req.body.installId = crypto.randomUUID();
    const second = response();
    await handler(req, second);
    assert.equal(second.statusCode, 200);
    counters.set('fixrecord:judging-total', 999);
    req.body.installId = crypto.randomUUID();
    const last = response();
    await handler(req, last);
    assert.equal(last.statusCode, 200);
    req.body.installId = crypto.randomUUID();
    const exhausted = response();
    await handler(req, exhausted);
    assert.equal(exhausted.statusCode, 429);
    assert.equal(modelCalls, 5);
    assert.equal(counters.get('fixrecord:judging-total'), 1000);
  } finally {
    delete process.env.VERCEL;
    delete process.env.UPSTASH_REDIS_REST_KV_REST_API_URL;
    delete process.env.UPSTASH_REDIS_REST_KV_REST_API_TOKEN;
  }
});

test('hosted quota fails closed when an integration credential is missing', async () => {
  process.env.VERCEL = '1';
  process.env.UPSTASH_REDIS_REST_URL = 'https://legacy.upstash.io';
  process.env.UPSTASH_REDIS_REST_TOKEN = 'legacy-token';
  process.env.UPSTASH_REDIS_REST_KV_REST_API_URL = 'https://integration.upstash.io';
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { throw new Error('No request should be sent with mismatched Redis credentials'); };
  try {
    const res = response();
    await handler(request({ roughNotes: 'Replaced the washer.' }), res);
    assert.equal(res.statusCode, 503);
  } finally {
    delete process.env.VERCEL;
    delete process.env.UPSTASH_REDIS_REST_URL;
    delete process.env.UPSTASH_REDIS_REST_TOKEN;
    delete process.env.UPSTASH_REDIS_REST_KV_REST_API_URL;
    globalThis.fetch = originalFetch;
  }
});

test('a server-issued Pro access code allows thirty AI requests per month', async () => {
  const originalNow = Date.now;
  const start = originalNow();
  let minute = 0;
  Date.now = () => start + minute * 60_000;
  const req = request({ roughNotes: 'Replaced the washer.' });
  req.headers['x-fixrecord-access-code'] = freshAccessCode(true);
  req.socket.remoteAddress = '192.0.2.79';
  let modelCalls = 0;
  globalThis.fetch = async url => {
    modelCalls++;
    return new Response(JSON.stringify({ status: 'completed', output: [{ content: [{ type: 'output_text', text: JSON.stringify({ reportedIssue: '', workCompleted: '', completionNotes: '', professionalSummary: 'Washer replaced.' }) }] }] }), { status: 200 });
  };
  try {
    for (let count = 1; count <= 31; count++) {
      minute = Math.floor((count - 1) / 5);
      const res = response();
      await handler(req, res);
      assert.equal(res.statusCode, count <= 30 ? 200 : 429);
    }
    assert.equal(modelCalls, 30);
  } finally {
    Date.now = originalNow;
  }
});
