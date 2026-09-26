import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createHash } from 'node:crypto';
import sharp from 'sharp';

type Input = { installId: string; jobId: string; revenueCatAppUserId: string; jobTitle: string; issueDescription: string; roughNotes: string; materials?: string[]; locale?: string; beforeImage?: string; afterImage?: string };
const required = ['reportedIssue', 'workCompleted', 'completionNotes', 'professionalSummary'] as const;
const defaultModel = 'gpt-6-luna';
const maxImageBytes = 900_000;
const memory = new Map<string, { minute: number; day: number; month: number; minuteCount: number; dayCount: number; monthlyCount: number }>();
const ipMemory = new Map<string, { minute: number; day: number; minuteCount: number; dayCount: number }>();

function validImage(value: unknown): value is string {
  if (typeof value !== 'string' || value.length === 0 || value.length > 1_200_000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return false;
  const bytes = Buffer.from(value, 'base64');
  return bytes.length > 0 && bytes.length <= maxImageBytes && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff && bytes.toString('base64') === value;
}

async function normaliseImage(value: string | undefined): Promise<string | undefined> {
  if (!value) return undefined;
  const image = await sharp(Buffer.from(value, 'base64'), { failOn: 'warning', limitInputPixels: 4_000_000 })
    .rotate().resize(1200, 1200, { fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 75 }).toBuffer();
  if (image.length > maxImageBytes) throw new Error('Image is too large');
  return image.toString('base64');
}

function valid(body: unknown): body is Input {
  if (!body || typeof body !== 'object') return false;
  const value = body as Record<string, unknown>;
  return typeof value.installId === 'string' && /^[a-f0-9-]{36}$/i.test(value.installId)
    && typeof value.jobId === 'string' && /^[a-f0-9-]{36}$/i.test(value.jobId)
    && value.revenueCatAppUserId === value.installId
    && typeof value.jobTitle === 'string' && value.jobTitle.length <= 150
    && typeof value.issueDescription === 'string' && value.issueDescription.length <= 1000
    && typeof value.roughNotes === 'string' && value.roughNotes.length <= 3000
    && (!value.materials || (Array.isArray(value.materials) && value.materials.length <= 30 && value.materials.every(x => typeof x === 'string' && x.length <= 80)))
    && (!value.locale || (typeof value.locale === 'string' && value.locale.length <= 40))
    && (value.beforeImage === undefined || validImage(value.beforeImage))
    && (value.afterImage === undefined || validImage(value.afterImage))
    && (value.roughNotes.trim().length > 0 || value.beforeImage !== undefined || value.afterImage !== undefined);
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

async function allowedIP(ipKey: string): Promise<boolean> {
  const minute = Math.floor(Date.now() / 60000), day = Math.floor(Date.now() / 86400000);
  const url = process.env.UPSTASH_REDIS_REST_URL, token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (url && token) {
    for (const [bucket, max, ttl] of [[`ip-minute:${minute}`, 30, 120], [`ip-day:${day}`, 100, 172800]] as const) {
      const response = await fetch(`${url}/pipeline`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify([['INCR', `fixrecord:${bucket}:${ipKey}`], ['EXPIRE', `fixrecord:${bucket}:${ipKey}`, ttl]]) });
      if (!response.ok) throw new Error('Usage service unavailable');
      const result = await response.json() as Array<{ result?: number }>;
      if ((result?.[0]?.result ?? max + 1) > max) return false;
    }
    return true;
  }
  if (process.env.VERCEL) throw new Error('Usage service unavailable');
  const state = ipMemory.get(ipKey) ?? { minute, day, minuteCount: 0, dayCount: 0 };
  if (state.minute !== minute) { state.minute = minute; state.minuteCount = 0; }
  if (state.day !== day) { state.day = day; state.dayCount = 0; }
  state.minuteCount++; state.dayCount++; ipMemory.set(ipKey, state);
  return state.minuteCount <= 30 && state.dayCount <= 100;
}

async function allowed(key: string, installId: string, appUserId: string): Promise<boolean> {
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
    const global = await redis([['INCR', `fixrecord:global:${day}`], ['EXPIRE', `fixrecord:global:${day}`, 172800]]);
    if ((global?.[0]?.result ?? 1001) > 1000) return false;
    const monthlyLimit = await isPro(appUserId) ? 30 : 3;
    const usage = await redis([['INCR', `fixrecord:requests:${month}:${installId}`], ['EXPIRE', `fixrecord:requests:${month}:${installId}`, 2678400]]);
    return (usage[0]?.result ?? monthlyLimit + 1) <= monthlyLimit;
  }
  if (process.env.VERCEL) return false;
  const state = memory.get(installId) ?? { minute, day, month, minuteCount: 0, dayCount: 0, monthlyCount: 0 };
  if (state.minute !== minute) { state.minute = minute; state.minuteCount = 0; }
  if (state.day !== day) { state.day = day; state.dayCount = 0; }
  if (state.month !== month) { state.month = month; state.monthlyCount = 0; }
  state.minuteCount++; state.dayCount++; state.monthlyCount++;
  memory.set(installId, state);
  if (state.minuteCount > 6 || state.dayCount > 100) return false;
  return state.monthlyCount <= (await isPro(appUserId) ? 30 : 3);
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  if (!process.env.OPENAI_API_KEY?.trim()) return res.status(503).json({ error: 'AI is not configured' });
  // Vercel supplies the trusted client IP header. This cheap gate runs before
  // Base64 validation and image decoding, including for malformed requests.
  const ip = String((process.env.VERCEL ? req.headers['x-vercel-forwarded-for'] : req.headers['x-forwarded-for']) ?? req.socket.remoteAddress ?? 'unknown').split(',')[0].trim().slice(0, 64);
  const ipKey = createHash('sha256').update(ip).digest('hex');
  try { if (!(await allowedIP(ipKey))) return res.status(429).json({ error: 'AI limit reached' }); }
  catch { return res.status(503).json({ error: 'Usage service unavailable' }); }
  if (!valid(req.body)) return res.status(400).json({ error: 'Invalid job facts' });
  const input = req.body;
  let beforeImage: string | undefined, afterImage: string | undefined;
  try {
    beforeImage = await normaliseImage(input.beforeImage);
    afterImage = await normaliseImage(input.afterImage);
  } catch { return res.status(400).json({ error: 'Invalid job photo' }); }
  const key = `${input.installId}:${ipKey}`;
  try { if (!(await allowed(key, input.installId, input.revenueCatAppUserId))) return res.status(429).json({ error: 'AI limit reached' }); }
  catch { return res.status(503).json({ error: 'Usage service unavailable' }); }
  const controller = new AbortController(); const timeout = setTimeout(() => controller.abort(), 16000);
  try {
    const schema = { type: 'object', additionalProperties: false, properties: Object.fromEntries(required.map(name => [name, { type: 'string' }])), required: [...required] };
    const content: Array<Record<string, string>> = [
      { type: 'input_text', text: JSON.stringify({ jobTitle: input.jobTitle, issueDescription: input.issueDescription, roughNotes: input.roughNotes, materials: input.materials ?? [], locale: input.locale ?? 'en' }) }
    ];
    if (beforeImage) content.push({ type: 'input_text', text: 'Before photo (starting condition)' }, { type: 'input_image', image_url: `data:image/jpeg;base64,${beforeImage}`, detail: 'high' });
    if (afterImage) content.push({ type: 'input_text', text: 'After photo (finished condition)' }, { type: 'input_image', image_url: `data:image/jpeg;base64,${afterImage}`, detail: 'high' });
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST', signal: controller.signal,
      headers: { Authorization: `Bearer ${process.env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: process.env.OPENAI_MODEL?.trim() || defaultModel, reasoning: { effort: 'none' }, store: false, max_output_tokens: 700,
        instructions: 'Write a concise professional work note using only supplied text and visible evidence in labelled Before/After photos. Photos can show visible conditions or changes, but cannot prove the cause, exact repair, testing, safety or completion. Never infer unseen work, materials, test results, compliance, certifications or success. When work details are missing, say so plainly. Preserve ambiguity. Do not claim verified, certified, safe or fully repaired unless explicitly supplied as the worker’s statement. Return concise professional JSON.',
        input: [{ role: 'user', content }],
        text: { format: { type: 'json_schema', name: 'work_note', strict: true, schema } } })
    });
    if (!response.ok) return res.status(502).json({ error: 'AI service unavailable' });
    const payload = await response.json() as { status?: string; output?: Array<{ content?: Array<{ type?: string; text?: string }> }> };
    if (payload.status !== 'completed') return res.status(502).json({ error: 'AI response incomplete' });
    const text = payload.output?.flatMap(x => x.content ?? []).find(x => x.type === 'output_text')?.text;
    if (!text) return res.status(502).json({ error: 'AI response unavailable' });
    const result = JSON.parse(text) as Record<string, unknown>;
    if (!required.every(k => typeof result[k] === 'string' && (result[k] as string).length <= 2000)
      || !(result.professionalSummary as string).trim()) return res.status(502).json({ error: 'AI response invalid' });
    return res.status(200).json(result);
  } catch { return res.status(502).json({ error: 'AI service unavailable' }); }
  finally { clearTimeout(timeout); }
}
