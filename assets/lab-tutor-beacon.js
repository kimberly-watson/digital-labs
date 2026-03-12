/* lab-tutor-beacon.js — injected into Nexus (8082) and IQ Server (8072) by nginx sub_filter */
(function () {
  /* Guard 1: only run in the top-level frame */
  if (window !== window.top) return;

  /* Guard 2: only execute once */
  if (window.__snBeaconInit) return;
  window.__snBeaconInit = true;

  /* Detect product by port — avoids inline scripts blocked by IQ Server's CSP */
  var PRODUCT = location.port === '8082' ? 'Nexus Repository' :
                location.port === '8072' ? 'IQ Server' : '';
  if (!PRODUCT) return;

  var TUTOR_URL = 'http://' + location.hostname + '/tutor';
  var WIN_W     = 440;
  var WIN_H     = 640;
  var _tutorWin = null;

  /* ── storage with fallback (Safari private mode blocks localStorage) ── */
  var _mem = {};
  var store = (function () {
    try { localStorage.setItem('__t','1'); localStorage.removeItem('__t'); return localStorage; } catch(e) {}
    try { sessionStorage.setItem('__t','1'); sessionStorage.removeItem('__t'); return sessionStorage; } catch(e2) {}
    return {
      setItem:    function(k,v) { _mem[k]=v; },
      getItem:    function(k)   { return _mem[k]!==undefined ? _mem[k] : null; },
      removeItem: function(k)   { delete _mem[k]; }
    };
  })();

  /* ── context pulse ──
     Writes to own-origin localStorage AND postMessages the tutor directly.
     postMessage is needed because tutor is port 80 — different origin.
     Also sends a snHeartbeat so the tutor knows this page is still open. */
  var TUTOR_ORIGIN = 'http://' + location.hostname;
  function pulse() {
    try {
      store.setItem('snLabProduct', PRODUCT);
      store.setItem('snLabUrl',     location.href);
      store.setItem('snLabTs',      String(Date.now()));
    } catch(e) {}
    if (_tutorWin && !_tutorWin.closed) {
      try {
        _tutorWin.postMessage(
          { type: 'snLabContext', product: PRODUCT, url: location.href, ts: Date.now() },
          TUTOR_ORIGIN
        );
      } catch(e) {}
    }
  }
  pulse();
  setInterval(pulse, 2000);

  /* ── open / focus tutor popup ──
     One call does everything within the user gesture:
     - If 'LabTutor' exists in THIS browsing context: Chrome navigates it to
       TUTOR_URL and brings it to the foreground (per spec, features are ignored
       when the named window already exists).
     - If 'LabTutor' does NOT exist here (portal opened it from a different context):
       Chrome opens a fresh popup at TUTOR_URL with the given features. The
       ownership heartbeat closes the portal's tutor within ~500ms.
     Either way the user gets a tutor window in front. History is in localStorage
     so the conversation survives a reload. */
  function openTutor() {
    var left = Math.max(0, screen.availWidth  - WIN_W - 20);
    var top  = Math.max(0, Math.round((screen.availHeight - WIN_H) / 2));
    var feat = 'width='+WIN_W+',height='+WIN_H+',left='+left+',top='+top
             + ',resizable=yes,scrollbars=no,location=no,toolbar=no,menubar=no,status=no';
    _tutorWin = window.open(TUTOR_URL, 'LabTutor', feat);
  }

  /* ── button ── */
  var BTN_ID = 'sn-tutor-btn';
  var CSS_ID = 'sn-tutor-css';

  function injectStyles() {
    if (document.getElementById(CSS_ID)) return;
    var s = document.createElement('style');
    s.id = CSS_ID;
    s.textContent = [
      '#'+BTN_ID+'{',
        'position:fixed!important;bottom:1.5rem!important;right:1.5rem!important;',
        'z-index:2147483647!important;height:44px!important;padding:0 1.2rem!important;',
        'background:#FE572A!important;color:#FBFCFA!important;border:none!important;',
        'border-radius:22px!important;',
        'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif!important;',
        'font-size:.9rem!important;font-weight:700!important;cursor:pointer!important;',
        'box-shadow:0 4px 16px rgba(254,87,42,.55)!important;',
        'display:-webkit-flex!important;display:flex!important;',
        '-webkit-align-items:center!important;align-items:center!important;',
        '-webkit-transition:transform .15s,box-shadow .15s!important;',
        'transition:transform .15s,box-shadow .15s!important;',
      '}',
      '#'+BTN_ID+':hover{',
        'transform:translateY(-2px)!important;',
        'box-shadow:0 6px 22px rgba(254,87,42,.7)!important;',
      '}'
    ].join('');
    var target = document.head || document.documentElement;
    target.appendChild(s);
  }

  function mountButton() {
    if (!document.body) return;
    if (document.getElementById(BTN_ID)) return;
    injectStyles();
    var btn = document.createElement('button');
    btn.id        = BTN_ID;
    btn.title     = 'Open Lab Tutor';
    btn.innerHTML = '&#129302; Lab Tutor';
    btn.addEventListener('click', openTutor);
    document.body.appendChild(btn);
  }

  mountButton();
  setInterval(mountButton, 500);

})();
