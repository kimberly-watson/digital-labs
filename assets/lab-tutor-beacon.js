/* lab-tutor-beacon.js
   Injected into Nexus (port 8082) and IQ Server (port 8072) by nginx sub_filter.
   Writes current product + URL into shared storage every 2 seconds so the tutor
   popup can always know where the learner is.

   Storage priority: localStorage -> sessionStorage -> in-memory window variable
   (Safari private mode blocks localStorage; Firefox/Edge handle it fine) */
(function () {
  var PRODUCT = window.__snLabProduct || '';
  if (!PRODUCT) return;

  /* Cross-browser storage with graceful fallback */
  var _mem = {};
  var store = (function () {
    try {
      var k = '__sn_test__';
      localStorage.setItem(k, '1');
      localStorage.removeItem(k);
      return localStorage;
    } catch (e) {}
    try {
      var k2 = '__sn_test__';
      sessionStorage.setItem(k2, '1');
      sessionStorage.removeItem(k2);
      return sessionStorage;
    } catch (e2) {}
    return {
      setItem: function (k, v) { _mem[k] = v; },
      getItem: function (k)    { return _mem[k] !== undefined ? _mem[k] : null; },
      removeItem: function (k) { delete _mem[k]; }
    };
  })();

  function pulse() {
    try {
      store.setItem('snLabProduct', PRODUCT);
      store.setItem('snLabUrl',     location.href);
      store.setItem('snLabTs',      String(Date.now()));
    } catch (e) {}
  }

  pulse();
  setInterval(pulse, 2000);

  /* Bring the tutor popup to the front whenever the user focuses this tab.
     window.open('', 'LabTutor') returns the existing popup by name without
     navigating it. If it's cross-origin (tutor is port 80, we're on 8082/8072),
     location.href throws — that means the window IS open, so we focus it.
     If location.href returns 'about:blank', no tutor is open yet — close the
     blank window we accidentally created and do nothing. */
  var _tutorRef = null;
  function bringTutorToFront() {
    if (_tutorRef && !_tutorRef.closed) {
      _tutorRef.focus();
      return;
    }
    var w = window.open('', 'LabTutor');
    if (!w) return;
    try {
      var href = w.location.href;
      if (!href || href === 'about:blank') {
        w.close(); // No tutor open yet — discard blank window
      } else {
        _tutorRef = w;
        _tutorRef.focus();
      }
    } catch (e) {
      // Cross-origin means the tutor IS open — safe to focus
      _tutorRef = w;
      _tutorRef.focus();
    }
  }

  window.addEventListener('focus', bringTutorToFront);
})();
