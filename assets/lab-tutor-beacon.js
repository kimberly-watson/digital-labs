/* lab-tutor-beacon.js — injected into Nexus and IQ Server pages via nginx sub_filter
   Does ONE thing: writes the current product and URL to localStorage every 2 seconds.
   No UI, no DOM manipulation, nothing ExtJS can interfere with. */
(function () {
  var PRODUCT = window.__snLabProduct || '';
  if (!PRODUCT) return;

  function pulse() {
    try {
      localStorage.setItem('snLabProduct', PRODUCT);
      localStorage.setItem('snLabUrl',     location.href);
      localStorage.setItem('snLabTs',      Date.now());
    } catch (e) {}
  }

  pulse();
  setInterval(pulse, 2000);
})();
