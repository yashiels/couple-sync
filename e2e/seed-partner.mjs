#!/usr/bin/env node
// seed-partner.mjs — seeds the SECOND user of a couple-sync E2E test.
//
// Uses the Firebase Auth emulator (http://127.0.0.1:9099) and the couple-sync
// backend (http://127.0.0.1:3000). Node >= 18 (built-in fetch), ESM, no deps.
//
// Endpoint / payload shapes were read from the real backend routes:
//   backend/src/routes/auth.ts    POST /auth/verify   (Bearer; no body; -> { user })
//   backend/src/routes/users.ts   PATCH /users/:uid   ({ timezone } etc; uid MUST equal caller; -> { user })
//   backend/src/routes/invites.ts POST /invites       (no body; 201 -> { code, expires_at })
//                                 POST /invites/:code/redeem (no body; -> { couple_id })
//   backend/src/routes/blocks.ts  POST /blocks         (see block payload below; 201 -> { block })
//
// Usage:
//   node seed-partner.mjs invite            [email] [password]
//   node seed-partner.mjs redeem <code>     [email] [password]
//   node seed-partner.mjs block  <flags...> [email] [password]
//
// See usage() below for block flags. Email/password default to
// u2@e2e.test / e2e-password and may be passed as trailing positional args.

const AUTH_EMULATOR = process.env.AUTH_EMULATOR_URL ?? 'http://127.0.0.1:9099';
const BACKEND = process.env.BACKEND_URL ?? 'http://127.0.0.1:3000';
// The emulator accepts any non-empty API key.
const API_KEY = 'fake';

const DEFAULT_EMAIL = 'u2@e2e.test';
const DEFAULT_PASSWORD = 'e2e-password';

function log(step, msg) {
  console.log(`[${step}] ${msg}`);
}

function die(step, status, body) {
  console.error(`[${step}] FAILED  http=${status}`);
  console.error(typeof body === 'string' ? body : JSON.stringify(body, null, 2));
  process.exit(1);
}

function usage() {
  console.error(`seed-partner.mjs — seed the SECOND couple-sync user

Sub-commands:
  invite [email] [password]
      Sign up/in, verify, set timezone, then create an invite.
      Prints exactly:  PAIR_CODE=<code>

  redeem <code> [email] [password]
      Sign up/in, verify, set timezone, then redeem <code> to pair.

  block --couple-id=<id> --start=<epochMs> --end=<epochMs> [flags] [email] [password]
      Sign up/in, verify, set timezone, then create a time block.
      Flags (matching POST /blocks payload):
        --couple-id=<uuid>     REQUIRED. Sent as body.couple_id.
        --start=<epochMs>      REQUIRED. body.start_utc (UTC ms since epoch, integer).
        --end=<epochMs>        REQUIRED. body.end_utc   (UTC ms since epoch, integer).
        --title=<str>          Default "E2E block". body.title (non-empty string).
        --type=<busy|free|tentative>   Default "busy". body.type.
        --category=<str>       Optional. body.category (string or omitted).
        --timezone=<IANA>      Default "Etc/UTC". body.timezone.
        --recurrence-rule=<RRULE>  Optional. body.recurrence_rule (must contain FREQ=).
        --visibility=<bothPartners|onlyMe>  Default "bothPartners". body.visibility.

Env overrides: AUTH_EMULATOR_URL, BACKEND_URL.`);
}

// ---- CLI parsing -----------------------------------------------------------

// Split argv into --key[=val] flags and bare positionals.
function parseArgs(argv) {
  const flags = {};
  const positionals = [];
  for (const arg of argv) {
    if (arg.startsWith('--')) {
      const eq = arg.indexOf('=');
      if (eq === -1) flags[arg.slice(2)] = true;
      else flags[arg.slice(2, eq)] = arg.slice(eq + 1);
    } else {
      positionals.push(arg);
    }
  }
  return { flags, positionals };
}

function requireInt(step, name, raw) {
  if (raw === undefined) die(step, 'n/a', `missing required flag --${name}`);
  const n = Number(raw);
  if (!Number.isInteger(n)) die(step, 'n/a', `--${name} must be an integer epoch-ms, got: ${raw}`);
  return n;
}

// ---- HTTP helper -----------------------------------------------------------

async function httpJson(step, url, { method = 'GET', token, body } = {}) {
  const headers = {};
  if (token) headers['Authorization'] = `Bearer ${token}`;
  let payload;
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  let res;
  try {
    res = await fetch(url, { method, headers, body: payload });
  } catch (err) {
    die(step, 'network', `fetch failed for ${method} ${url}: ${err?.message ?? err}`);
  }
  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = null; // non-JSON body; keep raw text for error reporting
  }
  if (!res.ok) die(step, res.status, json ?? text);
  return json ?? {};
}

// ---- Steps -----------------------------------------------------------------

