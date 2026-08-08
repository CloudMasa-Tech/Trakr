importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDqH4PCc-rs86qYI5ZGwi2WOU4PtMJJzVE',
  appId: '1:6848613159:web:3250e45472fa6762137702',
  messagingSenderId: '6848613159',
  projectId: 'trakradminsetup-28437',
  authDomain: 'trakradminsetup-28437.firebaseapp.com',
  measurementId: 'G-N3M010CSJ9',
});

const messaging = firebase.messaging();

function cleanNotificationText(value) {
  return String(value || '')
    .replace(/^T[ЯR]AKR\s*•\s*/i, '')
    .replace(/^T[ЯR]AKA\s*•\s*/i, '')
    .replace(/\bT[ЯR]AKA\b\s*•?\s*/gi, '')
    .replace(/\bT[ЯR]AKR\b\s*•?\s*/gi, '')
    .replace(/\s+•\s+/g, ' • ')
    .trim();
}

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};
  const title = cleanNotificationText(
    notification.title || data.title || 'Attendance System',
  );
  const body = cleanNotificationText(
    notification.body || data.body || data.content || '',
  );

  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: data.notificationTag || data.requestId,
    data,
  });
});
