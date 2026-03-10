# ============================================================
# view-labs.ps1  --  Sonatype Digital Labs  Sonatype Personnel View
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

# Build HTML as plain ASCII-safe string; no backtick JS template literals,
# no em-dashes, no special chars that PowerShell here-strings mangle.
# JS template literals (backticks) replaced with string concatenation.
$html = '<!DOCTYPE html>' + [char]10
$html += '<html lang="en"><head>' + [char]10
$html += '<meta charset="UTF-8">' + [char]10
$html += '<meta name="viewport" content="width=device-width, initial-scale=1.0">' + [char]10
$html += '<title>Digital Labs &mdash; Sonatype Personnel View</title>' + [char]10
$html += '<style>' + [char]10
$html += ':root{--bg:#0d1117;--surface:#161b22;--border:#21262d;--border2:#30363d;--text:#e6edf3;--muted:#7d8590;--accent:#58a6ff;--green:#3fb950;--yellow:#d29922;--red:#f85149;--mono:"Consolas","Courier New",monospace;--sans:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;}' + [char]10
$html += '*,*::before,*::after{box-sizing:border-box;margin:0;padding:0;}' + [char]10
$html += 'html{background:var(--bg);color:var(--text);font-family:var(--sans);}' + [char]10
$html += 'body{min-height:100vh;background:radial-gradient(ellipse 80% 40% at 50% -10%,rgba(88,166,255,.08) 0%,transparent 60%),var(--bg);}' + [char]10
$html += 'header{border-bottom:1px solid var(--border);padding:20px 32px;display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;}' + [char]10
$html += '.logo{display:flex;align-items:center;gap:12px;}' + [char]10
$html += '.logo-icon{width:32px;height:32px;background:linear-gradient(135deg,#58a6ff 0%,#1f6feb 100%);border-radius:8px;display:grid;place-items:center;font-size:16px;}' + [char]10
$html += '.logo-text{font-size:15px;font-weight:600;letter-spacing:.02em;}' + [char]10
$html += '.logo-sub{font-size:11px;color:var(--muted);font-family:var(--mono);margin-top:1px;}' + [char]10
$html += '.header-right{display:flex;align-items:center;gap:16px;flex-wrap:wrap;}' + [char]10
$html += '.snapshot-time{font-family:var(--mono);font-size:11px;color:var(--muted);}' + [char]10
$html += '.btn{display:inline-flex;align-items:center;gap:6px;padding:6px 14px;border-radius:6px;font-size:12px;font-weight:600;text-decoration:none;cursor:pointer;border:none;font-family:var(--sans);transition:opacity .15s;}' + [char]10
$html += '.btn:hover{opacity:.8;}.btn-ghost{background:transparent;border:1px solid var(--border2);color:var(--muted);}' + [char]10
$html += 'main{padding:28px 32px;max-width:1400px;margin:0 auto;}' + [char]10
$html += '.summary-bar{display:flex;gap:16px;margin-bottom:28px;flex-wrap:wrap;}' + [char]10
$html += '.stat-chip{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:12px 20px;display:flex;flex-direction:column;gap:4px;min-width:120px;}' + [char]10
$html += '.stat-chip .val{font-size:24px;font-weight:600;font-family:var(--mono);}' + [char]10
$html += '.stat-chip .lbl{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;}' + [char]10
$html += '.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(380px,1fr));gap:20px;}' + [char]10