// 1. Firebase Auth emulator sign-up, falling back to sign-in on EMAIL_EXISTS.
async function authenticate(email, password) {
  const signUpUrl =
    `${AUTH_EMULATOR}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`;
  const signInUrl =
    `${AUTH_EMULATOR}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;
  const reqBody = { email, password, returnSecureToken: true };

  log('auth', `signing up ${email} at emulator`);
  let res;
  try {
    res = await fetch(signUpUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(reqBody),
    });
  } catch (err) {
    die('auth', 'network', `fetch failed for signUp: ${err?.message ?? err}`);
  }
  let data = await res.json().catch(() => ({}));

  if (!res.ok) {
    const code = data?.error?.message ?? '';
    if (code === 'EMAIL_EXISTS') {
      log('auth', 'email exists, signing in instead');
      data = await httpJson('auth', signInUrl, { method: 'POST', body: reqBody });
    } else {
      die('auth', res.status, data);
    }
  }

  if (!data.idToken || !data.localId) {
    die('auth', res.status, `no idToken/localId in emulator response: ${JSON.stringify(data)}`);
  }
  log('auth', `authenticated uid=${data.localId}`);
  return { idToken: data.idToken, uid: data.localId };
}

// 2. Register the user server-side. Body-less: the backend reads the verified claims.
async function verify(idToken) {
  log('verify', 'POST /auth/verify');
  const out = await httpJson('verify', `${BACKEND}/auth/verify`, {
    method: 'POST',
    token: idToken,
  });
  log('verify', `registered uid=${out.user?.uid} email=${out.user?.email}`);
  return out.user;
}

// 3. Set timezone. PATCH /users/:uid — uid MUST equal the caller (else 403). Body { timezone }.
async function setTimezone(idToken, uid, timezone) {
  log('timezone', `PATCH /users/${uid} timezone=${timezone}`);
  const out = await httpJson('timezone', `${BACKEND}/users/${encodeURIComponent(uid)}`, {
    method: 'PATCH',
    token: idToken,
    body: { timezone },
  });
  log('timezone', `timezone set to ${out.user?.timezone}`);
  return out.user;
}

// 4. Create invite. POST /invites, no body. 201 -> { code, expires_at }.
async function createInvite(idToken) {
  log('invite', 'POST /invites');
  const out = await httpJson('invite', `${BACKEND}/invites`, {
    method: 'POST',
    token: idToken,
  });
  if (!out.code) die('invite', 201, `no code in response: ${JSON.stringify(out)}`);
  log('invite', `invite created, expires_at=${out.expires_at}`);
  return out.code;
}

// 5. Redeem invite. POST /invites/:code/redeem, no body. -> { couple_id }.
async function redeemInvite(idToken, code) {
  log('redeem', `POST /invites/${code}/redeem`);
  const out = await httpJson('redeem', `${BACKEND}/invites/${encodeURIComponent(code)}/redeem`, {
    method: 'POST',
    token: idToken,
  });
  log('redeem', `paired, couple_id=${out.couple_id}`);
  return out.couple_id;
}

// 6. Create a time block. POST /blocks. 201 -> { block }.
async function createBlock(idToken, block) {
  log('block', `POST /blocks couple_id=${block.couple_id} ${block.start_utc}->${block.end_utc}`);
  const out = await httpJson('block', `${BACKEND}/blocks`, {
    method: 'POST',
    token: idToken,
    body: block,
  });
  log('block', `block created id=${out.block?.id} type=${out.block?.type}`);
  return out.block;
}

// ---- Common bootstrap: auth -> verify -> timezone --------------------------

async function bootstrap(email, password, timezone = 'Etc/UTC') {
  const { idToken, uid } = await authenticate(email, password);
  await verify(idToken);
  await setTimezone(idToken, uid, timezone);
  return { idToken, uid };
}

// ---- Main ------------------------------------------------------------------

async function main() {
  const [, , sub, ...rest] = process.argv;
  const { flags, positionals } = parseArgs(rest);

  if (!sub || sub === '-h' || sub === '--help' || sub === 'help') {
    usage();
    process.exit(sub ? 0 : 1);
  }

  if (sub === 'invite') {
    // positionals: [email?, password?]
    const email = positionals[0] ?? DEFAULT_EMAIL;
    const password = positionals[1] ?? DEFAULT_PASSWORD;
    const { idToken } = await bootstrap(email, password);
    const code = await createInvite(idToken);
    // The ONLY line on stdout the harness parses.
    console.log(`PAIR_CODE=${code}`);
    return;
  }

  if (sub === 'redeem') {
    // positionals: [code, email?, password?]
    const code = positionals[0];
    if (!code) die('redeem', 'n/a', 'usage: redeem <code> [email] [password]');
    const email = positionals[1] ?? DEFAULT_EMAIL;
    const password = positionals[2] ?? DEFAULT_PASSWORD;
    const { idToken } = await bootstrap(email, password);
    await redeemInvite(idToken, code);
    return;
  }

  if (sub === 'block') {
    // positionals: [email?, password?]; everything else is flags.
    const email = positionals[0] ?? DEFAULT_EMAIL;
    const password = positionals[1] ?? DEFAULT_PASSWORD;

    const coupleId = flags['couple-id'];
    if (typeof coupleId !== 'string' || !coupleId) {
      die('block', 'n/a', 'missing required flag --couple-id=<uuid>');
    }
    const startUtc = requireInt('block', 'start', flags['start']);
    const endUtc = requireInt('block', 'end', flags['end']);

    const type = flags['type'] ?? 'busy';
    const visibility = flags['visibility'] ?? 'bothPartners';
    const timezone = flags['timezone'] ?? 'Etc/UTC';

    // Build the body to exactly match POST /blocks FIELDS. Server forces user_id/source; omit them.
    const body = {
      couple_id: coupleId,
      title: flags['title'] ?? 'E2E block',
      type,
      start_utc: startUtc,
      end_utc: endUtc,
      timezone,
      visibility,
    };
    // Optional fields: only send when provided (server treats absence and null distinctly).
    if (flags['category'] !== undefined) body.category = flags['category'];
    if (flags['recurrence-rule'] !== undefined) body.recurrence_rule = flags['recurrence-rule'];

    const { idToken } = await bootstrap(email, password, timezone);
    await createBlock(idToken, body);
    return;
  }

  console.error(`unknown sub-command: ${sub}`);
  usage();
  process.exit(1);
}

main().catch((err) => {
  console.error(`[fatal] ${err?.stack ?? err}`);
  process.exit(1);
});
