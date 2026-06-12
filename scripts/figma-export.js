#!/usr/bin/env node
// Export a Figma node as a rendered image via the public REST API.
//
// The Figma MCP tool path (`use_figma` + `exportAsync`) works but returns
// base64 through a 20 KB-truncated tool-call output, which forces a
// 10+ round-trip chunk assembly. The REST `/v1/images` endpoint renders
// the composited node server-side and returns a single signed URL, so one
// HTTP call replaces the whole chunk dance — much cheaper to call from
// the agent and much easier to read as a human.
//
// Usage:
//   FIGMA_TOKEN=xxx node scripts/figma-export.js \
//     --file <fileKey> --node <nodeId> \
//     --output assets/illustrations/foo.png \
//     [--scale 1|2|3] [--format png|jpg|svg|pdf] [--force]
//
// Overwriting a git-tracked output requires --force: a wrong node ID still
// renders "successfully" (usually as a tiny junk image), and writing that
// straight onto a committed asset destroys the good file.
//
// `fileKey` and `nodeId` come from the Figma URL:
//   https://www.figma.com/design/<fileKey>/<name>?node-id=<nodeId>
// Dashes in the URL's node-id become colons here (e.g. 258-5229 → 258:5229).
//
// Exits non-zero on any failure and prints a single `fail:` line.

const fs = require('fs');
const path = require('path');
const https = require('https');
const { execFileSync } = require('child_process');

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseArgs(argv) {
  const out = { scale: 1, format: 'png', absoluteBounds: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const next = () => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`missing value for ${a}`);
      return v;
    };
    switch (a) {
      case '--file': out.fileKey = next(); break;
      case '--node': out.nodeId = next(); break;
      case '--scale': out.scale = Number(next()); break;
      case '--format': out.format = next(); break;
      case '--output': out.output = next(); break;
      case '--absolute-bounds': out.absoluteBounds = true; break;
      case '--force': out.force = true; break;
      case '-h':
      case '--help': out.help = true; break;
      default: throw new Error(`unknown flag ${a}`);
    }
  }
  return out;
}

function printHelp() {
  console.log(
    'Usage: FIGMA_TOKEN=xxx figma-export.js ' +
    '--file <fileKey> --node <nodeId> --output <path> ' +
    '[--scale 1|2|3] [--format png|jpg|svg|pdf] ' +
    '[--absolute-bounds] [--force]'
  );
}

// A wrong node ID renders "successfully" as a tiny junk image, and writing
// it straight onto a committed asset silently destroys the good file. Treat
// git-tracked outputs as protected: overwriting one requires --force.
function isGitTracked(p) {
  try {
    execFileSync('git', ['ls-files', '--error-unmatch', path.resolve(p)], {
      cwd: path.dirname(path.resolve(p)),
      stdio: 'ignore',
    });
    return true;
  } catch (e) {
    return false; // untracked, outside a repo, or git unavailable
  }
}

function pngDimensions(buf) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47]);
  if (buf.length < 24 || !buf.subarray(0, 4).equals(sig)) return null;
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

function httpGet(url, headers = {}, retries = 4) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers }, (res) => {
      // `/v1/images` returns 200 with a JSON body; the signed S3 URL
      // serves the actual bytes on 200 as well. The only redirect we
      // reasonably expect is on CDN fetches — follow once.
      if (res.statusCode === 301 || res.statusCode === 302) {
        res.resume();
        return resolve(httpGet(res.headers.location, headers, retries));
      }
      if (res.statusCode === 429) {
        res.resume();
        if (retries <= 0) {
          return reject(new Error(`HTTP 429 for ${url}`));
        }
        const retryAfter = Number(res.headers['retry-after']);
        const delayMs = Number.isFinite(retryAfter)
            ? retryAfter * 1000
            : (5 - retries) * 1000;
        return resolve(
          sleep(delayMs).then(() => httpGet(url, headers, retries - 1)),
        );
      }
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    });
    req.on('error', reject);
  });
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) { printHelp(); return; }

  const missing = ['fileKey', 'nodeId', 'output'].filter((k) => !args[k]);
  if (missing.length) {
    throw new Error(`missing required flag(s): ${missing.map((m) => '--' + m.replace('Key', '').replace('Id', '')).join(', ')}`);
  }

  const token = process.env.FIGMA_TOKEN;
  if (!token) throw new Error('FIGMA_TOKEN env var is required');

  if (!args.force && fs.existsSync(args.output) && isGitTracked(args.output)) {
    throw new Error(
      `refusing to overwrite git-tracked file ${args.output} ` +
      '(verify the render first, then pass --force)'
    );
  }

  console.log(`[figma-export] exporting ${args.nodeId} @ ${args.scale}x ${args.format}`);

  // `use_absolute_bounds=true` tells Figma to render the node at its full
  // frame dimensions rather than tight-cropping to the artwork's
  // bounding box. Needed when a frame intentionally has empty space
  // around its content (the prototypical case is icon frames sized to
  // 24x24 with inner art smaller than that) — without it the exported
  // SVG viewBox matches the content, not the frame, and the icon's
  // position inside the 24x24 grid is lost.
  const apiUrl =
    `https://api.figma.com/v1/images/${encodeURIComponent(args.fileKey)}` +
    `?ids=${encodeURIComponent(args.nodeId)}` +
    `&format=${encodeURIComponent(args.format)}` +
    `&scale=${encodeURIComponent(args.scale)}` +
    (args.absoluteBounds ? '&use_absolute_bounds=true' : '');

  const apiResBuf = await httpGet(apiUrl, { 'X-Figma-Token': token });
  let apiRes;
  try {
    apiRes = JSON.parse(apiResBuf.toString('utf8'));
  } catch (e) {
    throw new Error(`invalid JSON from Figma API: ${e.message}`);
  }
  if (apiRes.err) throw new Error(`Figma API: ${apiRes.err}`);
  const imgUrl = apiRes.images && apiRes.images[args.nodeId];
  if (!imgUrl) {
    throw new Error(`Figma returned no image URL for node ${args.nodeId}`);
  }

  console.log('[figma-export] downloading rendered image');
  const imgBuf = await httpGet(imgUrl);

  // Write via a temp file so a failed download can never leave a partial
  // file at the destination.
  fs.mkdirSync(path.dirname(args.output), { recursive: true });
  const tmpPath = `${args.output}.tmp-download`;
  try {
    fs.writeFileSync(tmpPath, imgBuf);
    fs.renameSync(tmpPath, args.output);
  } catch (e) {
    fs.rmSync(tmpPath, { force: true });
    throw e;
  }

  const kb = Math.round(imgBuf.length / 1024);
  const dims = pngDimensions(imgBuf);
  const dimNote = dims ? `, ${dims.width}x${dims.height}` : '';
  console.log(`[figma-export] ok: ${args.output} (${kb} KB${dimNote})`);
}

main().catch((e) => {
  console.error(`[figma-export] fail: ${e.message}`);
  process.exit(1);
});
