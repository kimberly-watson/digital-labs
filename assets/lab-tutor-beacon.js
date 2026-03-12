/* lab-tutor-beacon.js
   Two jobs:
   1. Write product + URL to localStorage every 2s so the tutor popup knows context
   2. Mount a fixed "Lab Tutor" button on the right side of the page that opens
      the tutor popup. setInterval remounts it if ExtJS wipes it. */
(function () {
  var PRODUCT   = window.__snLabProduct || '';
  if (!PRODUCT) return;

  var TUTOR_URL = 'http://' + location.hostname + '/tutor';
  var WIN_W     = 440;
  var WIN_H     = 640;
  var _tutorWin = null;

  /* ── storage with fallback ── */
  var _mem = {};
  var store = (function () {
    try { localStorage.setItem('__t','1'); localStorage.removeItem('__t'); return localStorage; } catch(e) {}
    try { sessionStorage.setItem('__t','1'); sessionStorage.removeItem('__t'); return sessionStorage; } catch(e2) {}
    return { setItem: function(k,v){_mem[k]=v;}, getItem: function(k){return _mem[k]!==undefined?_mem[k]:null;}, removeItem: function(k){delete _mem[k];} };
  })();

  /* ── context pulse ── */
  function pulse() {
    try {
      store.setItem('snLabProduct', PRODUCT);
      store.setItem('snLabUrl',     location.href);
      store.setItem('snLabTs',      String(Date.now()));
    } catch(e) {}
  }
  pulse();
  setInterval(pulse, 2000);

  /* ── open / focus tutor popup ── */
  function openTutor() {
    /* Position: right edge of screen, vertically centered */
    var left = Math.max(0, screen.availWidth  - WIN_W - 20);
    var top  = Math.max(0, Math.round((screen.availHeight - WIN_H) / 2));
    var feat = 'width='+WIN_W+',height='+WIN_H+',left='+left+',top='+top
             + ',resizable=yes,scrollbars=no,location=no,toolbar=no,menubar=no,status=no';

    if (_tutorWin && !_tutorWin.closed) {
      _tutorWin.focus();
      return;
    }
    _tutorWin = window.open(TUTOR_URL, 'LabTutor', feat);
  }

  /* ── button styles ── */
  var BTN_ID  = 'sn-tutor-btn';
  var CSS_ID  = 'sn-tutor-css';

  function injectStyles() {
    if (document.getElementById(CSS_ID)) return;
    var s = document.createElement('style');
    s.id = CSS_ID;
    s.textContent = [
      '#'+BTN_ID+'{',
        'position:fixed!important;',
        'bottom:1.5rem!important;',
        'right:1.5rem!important;',
        'z-index:2147483647!important;',
        'height:44px!important;',
        'padding:0 1.2rem!important;',
        'background:#FE572A!important;',
        'color:#FBFCFA!important;',
        'border:none!important;',
        'border-radius:22px!important;',
        'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif!important;',
        'font-size:.9rem!important;',
        'font-weight:700!important;',
        'cursor:pointer!important;',
        'box-shadow:0 4px 16px rgba(254,87,42,.55)!important;',
        'display:-webkit-flex!important;display:flex!important;',
        '-webkit-align-items:center!important;align-items:center!important;',
        'gap:.45rem!important;',
        '-webkit-transition:transform .15s,box-shadow .15s!important;',
        'transition:transform .15s,box-shadow .15s!important;',
      '}',
      '#'+BTN_ID+':hover{',
        'transform:translateY(-2px)!important;',
        'box-shadow:0 6px 22px rgba(254,87,42,.7)!important;',
      '}'
    ].join('');
    /* Attach to <head> — survives body replacement */
    var target = document.head || document.documentElement;
    target.appendChild(s);
  }

  /* ── mount button ── */
  function mountButton() {
    if (!document.body)                          return;
    if (document.getElementById(BTN_ID))        return;
    injectStyles();
    var btn = document.createElement('button');
    btn.id          = BTN_ID;
    btn.title       = 'Open Lab Tutor';
    btn.innerHTML   = '&#129302; Lab Tutor';
    btn.addEventListener('click', openTutor);
    document.body.appendChild(btn);
  }

  /* Try immediately, then every 500ms to survive ExtJS body replacement */
  mountButton();
  setInterval(mountButton, 500);

})();
