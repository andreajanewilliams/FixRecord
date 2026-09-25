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
  delete process.env.REVENUECAT_SECRET_API_KEY;
  delete process.env.OPENAI_MODEL;
  process.env.OPENAI_API_KEY = 'test-only-key';
});

after(() => {
  globalThis.fetch = originalFetch;
  process.env = originalEnvironment;
});

function request(overrides = {}) {
  return {
    method: 'POST', headers: {}, socket: { remoteAddress: '127.0.0.1' },
    body: {
      installId: crypto.randomUUID(), jobId: crypto.randomUUID(),
      jobTitle: 'Kitchen Sink Repair', issueDescription: 'A leaking connection',
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

test('Luna request includes labelled photos and keeps job identifiers out of model input', async () => {
  const req = request({ beforeImage: jpeg, afterImage: jpeg });
  req.body.revenueCatAppUserId = req.body.installId;
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
  assert.ok(!JSON.stringify(upstream).includes(req.body.installId));
  assert.ok(!JSON.stringify(upstream).includes(req.body.jobId));
});

test('rejects requests with no work evidence or invalid image data before spending quota', async () => {
  globalThis.fetch = async () => { throw new Error('invalid inputs must not reach the model'); };
  for (const overrides of [{}, { beforeImage: Buffer.from('not a jpeg').toString('base64') }, { beforeImage: Buffer.from([0xff, 0xd8, 0xff, 0xd9]).toString('base64') }]) {
    const req = request(overrides);
    req.body.revenueCatAppUserId = req.body.installId;
    const res = response();
    await handler(req, res);
    assert.equal(res.statusCode, 400);
  }
});

test('limits an IP before decoding another photo', async () => {
  for (let count = 0; count < 31; count++) {
    const req = request({ beforeImage: Buffer.from([0xff, 0xd8, 0xff, 0xd9]).toString('base64') });
    req.socket.remoteAddress = '192.0.2.77';
    req.body.revenueCatAppUserId = req.body.installId;
    const res = response();
    await handler(req, res);
    assert.equal(res.statusCode, count < 30 ? 400 : 429);
  }
});

test('returns a setup error without an API key and rejects incomplete model output', async () => {
  const req = request({ roughNotes: 'Replaced the washer.' });
  req.body.revenueCatAppUserId = req.body.installId;
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