$html += '.card{background:var(--surface);border:1px solid var(--border);border-radius:12px;overflow:hidden;transition:border-color .2s,box-shadow .2s;}' + [char]10
$html += '.card:hover{border-color:var(--border2);box-shadow:0 4px 24px rgba(0,0,0,.4);}' + [char]10
$html += '.card-header{padding:16px 20px;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;gap:12px;}' + [char]10
$html += '.card-key{font-family:var(--mono);font-size:13px;font-weight:600;display:flex;align-items:center;gap:8px;}' + [char]10
$html += '.status-dot{width:8px;height:8px;border-radius:50%;background:var(--green);box-shadow:0 0 6px var(--green);animation:pulse 2s ease-in-out infinite;flex-shrink:0;}' + [char]10
$html += '@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}' + [char]10
$html += '.lease-badge{font-family:var(--mono);font-size:11px;font-weight:500;padding:3px 10px;border-radius:20px;white-space:nowrap;}' + [char]10
$html += '.badge-green{background:rgba(63,185,80,.15);color:var(--green);border:1px solid rgba(63,185,80,.3);}' + [char]10
$html += '.badge-yellow{background:rgba(210,153,34,.15);color:var(--yellow);border:1px solid rgba(210,153,34,.3);}' + [char]10
$html += '.badge-red{background:rgba(248,81,73,.15);color:var(--red);border:1px solid rgba(248,81,73,.3);}' + [char]10
$html += '.card-body{padding:16px 20px;display:flex;flex-direction:column;gap:10px;}' + [char]10
$html += '.field{display:flex;flex-direction:column;gap:3px;}' + [char]10
$html += '.field-label{font-size:10px;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);}' + [char]10
$html += '.field-value{font-family:var(--mono);font-size:12px;color:var(--text);}' + [char]10
$html += '.countdown{font-family:var(--mono);font-size:22px;font-weight:600;letter-spacing:.04em;}' + [char]10
$html += '.progress-track{height:4px;background:var(--border);border-radius:2px;overflow:hidden;margin-top:4px;}' + [char]10
$html += '.progress-fill{height:100%;border-radius:2px;transition:width 1s linear;}' + [char]10
$html += '.divider{height:1px;background:var(--border);margin:4px 0;}' + [char]10
$html += '.links{display:flex;gap:8px;flex-wrap:wrap;padding:14px 20px;border-top:1px solid var(--border);}' + [char]10
$html += '.link-btn{display:inline-flex;align-items:center;gap:5px;padding:5px 12px;border-radius:6px;font-size:11px;font-weight:600;text-decoration:none;font-family:var(--sans);border:1px solid var(--border2);color:var(--muted);transition:background .15s,color .15s;}' + [char]10
$html += '.link-btn:hover{background:var(--border);color:var(--text);}' + [char]10
$html += '.link-btn.primary{border-color:#1f6feb;color:var(--accent);}' + [char]10
$html += '.link-btn.primary:hover{background:rgba(31,111,235,.15);}' + [char]10
$html += '.empty{grid-column:1/-1;text-align:center;padding:80px 20px;color:var(--muted);}' + [char]10
$html += '.empty-icon{font-size:48px;margin-bottom:16px;}' + [char]10
$html += '.empty p{font-size:14px;}' + [char]10
$html += 'footer{padding:20px 32px;border-top:1px solid var(--border);font-size:11px;color:var(--muted);font-family:var(--mono);display:flex;gap:20px;flex-wrap:wrap;}' + [char]10
$html += '</style></head><body>' + [char]10

$html += '<header>' + [char]10
$html += '  <div class="logo"><div class="logo-icon">&#x1F52C;</div><div>' + [char]10
$html += '    <div class="logo-text">Sonatype Digital Labs</div>' + [char]10
$html += '    <div class="logo-sub">Sonatype Personnel View</div>' + [char]10
$html += '  </div></div>' + [char]10
$html += '  <div class="header-right">' + [char]10
$html += '    <span class="snapshot-time">Snapshot: ' + $timestamp + '</span>' + [char]10
$html += '    <a href="' + $dashboardUrl + '" target="_blank" class="btn btn-ghost">&#x1F4CA; CloudWatch</a>' + [char]10
$html += '    <button class="btn btn-ghost" onclick="location.reload()">&#x21BB; Refresh</button>' + [char]10
$html += '  </div>' + [char]10
$html += '</header>' + [char]10
$html += '<main><div class="summary-bar" id="summary-bar"></div><div class="grid" id="grid"></div></main>' + [char]10
$html += '<footer>' + [char]10
$html += '  <span>Data from: terraform output -json</span>' + [char]10
$html += '  <span>Auto-generated by view-labs.ps1</span>' + [char]10
$html += '  <span>Counters update live &middot; Refresh page to re-pull Terraform state</span>' + [char]10
$html += '</footer>' + [char]10

