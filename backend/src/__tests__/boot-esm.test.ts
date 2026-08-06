import { existsSync } from 'node:fs';
import { glob, readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { promisify } from 'node:util';
import { describe, expect, it } from 'vitest';

const exec = promisify(execFile);
const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const dist = path.join(backendRoot, 'dist');

/** Packages that are CJS-only with no `exports` map, so a named ESM import throws under plain node. */
const CJS_ONLY = ['rrule'];

/**
 * Everything else in this suite runs through vitest, which resolves a package's `module` field and
 * therefore happily accepts `import { RRule } from 'rrule'`. Plain `node dist/...` does not: rrule is
 * CJS with no `exports` map, so a named ESM import throws
 *   SyntaxError: The requested module 'rrule' does not provide an export named 'RRule'
 * That once made the built container unbootable while all 371 tests stayed green — tsc, vitest and
 * the Docker HEALTHCHECK all missed it, because none of them ran the built entrypoint.
 *
 * So: actually run the build output in a real node process. Any CJS/ESM interop regression in ANY
 * dependency fails here, not in production.
 *
 * Skips when dist/ is absent so `pnpm test` alone stays fast; `pnpm build && pnpm test` covers it,
 * which is what CI and every task gate run.
 */
describe.skipIf(!existsSync(dist))('built output is importable by plain node (ESM interop)', () => {
  const canImport = (rel: string) =>
    exec(process.execPath, ['-e', `import(${JSON.stringify(path.join(dist, rel))})`], {
      cwd: backendRoot,
    });

  it('imports dist/overlap/index.js', async () => {
    await expect(canImport('overlap/index.js')).resolves.toBeDefined();
  });

  it('imports dist/overlap/recurrence.js — the rrule consumer', async () => {
    await expect(canImport('overlap/recurrence.js')).resolves.toBeDefined();
  });

  // routes/*.js cannot be import-tested here: they pull in config.ts, which fails fast on missing
  // env by design. So guard the whole tree statically instead — this also covers files that do not
  // exist yet, which a per-file import test never would.
  it('no built file uses a NAMED import from a CJS-only package', async () => {
    const offenders: string[] = [];
    for await (const f of glob('**/*.js', { cwd: dist })) {
      const src = await readFile(path.join(dist, f), 'utf8');
      // tsc emits the safe form as `import x from "rrule"`; the unsafe one keeps its braces.
      for (const pkg of CJS_ONLY) {
        if (new RegExp(String.raw`import\s*\{[^}]*\}\s*from\s*["']${pkg}["']`).test(src)) {
          offenders.push(`${f} -> ${pkg}`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });

  it('expands a recurring block correctly when loaded as built output, not just as source', async () => {
    // Proves the destructured default import is actually wired, not merely importable.
    const script = `
      const { expandBlock } = await import(${JSON.stringify(path.join(dist, 'overlap/index.js'))});
      const out = expandBlock(
        { userId: 'u', type: 'busy', startUtc: Date.UTC(2026, 0, 5, 9), endUtc: Date.UTC(2026, 0, 5, 10),
          timezone: 'UTC', recurrenceRule: 'FREQ=DAILY;COUNT=3' },
        Date.UTC(2026, 0, 5), Date.UTC(2026, 0, 12),
      );
      if (out.length !== 3) { console.error('expected 3 occurrences, got ' + out.length); process.exit(1); }
    `;
    await expect(
      exec(process.execPath, ['--input-type=module', '-e', script], { cwd: backendRoot }),
    ).resolves.toBeDefined();
  });
});
