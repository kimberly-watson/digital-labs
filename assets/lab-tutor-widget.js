(function () {
  var PRODUCT  = window.__snLabProduct || 'the lab environment';
  var ENDPOINT = 'http://' + location.hostname + '/chat';
  var chatHistory = [];
  var controller  = null;

  /* ── styles ── */
  var css = document.createElement('style');
  css.textContent = [
    '#sn-bubble{position:fixed;bottom:2rem;right:2rem;height:48px;border-radius:24px;',
    'background:#FE572A;border:none;cursor:pointer;font-size:.95rem;font-weight:700;',
    'display:flex;align-items:center;gap:.5rem;padding:0 1.25rem;',
    'box-shadow:0 4px 20px rgba(254,87,42,.5);z-index:2147483646;color:#FBFCFA;',
    'transition:transform .15s,box-shadow .15s;}',
    '#sn-bubble:hover{transform:translateY(-2px);box-shadow:0 6px 24px rgba(254,87,42,.65);}',
    '#sn-win{position:fixed;bottom:5.5rem;right:2rem;width:390px;max-height:540px;',
    'background:#090B2F;border:2px solid #2D36EC;border-radius:18px;',
    'display:none;flex-direction:column;',
    'box-shadow:0 8px 40px rgba(45,54,236,.3);z-index:2147483647;overflow:hidden;}',
    '#sn-win.open{display:flex;}',
    '#sn-hdr{background:#2D36EC;padding:1rem 1.2rem;font-weight:700;font-size:.95rem;',
    'color:#FBFCFA;display:flex;justify-content:space-between;align-items:center;}',
    '#sn-hdr span small{font-weight:400;opacity:.75;margin-left:.5rem;font-size:.8rem;}',
    '#sn-close{background:none;border:none;color:rgba(255,255,255,.8);cursor:pointer;',
    'font-size:1.2rem;line-height:1;}',
    '#sn-msgs{flex:1;overflow-y:auto;padding:1rem;display:flex;flex-direction:column;',
    'gap:.75rem;min-height:280px;max-height:370px;}',
    '.sn-msg{max-width:85%;padding:.65rem 1rem;border-radius:14px;',
    'font-size:.88rem;line-height:1.55;}',
    '.sn-msg.user{background:#FE572A;align-self:flex-end;color:#FBFCFA;border-bottom-right-radius:4px;}',
    '.sn-msg.bot{background:#0d1245;border:1px solid #2D36EC;align-self:flex-start;',
    'color:#F1F5ED;border-bottom-left-radius:4px;}',
    '.sn-msg.think{color:#2D36EC;font-style:italic;background:transparent;border:none;}',
    '#sn-row{display:flex;gap:.5rem;padding:.75rem;border-top:1px solid #2D36EC;}',
    '#sn-input{flex:1;background:#0d1245;border:1px solid #2D36EC;border-radius:10px;',
    'padding:.55rem .75rem;color:#FBFCFA;font-size:.88rem;resize:none;outline:none;}',
    '#sn-input::placeholder{color:rgba(241,245,237,.4);}',
    '#sn-send{background:#FE572A;border:none;border-radius:10px;',
    'padding:.55rem 1rem;color:#FBFCFA;cursor:pointer;font-size:.88rem;font-weight:700;}',
    '#sn-send:hover{background:#e04820;}',
    '#sn-send:disabled{background:#2D36EC;opacity:.4;cursor:not-allowed;}'
  ].join('');
  document.head.appendChild(css);

  /* ── DOM ── */
  var bubble = document.createElement('button');
  bubble.id = 'sn-bubble';
  bubble.title = 'Open Lab Tutor';
  bubble.innerHTML = '&#129302; Lab Tutor';

  var win = document.createElement('div');
  win.id = 'sn-win';
  win.innerHTML = [
    '<div id="sn-hdr">',
    '  <span>&#129302; Sonatype Lab Tutor<small>' + PRODUCT + '</small></span>',
    '  <button id="sn-close">&#x2715;</button>',
    '</div>',
    '<div id="sn-msgs">',
    '  <div class="sn-msg bot">Hi! I\'m your Lab Tutor. I can see you\'re working in ',
    PRODUCT + '. Ask me anything about what you\'re exploring.</div>',
    '</div>',
    '<div id="sn-row">',
    '  <textarea id="sn-input" rows="2" placeholder="Ask the lab tutor..."></textarea>',
    '  <button id="sn-send">Send</button>',
    '</div>'
  ].join('');

  document.body.appendChild(bubble);
  document.body.appendChild(win);

  /* ── helpers ── */
  function addMsg(text, cls) {
    var msgs = document.getElementById('sn-msgs');
    var d = document.createElement('div');
    d.className = 'sn-msg ' + cls;
    d.textContent = text;
    msgs.appendChild(d);
    msgs.scrollTop = msgs.scrollHeight;
    return d;
  }

  function toggleChat() {
    win.classList.toggle('open');
    if (win.classList.contains('open')) document.getElementById('sn-input').focus();
  }

  async function sendMessage() {
    var input  = document.getElementById('sn-input');
    var sendBtn = document.getElementById('sn-send');
    var text = input.value.trim();
    if (!text) return;

    addMsg(text, 'user');
    chatHistory.push({ role: 'user', content: text });
    input.value = '';
    sendBtn.disabled = true;

    var thinking = addMsg('Thinking…', 'think');
    controller = new AbortController();
    var timer = setTimeout(function () { controller.abort(); }, 30000);

    try {
      var resp = await fetch(ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messages: chatHistory, product: PRODUCT }),
        signal: controller.signal
      });
      clearTimeout(timer);
      var data = await resp.json();
      thinking.remove();
      var reply = data.reply || 'No response received.';
      addMsg(reply, 'bot');
      chatHistory.push({ role: 'assistant', content: reply });
    } catch (err) {
      clearTimeout(timer);
      thinking.remove();
      var msg = err.name === 'AbortError'
        ? 'Request timed out — please try again.'
        : 'The tutor is not available right now. Please try again in a moment.';
      addMsg(msg, 'think');
    } finally {
      sendBtn.disabled = false;
    }
  }

  /* ── event wiring ── */
  bubble.addEventListener('click', toggleChat);
  document.getElementById('sn-close').addEventListener('click', toggleChat);
  document.getElementById('sn-send').addEventListener('click', sendMessage);
  document.getElementById('sn-input').addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage(); }
  });
})();
