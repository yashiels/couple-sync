# Integration tests — deferred

The previous Firestore-emulator-based integration tests (auth flow, block CRUD,
calendar sync, onboarding, overlap display, pairing) were removed in V7 when
the app dropped `cloud_firestore` and moved its data layer to the self-host
backend via `SyncService`.

They will be re-implemented against the running backend once V2–V5 (backend
auth, block CRUD + WS, pairing/unpair/cleanup, overlap WS + FCM) land and the
VPS is reachable from a test environment. Until then, unit coverage lives under
`test/` (notably `test/services/sync_service_test.dart` for the data layer).
