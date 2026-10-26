// Renders video/demo.html to MP4, frame by frame, with Playwright and ffmpeg, then adds the
// narration from the page's VOICEOVER list.
//
//   node video/render.mjs [out.mp4] [--stills 3,7.2,10] [--no-voice]
//
// Each frame calls render(t) in the page, so timing is exact regardless of how
// long a screenshot takes.
//
// Voice: with GEMINI_API_KEY set, lines are spoken by Gemini TTS (GEMINI_VOICE, default Kore).
// Models are tried in order (GEMINI_TTS_MODELS, comma-separated) because each has its own
// daily free-tier quota. Without it, macOS `say` (SAY_VOICE, default
// Samantha). Each line is cached in video/voice/ (git-ignored) by its text and voice, so
// re-rendering doesn't ask again. Put the key in .env at the repo root (git-ignored):
// GEMINI_API_KEY=… Never commit it.
import { spawn, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require('playwright'); } catch { playwright = require('/opt/node-tools/node_modules/playwright'); }

const here = dirname(fileURLToPath(import.meta.url));

// KEY=value lines from the repo's .env, without overriding the environment.
const envFile = resolve(here, '../.env');
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !(m[1] in process.env)) process.env[m[1]] = m[2].replace(/^(['"])(.*)\1$/, '$2');
  }
}
const args = process.argv.slice(2);
const stillsArg = args.indexOf('--stills');
const stills = stillsArg >= 0 ? args[stillsArg + 1].split(',').map(Number) : null;
const out = resolve(args.find(a => a.endsWith('.mp4')) ?? resolve(here, '../site/assets/demo.mp4'));
const withVoice = !args.includes('--no-voice');
const fps = 30, scale = 1;

const browser = await playwright.chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: scale });
await page.goto('file://' + resolve(here, 'demo.html'));
await page.evaluate(() => document.fonts.ready);
const total = await page.evaluate(() => window.TOTAL);
const narration = await page.evaluate(() => window.VOICEOVER ?? []);

if (stills) {
  mkdirSync(resolve(here, 'stills'), { recursive: true });
  for (const t of stills) {
    await page.evaluate(t => window.render(t), t);
    writeFileSync(resolve(here, `stills/t${t}.png`), await page.screenshot());
  }
  await browser.close();
  console.log('Wrote stills to video/stills/');
  process.exit(0);
}

const silent = withVoice && narration.length ? out.replace(/\.mp4$/, '.silent.mp4') : out;
const ffmpeg = spawn('ffmpeg', [
  '-y', '-loglevel', 'error',
  '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '24', '-pix_fmt', 'yuv420p',
  '-movflags', '+faststart', '-an', silent,
], { stdio: ['pipe', 'inherit', 'inherit'] });

const frames = Math.round(total * fps);
for (let i = 0; i < frames; i++) {
  await page.evaluate(t => window.render(t), i / fps);
  const buf = await page.screenshot({ type: 'jpeg', quality: 92 });
  if (!ffmpeg.stdin.write(buf)) await new Promise(r => ffmpeg.stdin.once('drain', r));
  if (i % 60 === 0) process.stdout.write(`frame ${i}/${frames}\r`);
}
ffmpeg.stdin.end();
await new Promise(r => ffmpeg.on('close', r));
await browser.close();

if (silent !== out) {
  const voice = resolve(here, 'voice');
  mkdirSync(voice, { recursive: true });
  const clips = [];
  for (const [start, text] of narration) {
    const file = speak(text, voice);
    const length = duration(file);
    clips.push({ start, text, file, length });
  }
  clips.forEach((c, i) => {
    const next = clips[i + 1]?.start ?? total;
    if (c.start + c.length > next) console.warn(`warning: "${c.text}" runs ${(c.start + c.length - next).toFixed(2)} s into the next part`);
  });
  // Each clip delayed to its start, mixed, and brought to a steady loudness for the web.
  const inputs = clips.flatMap(c => ['-i', c.file]);
  const chains = clips.map((c, i) => `[${i + 1}:a]aresample=48000,adelay=${Math.round(c.start * 1000)}:all=1[a${i}]`);
  const mix = `${chains.join(';')};${clips.map((_, i) => `[a${i}]`).join('')}amix=inputs=${clips.length}:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,apad[voice]`;
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', silent, ...inputs, '-filter_complex', mix,
    '-map', '0:v', '-map', '[voice]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k', '-shortest',
    '-movflags', '+faststart', out], { stdio: 'inherit' });
  execFileSync('rm', [silent]);
}
console.log(`\nWrote ${out}`);

/** A WAV of one line, from the cache or freshly spoken, with silence trimmed off both ends. */
function speak(text, dir) {
  const gemini = process.env.GEMINI_API_KEY;
  const models = (process.env.GEMINI_TTS_MODELS ?? 'gemini-3.8-flash-tts,gemini-3.1-flash-tts-preview,gemini-2.5-flash-preview-tts').split(',');
  const who = gemini ? `gemini:${process.env.GEMINI_VOICE ?? 'Kore'}` : `say:${process.env.SAY_VOICE ?? 'Samantha'}`;
  const key = createHash('sha256').update(`${who}\n${text}`).digest('hex').slice(0, 16);
  const file = resolve(dir, `${key}.wav`);
  if (existsSync(file)) return file;
  const raw = resolve(dir, `${key}.raw`);
  if (gemini) {
    const body = JSON.stringify({
      contents: [{ parts: [{ text }] }],
      generationConfig: { responseModalities: ['AUDIO'],
        speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: process.env.GEMINI_VOICE ?? 'Kore' } } } },
    });
    let reply;
    // A per-minute limit is waited out; a used-up daily quota moves on to the next model.
    models: for (const model of models) {
      for (let attempt = 1; attempt <= 8; attempt++) {
        reply = JSON.parse(execFileSync('curl', ['-sS', '-X', 'POST',
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
          '-H', 'Content-Type: application/json', '-H', `x-goog-api-key: ${gemini}`, '--data-binary', '@-'],
          { input: body, maxBuffer: 64 << 20 }).toString());
        if (reply.error?.code !== 429) break models;
        if (/per day/i.test(reply.error.message)) { console.log(`${model}: daily quota used up`); break; }
        console.log(`${model}: rate limit, waiting 30 s`);
        execFileSync('sleep', ['30']);
      }
    }
    if (reply.error) throw new Error(`Gemini TTS: ${reply.error.message}`);
    const part = reply.candidates[0].content.parts[0].inlineData;
    // Usually a WAV; raw 16-bit PCM at 24 kHz otherwise.
    const audio = Buffer.from(part.data, 'base64');
    writeFileSync(raw, audio);
    if (!part.mimeType.includes('wav')) {
      execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 's16le', '-ar', '24000', '-ac', '1', '-i', raw, `${raw}.wav`]);
      renameSync(`${raw}.wav`, raw);
    }
  } else {
    execFileSync('say', ['-v', process.env.SAY_VOICE ?? 'Samantha', '-r', '178', '-o', `${raw}.aiff`, text]);
    renameSync(`${raw}.aiff`, raw);
  }
  const trim = 'silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse';
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', raw, '-af', trim, '-ac', '1', file]);
  execFileSync('rm', [raw]);
  console.log(`spoke: ${text}`);
  return file;
}

function duration(file) {
  return Number(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file]).toString());
}