# Embed the labs JSON and all JavaScript
# Note: no JS template literals (backticks) used -- all string concatenation
# to avoid PowerShell here-string escape conflicts.
$html += '<script>' + [char]10
$html += 'var LABS_JSON = ' + $labsJson + ';' + [char]10
$html += @'
function pad(n){return String(n).padStart(2,'0');}
function fmtCountdown(ms){
  if(ms<=0)return{text:'EXPIRED',cls:'badge-red',color:'#f85149'};
  var s=Math.floor(ms/1000),m=Math.floor(s/60),h=Math.floor(m/60),d=Math.floor(h/24);
  var rh=h%24,rm=m%60,rs=s%60;
  var text=d>0?pad(d)+'d '+pad(rh)+'h '+pad(rm)+'m '+pad(rs)+'s':pad(rh)+'h '+pad(rm)+'m '+pad(rs)+'s';
  var cls=ms>48*3600000?'badge-green':ms>4*3600000?'badge-yellow':'badge-red';
  var color=ms>48*3600000?'#3fb950':ms>4*3600000?'#d29922':'#f85149';
  return{text:text,cls:cls,color:color};
}
function buildCards(){
  var keys=Object.keys(LABS_JSON);
  var grid=document.getElementById('grid');
  var totalMs=keys.map(function(k){return new Date(LABS_JSON[k].terminates_at)-Date.now();});
  var active=totalMs.filter(function(ms){return ms>0;}).length;
  var expiring=totalMs.filter(function(ms){return ms>0&&ms<48*3600000;}).length;
  document.getElementById('summary-bar').innerHTML=
    '<div class="stat-chip"><div class="val">'+keys.length+'</div><div class="lbl">Total Labs</div></div>'+
    '<div class="stat-chip"><div class="val" style="color:var(--green)">'+active+'</div><div class="lbl">Active</div></div>'+
    '<div class="stat-chip"><div class="val" style="color:var(--yellow)">'+expiring+'</div><div class="lbl">Expiring Soon</div></div>';
  if(keys.length===0){
    grid.innerHTML='<div class="empty"><div class="empty-icon">&#x1F9EA;</div><p>No labs currently deployed.</p></div>';
    return;
  }
  keys.forEach(function(k){
    var lab=LABS_JSON[k];
    var expiresAt=new Date(lab.terminates_at);
    var card=document.createElement('div');
    card.className='card';
    card.dataset.expires=expiresAt.getTime();
    card.dataset.key=k;
    card.innerHTML=
      '<div class="card-header">'+
        '<div class="card-key"><div class="status-dot" id="dot-'+k+'"></div>'+k+'</div>'+
        '<div class="lease-badge badge-green" id="badge-'+k+'">calculating...</div>'+
      '</div>'+
      '<div class="card-body">'+
        '<div class="field"><div class="field-label">Time Remaining</div>'+
          '<div class="countdown" id="cd-'+k+'">calculating...</div>'+
          '<div class="progress-track"><div class="progress-fill" id="prog-'+k+'" style="width:100%;background:var(--green)"></div></div>'+
        '</div>'+
        '<div class="divider"></div>'+
        '<div class="field"><div class="field-label">Expires</div><div class="field-value">'+expiresAt.toLocaleString()+'</div></div>'+
        '<div class="field"><div class="field-label">Instance ID</div><div class="field-value">'+lab.instance_id+'</div></div>'+
        '<div class="field"><div class="field-label">Public IP</div><div class="field-value">'+lab.public_ip+'</div></div>'+
      '</div>'+
      '<div class="links">'+
        '<a href="'+lab.lab_url+'" target="_blank" class="link-btn primary">&#x1F310; Portal</a>'+
        '<a href="'+lab.nexus_url+'" target="_blank" class="link-btn">&#x1F4E6; Nexus</a>'+
        '<a href="'+lab.iq_url+'" target="_blank" class="link-btn">&#x1F512; IQ Server</a>'+
      '</div>';
    grid.appendChild(card);
  });
}
function tick(){
  document.querySelectorAll('.card[data-expires]').forEach(function(card){
    var k=card.dataset.key;
    var expires=parseInt(card.dataset.expires);
    var ms=expires-Date.now();
    var leaseDuration=7*24*3600*1000;
    var r=fmtCountdown(ms);
    var cdEl=document.getElementById('cd-'+k);
    var badgeEl=document.getElementById('badge-'+k);
    var progEl=document.getElementById('prog-'+k);
    var dotEl=document.getElementById('dot-'+k);
    if(cdEl)cdEl.textContent=r.text;
    if(badgeEl){badgeEl.textContent=ms>0?'Active':'Expired';badgeEl.className='lease-badge '+r.cls;}
    if(progEl){var pct=Math.max(0,Math.min(100,(ms/leaseDuration)*100));progEl.style.width=pct+'%';progEl.style.background=r.color;}
    if(dotEl){dotEl.style.background=r.color;dotEl.style.boxShadow='0 0 6px '+r.color;}
  });
}
buildCards();tick();setInterval(tick,1000);
'@
$html += [char]10 + '</script></body></html>'

# Write with no BOM (established pattern for this project)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$tmpFile = Join-Path $env:TEMP "digital-labs-instructor.html"
[System.IO.File]::WriteAllText($tmpFile, $html, $utf8NoBom)
Start-Process $tmpFile
Write-Host "Opened instructor view: $tmpFile" -ForegroundColor Green

