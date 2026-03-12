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

  /* ── raiseTutor ──
     Step 1: peek for 'LabTutor' in our own browsing context (works when this tab
     was opened from the same context that opened the tutor).
     Step 2: if the peek returns a blank window (different browsing context — the
     portal opened Nexus/IQ as a new tab, so they share an opener chain but NOT a
     context), postMessage the portal (window.opener) and ask IT to do the raise.
     The portal opened the tutor, so it CAN find 'LabTutor' directly.
     visibilitychange is intentionally NOT used — raises steal focus, which fires
     visibilitychange, creating an infinite loop. One-shot on page load only. */
  function raiseTutor() {
    var HOSTNAME_ORIGIN = 'http://' + location.hostname;

    /* Step 1: same-context lookup */
    var peek = null;
    try { peek = window.open('', 'LabTutor'); } catch(e) {}
    if (peek && !peek.closed) {
      try {
        var href = peek.location.href;
        if (href && href !== 'about:blank') {
          /* Tutor found in same context — raise via hash navigation */
          try { window.open(TUTOR_URL + '#raise', 'LabTutor'); } catch(e) {}
          _tutorWin = peek;
          return;
        }
        /* Blank = different browsing context. Close the stray blank window. */
        peek.close();
      } catch(e) {
        /* Cross-origin exception = tutor IS loaded at port 80 in same context */
        try { window.open(TUTOR_URL + '#raise', 'LabTutor'); } catch(e2) {}
        _tutorWin = peek;
        return;
      }
    }

    /* Step 2: ask the portal (opener) to raise on our behalf */
    try {
      if (window.opener && !window.opener.closed) {
        window.opener.postMessage({ type: 'snRaiseTutor' }, HOSTNAME_ORIGIN);
      }
    } catch(e) {}
  }

  raiseTutor();

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
     window.open('','LabTutor') either returns the existing named popup (same
     browsing context) or a NEW blank popup (different tab context — Chrome can't
     cross browsing-context boundaries). We never close-and-reopen: instead we
     navigate the blank window in-place to avoid spawning a second instance.
     Conversation is preserved via port-80 localStorage regardless. */
  function openTutor() {
    var left = Math.max(0, screen.availWidth  - WIN_W - 20);
    var top  = Math.max(0, Math.round((screen.availHeight - WIN_H) / 2));
    var feat = 'width='+WIN_W+',height='+WIN_H+',left='+left+',top='+top
             + ',resizable=yes,scrollbars=no,location=no,toolbar=no,menubar=no,status=no';

    var existing = null;
    try { existing = window.open('', 'LabTutor'); } catch(e) {}

    if (existing && !existing.closed) {
      try {
        var href = existing.location.href;
        if (href && href !== 'about:blank') {
          /* Same-context popup already loaded — just focus it */
          existing.focus();
          _tutorWin = existing;
          return;
        }
        /* Blank popup (different-context): resizeTo/moveTo are blocked by browsers
           on windows not opened by this script. Close it and open fresh below
           with correct size features. The ownership heartbeat evicts the old
           portal tutor within ~500ms. */
        existing.close();
      } catch(e) {
        /* Cross-origin exception = tutor IS loaded at port 80 — raise it */
        _tutorWin = existing;
        try { window.open(TUTOR_URL + '#raise', 'LabTutor'); } catch(e2) {}
        return;
      }
    }

    /* No window at all — open fresh */
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
