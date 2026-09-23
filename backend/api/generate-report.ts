import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createHash } from 'node:crypto';

type Input = { installId: string; jobId: string; revenueCatAppUserId: string; jobTitle: string; issueDescription: string; roughNotes: string; materials?: string[]; locale?: string };
const required = ['reportedIssue', 'workCompleted', 'completionNotes', 'professionalSummary'] as const;
const memory = new Map<string, { minute: number; day: number; month: number; minuteCount: number; dayCount: number; jobs: Map<string, number> }>();
const ipMemory = new Map<string, { minute: number; day: number; minuteCount: number; dayCount: number }>();

function valid(body: unknown): body is Input {
  if (!body || typeof body !== 'object') return false;
  const value = body as Record<string, unknown>;
  return typeof value.installId === 'string' && /^[a-f0-9-]{36}$/i.test(value.installId)
    && typeof value.jobId === 'string' && /^[a-f0-9-]{36}$/i.test(value.jobId)
    && value.revenueCatAppUserId === value.installId
    && typeof value.jobTitle === 'string' && value.jobTitle.length <= 150
    && typeof value.issueDescription === 'string' && value.issueDescription.length <= 1000
    && typeof value.roughNotes === 'string' && value.roughNotes.length > 0 && value.roughNotes.length <= 3000
    && (!value.materials || (Array.isArray(value.materials) && value.materials.length <= 30 && value.materials.every(x => typeof x === 'string' && x.length <= 80)))
    && (!value.locale || (typeof value.locale === 'string' && value.locale.length <= 40));
}

