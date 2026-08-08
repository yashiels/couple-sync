# couple-sync authenticated E2E (on Atlas)

Full sign-in → pairing → overlap E2E on a real Android emulator, with **no real Google** (its OAuth
can't be automated). Auth is bypassed via the Firebase Auth emulator; the app must be built with
`EXPO_PUBLIC_E2E=1` (see `app.config.ts` / `src/auth.ts`).

## What it proves
Launch → renders → E2E sign-in (Auth emulator) → timezone onboarding → pairing (real UI, code entry)
→ overlap window renders on the Free-time tab. Blocks are seeded via API (the block form uses native
Android date pickers Maestro can't drive); the overlap **compute + WS push + render** are real.

## Stack (all `network_mode: host` so the emulator's 10.0.2.2 reaches them)
- `docker-compose.e2e.yml`: `pg` (:5433), `auth-emu` (:9099, firebase-tools), `api` (couple-sync-api:latest, `FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099`).
- Android emulator: `docker run -d --name android-e2e --privileged --device /dev/kvm --network host budtmo/docker-android:emulator_11.0`.
- E2E APK: built with `-e EXPO_PUBLIC_E2E=1 -e API_BASE_URL=http://10.0.2.2:3000`, `adb -s emulator-5554 install -r`.

## Run
```bash
# 1. bring up stack + emulator, install the E2E APK (see the memory note couple-sync-e2e-harness)
# 2. run the whole flow inside a host-networked builder container:
docker run --rm --network host \
  -v ~/apps/cs-e2e:/app -v ~/apps/cs-e2e/maestro-out:/root/.maestro \
  -e ANDROID_HOME=/opt/android-sdk \
  mingc/android-build-box:latest bash /app/e2e/run-e2e.sh
```
`run-e2e.sh`: flow1 (login+tz+pairing) → seed u2+invite → flow2 (enter code) → fetch couple_id →
seed both busy fence blocks → flow3 (assert `★ Best match` + `Mon 10 Aug, 18:00 – 20:00`).

## Notes
- No component in the flow has a `testID` except `signin-button`; flows select by visible text.
- Overlap = intersection of each partner's **free gaps** (busy blocks inverted), clipped to 07:00–23:00
  local, ≥30 min. Fence dates are absolute (Aug 2026) — refresh them if run past the 14-day horizon.
- adb gotcha: never `adb connect` inside the `android-e2e` container (duplicates the device); use
  `adb -s emulator-5554`. Maestro runs in its own host-net container and connects to `127.0.0.1:5555`.
