import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

// ─── Testable business logic ──────────────────────────────────────────────────

interface InviteCreateDeps {
  updateDeepLink(code: string, deepLinkUrl: string): Promise<void>;
}

export async function handleOnInviteCreate(
  code: string,
  deps: InviteCreateDeps
): Promise<void> {
  const deepLinkUrl = `coupleschedule://invite/${code}`;
  await deps.updateDeepLink(code, deepLinkUrl);
}

// ─── Cloud Function export ────────────────────────────────────────────────────

export const onInviteCreate = onDocumentCreated(
  'invites/{code}',
  async (event) => {
    const db = admin.firestore();
    const { code } = event.params;

    await handleOnInviteCreate(code, {
      updateDeepLink: async (inviteCode, url) => {
        await db.collection('invites').doc(inviteCode).update({ deepLinkUrl: url });
      },
    });
  }
);
