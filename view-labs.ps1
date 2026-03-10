# ============================================================
# view-labs.ps1  —  Sonatype Digital Labs  Instructor View
# Run from the digital-labs repo root.
# Generates a self-contained HTML dashboard and opens it.
# ============================================================

Set-Location $PSScriptRoot

Write-Host "Fetching lab state from Terraform..." -ForegroundColor Cyan
$raw = terraform output -json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: terraform output failed. Are you in the repo root with state initialized?" -ForegroundColor Red
    Write-Host $raw
    exit 1
}

$tf = $raw | ConvertFrom-Json
$labs = $tf.labs.value
$dashboardUrl = $tf.dashboard_url.value

# Serialize labs map to JSON for embedding in HTML
$labsJson = $labs | ConvertTo-Json -Depth 5 -Compress

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss") + " UTC"

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Digital Labs — Instructor View</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@300;400;600&display=swap" rel="stylesheet">
<style>
  :root {
    --bg:       #0d1117;
    --surface:  #161b22;
    --border:   #21262d;
    --border2:  #30363d;
    --text:     #e6edf3;
    --muted:    #7d8590;
    --accent:   #58a6ff;
    --green:    #3fb950;
    --yellow:   #d29922;
    --red:      #f85149;
    --orange:   #e3b341;
    --mono:     'IBM Plex Mono', monospace;
    --sans:     'IBM Plex Sans', sans-serif;
  }
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  html { background: var(--bg); color: var(--text); font-family: var(--sans); }

  body {
    min-height: 100vh;
    background:
      radial-gradient(ellipse 80% 40% at 50% -10%, rgba(88,166,255,.08) 0%, transparent 60%),
      var(--bg);
  }

  header {
    border-bottom: 1px solid var(--border);
    padding: 20px 32px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    flex-wrap: wrap;
  }
  .logo {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .logo-icon {
    width: 32px; height: 32px;
    background: linear-gradient(135deg, #58a6ff 0%, #1f6feb 100%);
    border-radius: 8px;
    display: grid;
    place-items: center;
    font-size: 16px;
  }
  .logo-text { font-size: 15px; font-weight: 600; letter-spacing: .02em; }
  .logo-sub  { font-size: 11px; font-weight: 300; color: var(--muted); font-family: var(--mono); margin-top: 1px; }

  .header-right { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
  .snapshot-time { font-family: var(--mono); font-size: 11px; color: var(--muted); }
  .btn {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 6px 14px; border-radius: 6px; font-size: 12px; font-weight: 600;
    text-decoration: none; cursor: pointer; border: none; font-family: var(--sans);
    transition: opacity .15s;
  }
  .btn:hover { opacity: .8; }
  .btn-ghost  { background: transparent; border: 1px solid var(--border2); color: var(--muted); }
  .btn-primary{ background: #1f6feb; color: #fff; }

  main { padding: 28px 32px; max-width: 1400px; margin: 0 auto; }

  .summary-bar {
    display: flex; gap: 16px; margin-bottom: 28px; flex-wrap: wrap;
  }
  .stat-chip {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 12px 20px;
    display: flex; flex-direction: column; gap: 4px;
    min-width: 120px;
  }
  .stat-chip .val { font-size: 24px; font-weight: 600; font-family: var(--mono); }
  .stat-chip .lbl { font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: .06em; }

  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
    gap: 20px;
  }

  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    overflow: hidden;
    transition: border-color .2s, box-shadow .2s;
  }
  .card:hover {
    border-color: var(--border2);
    box-shadow: 0 4px 24px rgba(0,0,0,.4);
  }

  .card-header {
    padding: 16px 20px;
    border-bottom: 1px solid var(--border);
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
  }
  .card-key {
    font-family: var(--mono); font-size: 13px; font-weight: 600;
    display: flex; align-items: center; gap: 8px;
  }
  .status-dot {
    width: 8px; height: 8px; border-radius: 50%;
    background: var(--green);
    box-shadow: 0 0 6px var(--green);
    animation: pulse 2s ease-in-out infinite;
    flex-shrink: 0;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50%       { opacity: .4; }
  }

  .lease-badge {
    font-family: var(--mono); font-size: 11px; font-weight: 500;
    padding: 3px 10px; border-radius: 20px; white-space: nowrap;
  }
  .badge-green  { background: rgba(63,185,80,.15);  color: var(--green);  border: 1px solid rgba(63,185,80,.3);  }
  .badge-yellow { background: rgba(210,153,34,.15); color: var(--yellow); border: 1px solid rgba(210,153,34,.3); }
  .badge-red    { background: rgba(248,81,73,.15);  color: var(--red);    border: 1px solid rgba(248,81,73,.3);  }

  .card-body { padding: 16px 20px; display: flex; flex-direction: column; gap: 10px; }

  .field { display: flex; flex-direction: column; gap: 3px; }
  .field-label { font-size: 10px; text-transform: uppercase; letter-spacing: .08em; color: var(--muted); }
  .field-value { font-family: var(--mono); font-size: 12px; color: var(--text); }

  .countdown {
    font-family: var(--mono); font-size: 22px; font-weight: 600;
    letter-spacing: .04em;
  }

  .progress-track {
    height: 4px; background: var(--border); border-radius: 2px; overflow: hidden; margin-top: 4px;
  }
  .progress-fill {
    height: 100%; border-radius: 2px; transition: width 1s linear;
  }

  .divider { height: 1px; background: var(--border); margin: 4px 0; }

  .links { display: flex; gap: 8px; flex-wrap: wrap; padding: 14px 20px; border-top: 1px solid var(--border); }
  .link-btn {
    display: inline-flex; align-items: center; gap: 5px;
    padding: 5px 12px; border-radius: 6px; font-size: 11px; font-weight: 600;
    text-decoration: none; font-family: var(--sans);
    border: 1px solid var(--border2); color: var(--muted);
    transition: background .15s, color .15s, border-color .15s;
  }
  .link-btn:hover { background: var(--border); color: var(--text); border-color: var(--border2); }
  .link-btn.primary { border-color: #1f6feb; color: var(--accent); }
  .link-btn.primary:hover { background: rgba(31,111,235,.15); }

  .empty {
    grid-column: 1/-1;
    text-align: center;
    padding: 80px 20px;
    color: var(--muted);
  }
  .empty-icon { font-size: 48px; margin-bottom: 16px; }
  .empty p { font-size: 14px; }

  footer {
    padding: 20px 32px;
    border-top: 1px solid var(--border);
    font-size: 11px; color: var(--muted); font-family: var(--mono);
    display: flex; gap: 20px; flex-wrap: wrap;
  }
</style>
</head>
<body>

<header>
  <div class="logo">
    <div class="logo-icon">🔬</div>
    <div>
      <div class="logo-text">Sonatype Digital Labs</div>
      <div class="logo-sub">Instructor View</div>
    </div>
  </div>
  <div class="header-right">
    <span class="snapshot-time">Snapshot: $timestamp</span>
    <a href="$dashboardUrl" target="_blank" class="btn btn-ghost">📊 CloudWatch</a>
    <button class="btn btn-ghost" onclick="location.reload()">↻ Refresh</button>
  </div>
</header>

<main>
  <div class="summary-bar" id="summary-bar"></div>
  <div class="grid" id="grid"></div>
</main>

<footer>
  <span>Data from: terraform output -json</span>
  <span>Auto-generated by view-labs.ps1</span>
  <span>Counters update live · Refresh page to re-pull Terraform state</span>
</footer>

<script>
const LABS_JSON = $labsJson;

function pad(n) { return String(n).padStart(2, '0'); }

function fmtCountdown(msLeft) {
  if (msLeft <= 0) return { text: 'EXPIRED', cls: 'badge-red', color: '#f85149' };
  const s  = Math.floor(msLeft / 1000);
  const m  = Math.floor(s / 60);
  const h  = Math.floor(m / 60);
  const d  = Math.floor(h / 24);
  const rh = h % 24, rm = m % 60, rs = s % 60;
  const text = d > 0
    ? pad(d)+'d '+pad(rh)+'h '+pad(rm)+'m '+pad(rs)+'s'
    : pad(rh)+'h '+pad(rm)+'m '+pad(rs)+'s';
  const cls   = msLeft > 48*3600000 ? 'badge-green' : msLeft > 4*3600000 ? 'badge-yellow' : 'badge-red';
  const color = msLeft > 48*3600000 ? '#3fb950'     : msLeft > 4*3600000 ? '#d29922'      : '#f85149';
  return { text, cls, color };
}

function buildCards() {
  const keys = Object.keys(LABS_JSON);
  const grid = document.getElementById('grid');

  // Summary bar
  const totalMs = keys.map(k => new Date(LABS_JSON[k].terminates_at) - Date.now());
  const active  = totalMs.filter(ms => ms > 0).length;
  const expiring= totalMs.filter(ms => ms > 0 && ms < 48*3600000).length;
  document.getElementById('summary-bar').innerHTML = `
    <div class="stat-chip"><div class="val">${keys.length}</div><div class="lbl">Total Labs</div></div>
    <div class="stat-chip"><div class="val" style="color:var(--green)">${active}</div><div class="lbl">Active</div></div>
    <div class="stat-chip"><div class="val" style="color:var(--yellow)">${expiring}</div><div class="lbl">Expiring Soon</div></div>
  `;

  if (keys.length === 0) {
    grid.innerHTML = '<div class="empty"><div class="empty-icon">🧪</div><p>No labs currently deployed.</p></div>';
    return;
  }

  keys.forEach(k => {
    const lab = LABS_JSON[k];
    const expiresAt = new Date(lab.terminates_at);
    const launched  = lab.terminates_at; // best proxy we have

    const card = document.createElement('div');
    card.className = 'card';
    card.dataset.expires = expiresAt.getTime();
    card.dataset.key = k;

    card.innerHTML = `
      <div class="card-header">
        <div class="card-key">
          <div class="status-dot" id="dot-${k}"></div>
          ${k}
        </div>
        <div class="lease-badge badge-green" id="badge-${k}">calculating...</div>
      </div>
      <div class="card-body">
        <div class="field">
          <div class="field-label">Time Remaining</div>
          <div class="countdown" id="cd-${k}">--d --h --m --s</div>
          <div class="progress-track">
            <div class="progress-fill" id="prog-${k}" style="width:100%; background:var(--green)"></div>
          </div>
        </div>
        <div class="divider"></div>
        <div class="field">
          <div class="field-label">Expires</div>
          <div class="field-value">${expiresAt.toLocaleString()}</div>
        </div>
        <div class="field">
          <div class="field-label">Instance ID</div>
          <div class="field-value">${lab.instance_id}</div>
        </div>
        <div class="field">
          <div class="field-label">Public IP</div>
          <div class="field-value">${lab.public_ip}</div>
        </div>
      </div>
      <div class="links">
        <a href="${lab.lab_url}" target="_blank" class="link-btn primary">🌐 Portal</a>
        <a href="${lab.nexus_url}" target="_blank" class="link-btn">📦 Nexus</a>
        <a href="${lab.iq_url}" target="_blank" class="link-btn">🔒 IQ Server</a>
      </div>
    `;

    grid.appendChild(card);
  });
}

function tick() {
  document.querySelectorAll('.card[data-expires]').forEach(card => {
    const k       = card.dataset.key;
    const expires = parseInt(card.dataset.expires);
    const msLeft  = expires - Date.now();
    const leaseDuration = 7 * 24 * 3600 * 1000; // assume max 1w; progress relative
    const { text, cls, color } = fmtCountdown(msLeft);

    const cdEl    = document.getElementById('cd-' + k);
    const badgeEl = document.getElementById('badge-' + k);
    const progEl  = document.getElementById('prog-' + k);
    const dotEl   = document.getElementById('dot-' + k);

    if (cdEl)    cdEl.textContent = text;
    if (badgeEl) { badgeEl.textContent = msLeft > 0 ? 'Active' : 'Expired'; badgeEl.className = 'lease-badge ' + cls; }
    if (progEl)  { const pct = Math.max(0, Math.min(100, (msLeft / leaseDuration) * 100)); progEl.style.width = pct + '%'; progEl.style.background = color; }
    if (dotEl)   { dotEl.style.background = color; dotEl.style.boxShadow = '0 0 6px ' + color; }
  });
}

buildCards();
tick();
setInterval(tick, 1000);
</script>
</body>
</html>
"@

$tmpFile = Join-Path $env:TEMP "digital-labs-instructor.html"
$html | Out-File -FilePath $tmpFile -Encoding UTF8
Start-Process $tmpFile
Write-Host "Opened instructor view: $tmpFile" -ForegroundColor Green