async function isPro(appUserId: string): Promise<boolean> {
  const secret = process.env.REVENUECAT_SECRET_API_KEY;
  if (!secret) return false;
  try {
    const response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`, { headers: { Authorization: `Bearer ${secret}` }, signal: AbortSignal.timeout(4000) });
    if (!response.ok) return false;
    const data = await response.json() as { subscriber?: { entitlements?: { pro?: { expires_date?: string | null } } } };
    const entitlement = data.subscriber?.entitlements?.pro;
    return !!entitlement && (!entitlement.expires_date || Date.parse(entitlement.expires_date) > Date.now());
  } catch { return false; }
}

async function allowed(key: string, ipKey: string, installId: string, jobId: string, appUserId: string): Promise<boolean> {
  const now = Date.now();
  const minute = Math.floor(now / 60000), day = Math.floor(now / 86400000);
  const month = new Date(now).getUTCFullYear() * 12 + new Date(now).getUTCMonth();
  // Production deployments must configure a shared Redis endpoint: per-instance memory is not a safe global limit.
  const url = process.env.UPSTASH_REDIS_REST_URL, token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (url && token) {
    const redis = async (commands: (string | number)[][]) => {
      const response = await fetch(`${url}/pipeline`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(commands) });
      if (!response.ok) throw new Error('Usage service unavailable');
      return response.json() as Promise<Array<{ result?: number }>>;
    };
    for (const [bucket, max, ttl] of [[`minute:${minute}`, 6, 120], [`day:${day}`, 100, 172800]] as const) {
      const redisKey = `fixrecord:${bucket}:${key}`;
      const result = await redis([['INCR', redisKey], ['EXPIRE', redisKey, ttl]]);
      if ((result?.[0]?.result ?? max + 1) > max) return false;
    }
    // The installation ID is client controlled. An independent IP limit prevents ID rotation
    // from exhausting the shared AI budget. Vercel supplies the trusted client IP header.
    for (const [bucket, max, ttl] of [[`ip-minute:${minute}`, 30, 120], [`ip-day:${day}`, 100, 172800]] as const) {
      const result = await redis([['INCR', `fixrecord:${bucket}:${ipKey}`], ['EXPIRE', `fixrecord:${bucket}:${ipKey}`, ttl]]);
      if ((result?.[0]?.result ?? max + 1) > max) return false;
    }
    const global = await redis([['INCR', `fixrecord:global:${day}`], ['EXPIRE', `fixrecord:global:${day}`, 172800]]);
    if ((global?.[0]?.result ?? 1001) > 1000) return false;
    const monthlyJobLimit = await isPro(appUserId) ? 100 : 10;
    const jobsKey = `fixrecord:jobs:${month}:${installId}`;
    const countKey = `fixrecord:rewrites:${month}:${installId}:${jobId}`;
    const state = await redis([['SISMEMBER', jobsKey, jobId], ['SCARD', jobsKey]]);
    if ((state[0]?.result ?? 0) === 0 && (state[1]?.result ?? monthlyJobLimit) >= monthlyJobLimit) return false;
    const usage = await redis([['SADD', jobsKey, jobId], ['EXPIRE', jobsKey, 2678400], ['INCR', countKey], ['EXPIRE', countKey, 2678400]]);
    if ((usage[2]?.result ?? 6) > 5) return false;
    return true;
  }
  if (process.env.VERCEL) return false;
  const ipState = ipMemory.get(ipKey) ?? { minute, day, minuteCount: 0, dayCount: 0 };
  if (ipState.minute !== minute) { ipState.minute = minute; ipState.minuteCount = 0; }
  if (ipState.day !== day) { ipState.day = day; ipState.dayCount = 0; }
  ipState.minuteCount++; ipState.dayCount++; ipMemory.set(ipKey, ipState);
  if (ipState.minuteCount > 30 || ipState.dayCount > 100) return false;
  const state = memory.get(installId) ?? { minute, day, month, minuteCount: 0, dayCount: 0, jobs: new Map<string, number>() };
  if (state.minute !== minute) { state.minute = minute; state.minuteCount = 0; }
  if (state.day !== day) { state.day = day; state.dayCount = 0; }
  if (state.month !== month) { state.month = month; state.jobs.clear(); }
  state.minuteCount++; state.dayCount++;
  memory.set(installId, state);
  if (state.minuteCount > 6 || state.dayCount > 100) return false;
  const monthlyJobLimit = await isPro(appUserId) ? 100 : 10;
  const rewrites = state.jobs.get(jobId) ?? 0;
  if (rewrites === 0 && state.jobs.size >= monthlyJobLimit) return false;
  state.jobs.set(jobId, rewrites + 1);
  return rewrites < 5;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  if (!valid(req.body)) return res.status(400).json({ error: 'Invalid job facts' });
  if (!process.env.OPENAI_API_KEY || !process.env.OPENAI_MODEL) return res.status(503).json({ error: 'AI is not configured' });
  const input = req.body;
  const ip = String((process.env.VERCEL ? req.headers['x-vercel-forwarded-for'] : req.headers['x-forwarded-for']) ?? req.socket.remoteAddress ?? 'unknown').split(',')[0].trim().slice(0, 64);
  const ipKey = createHash('sha256').update(ip).digest('hex');
  const key = `${input.installId}:${ipKey}`;
  try { if (!(await allowed(key, ipKey, input.installId, input.jobId, input.revenueCatAppUserId))) return res.status(429).json({ error: 'AI limit reached' }); }
  catch { return res.status(503).json({ error: 'Usage service unavailable' }); }
  const controller = new AbortController(); const timeout = setTimeout(() => controller.abort(), 16000);
  try {
    const schema = { type: 'object', additionalProperties: false, properties: Object.fromEntries(required.map(name => [name, { type: 'string' }])), required: [...required] };
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST', signal: controller.signal,
      headers: { Authorization: `Bearer ${process.env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: process.env.OPENAI_MODEL, max_output_tokens: 350,
        instructions: 'Improve wording using only supplied facts. Do not invent work, materials, test results, compliance, certifications, safety or success. Preserve ambiguity. Avoid verified, certified, safe and fully repaired unless explicitly supplied as the worker’s statement. Return concise professional JSON.',
        input: JSON.stringify({ jobTitle: input.jobTitle, issueDescription: input.issueDescription, roughNotes: input.roughNotes, materials: input.materials ?? [], locale: input.locale ?? 'en' }),
        text: { format: { type: 'json_schema', name: 'work_note', strict: true, schema } } })
    });
    if (!response.ok) return res.status(502).json({ error: 'AI service unavailable' });
    const payload = await response.json() as { output?: Array<{ content?: Array<{ type?: string; text?: string }> }> };
    const text = payload.output?.flatMap(x => x.content ?? []).find(x => x.type === 'output_text')?.text;
    if (!text) return res.status(502).json({ error: 'AI response unavailable' });
    const result = JSON.parse(text) as Record<string, unknown>;
    if (!required.every(k => typeof result[k] === 'string' && (result[k] as string).length <= 2000)) return res.status(502).json({ error: 'AI response invalid' });
    return res.status(200).json(result);
  } catch { return res.status(502).json({ error: 'AI service unavailable' }); }
  finally { clearTimeout(timeout); }
}
