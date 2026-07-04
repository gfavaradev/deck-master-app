/* Deck Master — gestione consenso cookie (consent-first, GDPR).
 * I cookie di statistica/marketing NON vengono attivati senza consenso esplicito.
 * Al momento il sito NON carica strumenti di tracciamento: la funzione applyConsent()
 * è il punto in cui attivarli (es. Google Analytics) solo se l'utente acconsente.
 */
(function () {
  "use strict";

  var STORAGE_KEY = "dm_cookie_consent_v1";

  // ⚙️ Per attivare Google Analytics in futuro: metti qui il Measurement ID (es. "G-XXXX").
  // Verrà caricato SOLO se l'utente acconsente alle statistiche.
  var GA_MEASUREMENT_ID = "G-NDF4TNZ64L";

  function readConsent() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY) || "null");
    } catch (e) {
      return null;
    }
  }

  function saveConsent(consent) {
    consent.date = new Date().toISOString();
    localStorage.setItem(STORAGE_KEY, JSON.stringify(consent));
    applyConsent(consent);
  }

  function loadGoogleAnalytics() {
    if (!GA_MEASUREMENT_ID || window.__gaLoaded) return;
    window.__gaLoaded = true;
    var s = document.createElement("script");
    s.async = true;
    s.src = "https://www.googletagmanager.com/gtag/js?id=" + GA_MEASUREMENT_ID;
    document.head.appendChild(s);
    window.dataLayer = window.dataLayer || [];
    function gtag() { window.dataLayer.push(arguments); }
    window.gtag = gtag;
    gtag("js", new Date());
    gtag("config", GA_MEASUREMENT_ID, { anonymize_ip: true });
  }

  function applyConsent(consent) {
    if (consent && consent.analytics) loadGoogleAnalytics();
  }

  function hideBanner() {
    var b = document.getElementById("cookieBanner");
    if (b) b.classList.remove("show");
  }

  function showBanner() {
    var b = document.getElementById("cookieBanner");
    if (b) b.classList.add("show");
  }

  // API pubblica per la pagina Cookie Policy (pulsanti preferenze)
  window.DMCookies = {
    accept: function () { saveConsent({ necessary: true, analytics: true }); hideBanner(); },
    reject: function () { saveConsent({ necessary: true, analytics: false }); hideBanner(); },
    reopen: function () { showBanner(); },
    current: function () { return readConsent(); },
  };

  document.addEventListener("DOMContentLoaded", function () {
    var existing = readConsent();
    if (existing) {
      applyConsent(existing);
    } else {
      showBanner();
    }
    // Pulsanti del banner
    document.querySelectorAll("[data-cc]").forEach(function (el) {
      el.addEventListener("click", function (ev) {
        ev.preventDefault();
        var action = el.getAttribute("data-cc");
        if (action === "accept") window.DMCookies.accept();
        else if (action === "reject") window.DMCookies.reject();
        else if (action === "reopen") window.DMCookies.reopen();
      });
    });
  });
})();
