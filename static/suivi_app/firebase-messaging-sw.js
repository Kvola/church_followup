// Service worker des notifications web — Suivi Évangélisation.
//
// GABARIT : scripts/build_pwa.sh l'écrit en firebase-messaging-sw.js avec
// l'identifiant de l'app Web Firebase (FCM_WEB_APP_ID), le MÊME que celui
// compilé dans l'application. Les deux ne peuvent donc pas diverger.
//
// Enregistré par index.html sous un périmètre distinct (./fcm-push/) : au même
// périmètre, il évincerait le service worker de Flutter (cache de l'app). Le
// périmètre ne règle que l'interception des pages ; les messages push, eux,
// arrivent quelle que soit la portée.
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAXKFpEZIp2DtMj39qSmaQi5o3YuPadf6w',
  appId: '1:541286889689:web:2787d49d3b3c8e0e33a6c8',
  messagingSenderId: '541286889689',
  projectId: 'association-management-fef4d',
  authDomain: 'association-management-fef4d.firebaseapp.com',
  storageBucket: 'association-management-fef4d.firebasestorage.app',
});

const messaging = firebase.messaging();

// Application fermée ou en arrière-plan : on affiche nous-mêmes.
messaging.onBackgroundMessage((payload) => {
  const n = payload.notification || {};
  return self.registration.showNotification(n.title || 'Suivi Évangélisation', {
    body: n.body || '',
    icon: '../icons/Icon-192.png',
    badge: '../icons/Icon-192.png',
    data: payload.data || {},
  });
});

// Toucher la notification ouvre l'application (ou la ramène au premier plan).
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = new URL('../', self.location.href).href;
  event.waitUntil(clients.matchAll({type: 'window', includeUncontrolled: true}).then((list) => {
    for (const c of list) {
      if (c.url.startsWith(target) && 'focus' in c) return c.focus();
    }
    return clients.openWindow(target);
  }));
});
