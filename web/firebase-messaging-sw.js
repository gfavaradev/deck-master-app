importScripts("https://www.gstatic.com/firebasejs/12.9.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/12.9.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDGOzXC_7hNy76w-p2EwWUOONhijpSVDmE",
  appId: "1:983642109584:web:0a040ea630dab5c478ca15",
  messagingSenderId: "983642109584",
  projectId: "deck-master-1a35a",
  authDomain: "deck-master-1a35a.firebaseapp.com",
  storageBucket: "deck-master-1a35a.firebasestorage.app",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification ?? {};
  if (title) {
    self.registration.showNotification(title, { body });
  }
});
