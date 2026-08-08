// Handles approve/reject actions taken from a push notification.
// Ports the removed Cloud Functions `processNotificationAction` Firestore
// trigger plus `handleLeaveAction` / `handlePermissionAction` /
// `handleCheckoutAction`.
const { admin, initializeFirebaseAdmin } = require('../lib/firebaseAdmin');
const { notifyRequester } = require('../lib/helpers');

async function handleLeaveAction(db, action, requestId, responder) {
  const ref = db.collection('leave_requests').doc(requestId);
  const doc = await ref.get();
  if (!doc.exists) throw new Error(`Leave request ${requestId} not found`);
  const data = doc.data() || {};
  if (String(data.status || 'pending').toLowerCase() !== 'pending') return;

  const approved = action === 'approve';
  const reason = approved
    ? 'Approved from push notification'
    : 'Rejected from push notification';
  await ref.update({
    status: approved ? 'approved' : 'rejected',
    managerResponseReason: reason,
    rejectionReason: approved ? null : reason,
    respondedBy: responder,
    respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await notifyRequester(db, {
    employeeId: data.employeeId || data.userId,
    title: 'Leave Request Update',
    content: approved
      ? `Your leave request has been approved by ${responder}.`
      : '❌ Your leave request has been rejected. Please contact your manager.',
    type: 'Leave Response',
  });
}

async function handlePermissionAction(db, action, requestId, responder) {
  const ref = db.collection('permission_requests').doc(requestId);
  const doc = await ref.get();
  if (!doc.exists) throw new Error(`Permission request ${requestId} not found`);
  const data = doc.data() || {};
  if (String(data.status || 'pending').toLowerCase() !== 'pending') return;

  const approved = action === 'approve';
  const update = {
    status: approved ? 'approved' : 'rejected',
    respondedBy: responder,
    respondedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (approved) {
    update.managerResponse = 'Approved from push notification';
    update.approvedAt = admin.firestore.FieldValue.serverTimestamp();
    update.isPaid = data.isPaid ?? false;
    if (data.toTime) {
      update.returnTime = data.toTime;
      update.approvedReturnTime = data.toTime;
    }
  } else {
    update.rejectionReason = 'Rejected from push notification';
  }
  await ref.update(update);

  await notifyRequester(db, {
    employeeId: data.employeeId,
    title: `Permission Request ${approved ? 'Approved' : 'Rejected'}`,
    content: approved
      ? `Your permission request has been approved by ${responder}.`
      : '❌ Your permission request has been rejected.',
    type: 'Permission Response',
  });
}

async function handleCheckoutAction(db, action, requestId, responder) {
  if (action !== 'approve') {
    throw new Error('Checkout requests can only be approved from push notification.');
  }

  const ref = db.collection('checkout_requests').doc(requestId);
  const doc = await ref.get();
  if (!doc.exists) throw new Error(`Checkout request ${requestId} not found`);
  const data = doc.data() || {};
  if (String(data.status || 'pending').toLowerCase() !== 'pending') return;

  await ref.update({
    status: 'approved',
    adminNote: 'Approved from push notification',
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  if (data.attendanceId && data.checkoutDeadline) {
    await db.collection('attendance').doc(data.attendanceId).set({
      checkOutTime: data.checkoutDeadline,
      currentState: 'FINAL_CHECKOUT',
      checkoutApprovedByAdmin: true,
      checkoutApprovalNote: 'Approved from push notification',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  await notifyRequester(db, {
    employeeId: data.employeeId,
    title: 'Checkout Request Approved',
    content: `Your missed checkout request for ${data.dateKey || 'the selected date'} has been approved by ${responder}.`,
    type: 'Checkout Response',
  });
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,PATCH,DELETE,POST,PUT');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version'
  );

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed. Use POST.' });
  }

  try {
    const { actionId, actionType, requestId, managerName } = req.body || {};
    const action = String(actionId || '').toLowerCase();
    const type = String(actionType || '').toLowerCase();
    const cleanRequestId = String(requestId || '').trim();
    const responder = String(managerName || 'Push notification').trim();

    if (!['approve', 'reject'].includes(action) || !cleanRequestId) {
      return res.status(400).json({ error: 'Invalid notification action payload.' });
    }

    if (!initializeFirebaseAdmin()) {
      return res.status(500).json({ error: 'Firebase Admin not initialized properly. Check environment variables.' });
    }

    const db = admin.firestore();
    if (type === 'leave_request') {
      await handleLeaveAction(db, action, cleanRequestId, responder);
    } else if (type === 'permission_request') {
      await handlePermissionAction(db, action, cleanRequestId, responder);
    } else if (type === 'checkout_request') {
      await handleCheckoutAction(db, action, cleanRequestId, responder);
    } else {
      return res.status(400).json({ error: `Unsupported action type: ${type}` });
    }

    return res.status(200).json({ success: true, message: 'Notification action processed.' });
  } catch (error) {
    console.error('Error processing notification action:', error);
    return res.status(500).json({ error: 'Internal server error', details: error.message });
  }
}
