# Couple Schedule — Full App + Edge-First Rework Spec

**Date:** 2026-06-30
**Status:** Revised after Codex review (v4). v2 resolved P1a/P2a/P2b; v3 resolved P1b/P1c + 3 GCP P2s; v4 resolves the final P2 (raise `durationMinutes` cap to 1560 so DST fall-back 25h day-boundary windows aren't falsely rejected by FCM validation).
**Goal:** A working v1 of the couple-scheduling app — overlap compute moved to the device to cut server cost, the UX slop fixed, and the whole Google Cloud footprint pinned to the free tier.

---

## 1. Motivation

1. **"Most compute on the device/edge."** Today overlap runs in `onBlockWrite` (Cloud Function) on every block write. It is pure logic — it runs identically on-device.
2. **"Save on server costs."** `onBlockWrite` (+ `onUserPrefsWrite`) fire on every block/pref change and each reads the couple doc + user docs + all blocks. Deleting both removes the dominant variable cost.
3. **The v1 POC never worked end-to-end.** This is the version that actually runs, with the ~40 UX slop items fixed.

## 2. Non-goals

- No peer-to-peer / local-first sync rewrite. Firestore stays the sync bus.
- No new features (digests, analytics). Only the existing v1 surface, made to work and made nice.
- No `visibility: onlyMe` server enforcement (existing v1 trade-off — filtered client-side).

## 3. Full app surface (what's being built/fixed)

| Screen | Path | v1 scope |
|---|---|---|
| Auth | `features/auth` | Google + Apple sign-in; emulator toggle for dev. Fix hand-painted Google G + leaked emulator creds. |
| Timezone onboarding | `features/onboarding/timezone_setup` | Device-tz default, manual override. |
| Pairing | `features/onboarding/pairing` | Share code / enter code, deep link (`coupleschedule://invite/{code}` + https fallback). |
| Home | `features/home` | Partner clocks, next-window card, upcoming list. Fix double-spinner, dead-end empty state, tap-to-detail. |
| Calendar | `features/calendar` | Week view, both partners' blocks. Fix cross-tz block positioning + 24h-only labels. |
| Blocks | `features/blocks` | CRUD, recurrence (DAILY/WEEKLY/MONTHLY/YEARLY + INTERVAL/BYDAY/COUNT/UNTIL), categories, visibility. Fix raw `d/m/y`, bare IANA display, double-setState. |
| Overlap | `features/overlap` | Windows list, filter, detail dialog (both tzs). Fix silent 10-cap, dead-end empty state. |
| Settings | `features/settings` | Calendar connect/sync, notifications, late-night toggle, unpair, sign out. Fix non-persisted notification toggle, `STORY-019` TODO. |

## 4. Google Cloud / Firebase footprint

| Service | Use | Cost lever |
|---|---|---|
| **Firebase Auth** | Google + Apple providers | 50k MAU free → ~$0 |
| **Cloud Firestore** (native, `us-central1`) | Real-time sync bus. Collections: `users`, `couples`, `invites`, `timeblocks/{coupleId}/blocks`, `overlaps/{coupleId}/windows/latest` | 50k reads / 20k writes per day free. Device-side overlap compute *reduces* reads (no per-write all-blocks fetch in a CF). |
| **Cloud Functions v2** (nodejs22, `us-central1`) | `redeemInvite`, `unpairCouple`, `cleanupExpiredInvites` (scheduled), `onOverlapWrite` (FCM), `onInviteCreate` (deep link). **Delete:** `onBlockWrite`, `onUserPrefsWrite`. | 2M invocations/mo free. Deleting the two per-change triggers removes the dominant invocation source. |
| **Cloud Scheduler** | `cleanupExpiredInvites` daily 03:00 UTC | 3 free jobs/mo. |
| **Firebase Cloud Messaging** | Push on new overlap | Free, unlimited. |
| **Google Calendar API** (freebusy) | Called from the *device* with a stored user OAuth token (`calendar.readonly`). Not billed via Firebase. | Free quota **with controls**: enable the Calendar API in the GCP project; device sync throttled ≤ once/hour (existing `shouldAutoSync` guard) so freebusy is ~1 call/user/hour (1 quota unit/call); exponential backoff + retry on 429/503; surface "rate-limited, try later" to the user. Per-user daily quota is far below the default 1M/day. |
| **Firebase Hosting** (new, minimal) | Serve App Link / App Links verification files at the exact well-known paths: `/.well-known/apple-app-site-association` (content-type `application/json`, no redirect, served at the root domain) and `/.well-known/assetlinks.json` (same constraints). Plus the `https://coupleschedule.app/invite/{code}` landing → deep-link redirect. | Free Spark-tier hosting. |
| **App Check** (v1, in-scope) | Abuse protection on Firestore writes + Functions callables. **Moved from deferred to v1** because v2 introduces a client-write path on `overlaps/latest` that can trigger FCM — without App Check, a forged client can spam pushes + Firestore writes. Enforce on Firestore writes (member-write paths) and the `redeemInvite`/`unpairCouple` callables; exempt the emulators in dev. | Free (App Check quota is generous on Spark). |

**Runtime mismatch to fix:** `firebase.json` declares `nodejs20`, `functions/package.json` engines `node 22`. Align to **nodejs22** (Functions v2 supports it; matches the dep set).

## 5. Current vs target compute split

| Workload | Today | Target |
|---|---|---|
| Overlap computation | `onBlockWrite` CF (per block write) | **Device** — Dart port of `overlap.ts` |
| Overlap recompute on pref/tz change | `onUserPrefsWrite` CF (per user doc update) | **Device** — same controller watches user docs |
| Overlap write to `overlaps/latest` | CF (admin SDK) | **Device** — Firestore transaction |
| Calendar freebusy | Device | Device (unchanged) |
| FCM push on new overlap | `onOverlapWrite` CF | `onOverlapWrite` CF (unchanged + skip writer) |
| Atomic pairing / unpair / cleanup / deep link | CFs | unchanged |

**Deleted functions:** `onBlockWrite`, `onUserPrefsWrite` (+ their exports in `index.ts` and tests).

## 6. Architecture

```
Device (Flutter)                              Cloud Functions v2 (kept)
─────────────────────────────────             ──────────────────────────────
overlap_engine.dart  ◄── port of overlap.ts (pure, no Firebase)
  ▲ watches
timeblocks/...  (Firestore snapshot)          redeemInvite (callable — atomic pairing)
  ▲ watches                                     unpairCouple (callable — cleanup)
users/{uid}  (tz + showLateNightWindows)       cleanupExpiredInvites (scheduled)
  ▼ recompute + 500ms debounce + inputHash skip
overlaps/{coupleId}/windows/latest  ◄── device writes via Firestore transaction
  ▼ triggers
onOverlapWrite  ───► FCM to the non-writer partner

onInviteCreate (deep link)                    Firebase Hosting (app-links + invite landing)
```

## 7. The Dart overlap port

### 7.1 Engine — `lib/core/overlap/overlap_engine.dart`

Line-for-line port of `functions/src/lib/overlap.ts`:
- `mergeIntervals`, `intersectIntervals` — identical.
- `expandBlock` — uses the Dart **`rrule`** package (chosen, not hand-rolled — see §7.3). Preserve: strip optional `RRULE:` prefix; UTC `dtstart`; inclusive `between(windowStart - duration, windowEnd, true)` lookback.
- `computeFreeIntervals`, `clipToWakingHours`, `clipToDayBoundaries` — **must use `TZDateTime`** (from the `timezone` package, already a dep) for local start-of-day and 07:00/23:00 wall-clock setting, advancing by calendar days. NOT UTC millisecond day math — DST would shift the boundary. Port `scoreWindow` and drop the dead `_timezoneB` param.
- `computeBlockHash` — `package:crypto` sha256, slice 16.
- `computeOverlap` — same `HORIZON_DAYS=14`, `MIN_WINDOW_MINUTES=30`, `MAX_WINDOWS=20`.

### 7.2 Overlap controller — Riverpod `AsyncNotifier`

- Watches `FirestoreService.watchBlocks(coupleId)` AND both partners' user docs (timezone + `showLateNightWindows`).
- Debounce 500ms, then compute `nowBucket = floor(now, 1 hour)` and call `computeOverlap(blocksA, blocksB, tzA, tzB, now: nowBucket, prefsA, prefsB)` — **the bucketed now is passed as the `now` argument itself**, not just hashed. This guarantees two devices in the same hour produce byte-identical windows (same horizon end, same `timeDecay` score), restoring the deterministic-two-writer property.
- **Input hash (P1a fix):** `inputHash = sha256(blocksA ‖ blocksB ‖ tzA ‖ tzB ‖ prefsA ‖ prefsB ‖ ALGO_VERSION ‖ nowBucket)`. `ALGO_VERSION` is a constant bumped on any scoring/algorithm change to force recompute.
- **Write (P1b fix):** Firestore **transaction** on `overlaps/{coupleId}/windows/latest`: re-read the doc's `inputHash`; if it equals the locally computed one, skip the write; else write `{windows, computedAt, inputHash, computedBy: uid}`. Last-writer-wins is now benign because identical inputs ⇒ identical output.
- Exposes `OverlapResult` to the UI for instant render (independent of the write).

### 7.3 RRULE parity (P2a fix)

- Pick the maintained Dart `rrule` package; confirm it supports DAILY/WEEKLY/MONTHLY/YEARLY + INTERVAL + BYDAY + COUNT + UNTIL (the set `recurrence_picker_widget` emits).
- **Golden TS-vs-Dart tests** for each of the above, plus DST-transition cases (spring-forward, fall-back). Do not hand-roll only DAILY/WEEKLY.

## 8. Data model + rules changes

### 8.1 `overlaps/{coupleId}/windows/latest`
```ts
{
  windows: OverlapWindow[],   // ≤ 20
  computedAt: number,         // UTC ms
  inputHash: string,          // NEW (replaces blockHashA/B) — full input fingerprint
  computedBy: string          // NEW — uid of writer
}
```
`blockHashA`/`blockHashB` are replaced by the single `inputHash`. No migration: old docs deserialize with `inputHash` nullable; the first device write after deploy stamps the new shape.

### 8.2 Firestore rules (P1c fix)

```
match /overlaps/{coupleId}/windows/{windowId} {
  allow read: if isCoupleMember(coupleId);

  // Only "latest" is writable, only by a couple member, with schema bounds.
  allow write: if isCoupleMember(coupleId)
    && windowId == 'latest'
    && request.resource.data.computedBy == request.auth.uid
    && request.resource.data.inputHash is string
    && request.resource.data.computedAt is int
    && request.resource.data.windows is list
    && request.resource.data.windows.size() <= 20
    // Per-element shape/bounds can't be cleanly iterated in rules (no list
    // comprehension over map elements); the deep validation below is enforced
    // by onOverlapWrite before it trusts windows[] for the FCM side-effect.
}
```
- `windowId == 'latest'` — no arbitrary doc creation.
- `computedBy == auth.uid` — can't forge the other partner.
- `windows is list`, `size() <= 20`, `hasOnly([...])` — top-level shape gate in rules (cheap).
- **Deep element validation in `onOverlapWrite` (P1c fix):** before trusting `windows[]` for FCM, the function validates each element — `startUtc`/`endUtc`/`durationMinutes` are ints, `score` is number, `reasonableBoth` is bool, `0 < durationMinutes <= 1560` (26h — covers a 25h DST fall-back day from `clipToDayBoundaries`, not 24h), `startUtc < endUtc`, `endUtc - startUtc == durationMinutes*60000` (±tolerance). Malformed → skip the push, log, and not write a corrupt notification. This splits trust: rules gate *who writes + top-level shape*; the CF gates *what it trusts for the side-effect*.
- Add **rules tests** via the Firestore emulator (`@firebase/rules-unit-testing`) covering: member write to `latest` ✓, write to other `windowId` ✗, non-member ✗, `computedBy` mismatch ✗, `windows.size() == 21` ✗, non-list `windows` ✗.

### 8.3 `onOverlapWrite` change

Skip the `computedBy` uid when sending FCM (so the editor isn't self-pinged). ~3 lines + one test. `onOverlapWrite` reads `windows` and `computedBy` from the doc.

## 9. UX fixes (audit punch list — full list in the plan)

Ranked by impact:

1. **Cross-timezone rendering** (core of an LDR app, currently weakest) — `week_view_widget` block positioning via minutes-since-dayStart + block tz; `block_form` / `block_management` / settings dates via locale `DateFormat.yMd(locale)` / `Hm()`; show tz offset + current time, not bare IANA.
2. **Loading / empty / error states** — kill home double-spinner + fake 1s delay (await real provider futures); add CTAs to "no partner" dead-ends; keep AppBar visible during edit load.
3. **Calendar auth reliability** — fix dead `_refreshTokenKey`, make `signInSilently` refresh actually work, stop forcing `signOut()` before `connect()`; optional multi-calendar.
4. **Theme / code hygiene** — extract 4× `_formatDuration` + duplicated label getters to shared utils / enum extensions; switch on `TimeBlockCategory` enum; use `FilterChip` / `AppColors` / `theme.textTheme`; delete dead `Theme.of(context);` lines, unused `background*` colors, `STORY-019` TODO; replace hand-painted Google G with an asset.
5. **Navigation** — Today button drives the `WeekViewWidget` page controller; home window-card `onTap` → detail dialog.

## 10. Testing

- **Port the 44 jest overlap tests to Dart** + the new golden RRULE/DST cases (§7.3). Same inputs → same windows.
- Keep the functions jest suite for `redeemInvite`, `unpairCouple`, `cleanupExpiredInvites`, `onOverlapWrite` (add `computedBy`-skip test). Remove `onBlockWrite` + `onUserPrefsWrite` tests.
- **Firestore rules tests** for the relaxed `overlaps/latest` write path (§8.2).
- Widget smoke tests for the two navigation fixes + cross-tz block positioning only.

## 11. Cost impact

- **Deleted:** `onBlockWrite` + `onUserPrefsWrite` invocations and their per-call reads (couple doc + user docs + all-blocks fetch). These scaled with calendar-sync + pref-toggle volume — the dominant variable cost.
- **Added:** device compute (free) + `overlaps/latest` writes from the device, throttled by debounce + inputHash-skip + transaction-skip → roughly one write per real input change, same order as before.
- `onOverlapWrite` unchanged (one per real overlap change); FCM free.
- Net: materially lower CF invocation count and Firestore read count; stays within free tier.

## 12. Risks (revised)

- **RRULE parity** — Dart package vs npm `rrule` may diverge on edge cases (BYDAY with weekly, UNTIL tz, MONTHLY/YEARLY). Mitigation: §7.3 golden tests across the full picker-emitted set + DST.
- **DST in waking-hours clip** — UTC-millisecond day math would shift 07:00/23:00 by an hour on DST days. Mitigation: §7.2 `TZDateTime` local-day construction + DST tests.
- **Two writers** — `now` differs per device, so outputs are not byte-identical under the original design. Mitigation: `nowBucket` (hour) in `inputHash` + transaction skip ⇒ identical inputs produce identical writes; the only divergence is a one-hour-stale `now` on the losing device, which refreshes on its next change event. Acceptable.
- **Rule relaxation** — new write path on `overlaps/latest`. Mitigation: §8.2 restricts to `latest`, enforces `computedBy == auth.uid`, caps `windows ≤ 20`, type-checks; rules tests. Derived data only — no new information exposure (members can already read all blocks).
- **`now`-bucket drift** — hourly bucket means a window's `score` (timeDecay) is up to 1h stale. Fine for a 14-day horizon.

## 13. Deployment

- **Functions:** `firebase deploy --only functions` after deleting `onBlockWrite` / `onUserPrefsWrite` and aligning runtime to nodejs22.
- **Firestore:** `firebase deploy --only firestore:rules,firestore:indexes` with the §8.2 rules.
- **Hosting:** add `firebase.json` hosting config serving `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json` (as `application/json`, `Cache-Control: no-cache`, no redirect) plus the `/invite/{code}` deep-link redirect; `firebase deploy --only hosting`.
- **App Check:** register the iOS + Android apps for App Check (DeviceCheck / Play Integrity); enforce on Firestore write paths + callable Functions; add the debug token escape hatch for emulators/`--use-emulator` builds.
- **App:** iOS App Store + Android Play, manual for v1.

## 14. Open questions

1. Confirm the maintained Dart `rrule` package supports the full picker-emitted RRULE set (§7.3) — verify at plan start; if gaps, fall back to a different package, not hand-roll.
2. Domain ownership for `coupleschedule.app` (needed for App Links / Hosting) — is it owned/configured, or does the deep-link https fallback defer to v1.1?
3. Apple Sign-In requires a paid Apple Developer account for device testing — is that available, or do we ship Google-only for v1 and gate Apple behind a flag?
