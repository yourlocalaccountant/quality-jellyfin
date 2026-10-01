#!/usr/bin/env bash
set -euo pipefail

DIRS=(/usr/share/jellyfin/web /jellyfin/jellyfin-web /usr/lib/jellyfin/bin/jellyfin-web /opt/jellyfin/web /var/lib/jellyfin/web)
WEB=""
for d in "${DIRS[@]}"; do
  if [ -f "$d/index.html" ]; then WEB="$d"; break; fi
done
if [ -z "$WEB" ] && [ -n "${JELLYFIN_WEB:-}" ] && [ -f "$JELLYFIN_WEB/index.html" ]; then
  WEB="$JELLYFIN_WEB"
fi
if [ -z "$WEB" ]; then
  echo "jellyfin-web not found. Run again with JELLYFIN_WEB=/path/to/web"
  exit 1
fi
echo "Using web directory: $WEB"

cp -n "$WEB/index.html" "$WEB/index.html.bak-quality" 2>/dev/null || true

cat > "$WEB/quality-labels.js" <<'EOF'
(function () {
  'use strict';
  var VERSION = 'v5';
  if (window.__qualityLabelsVersion === VERSION) return;
  window.__qualityLabelsVersion = VERSION;

  // [minimum Mbps, label]. Edit this table to change which resolution each bitrate gets.
  var MAP = [
    [80,  '4K'],
    [5,   '1080p'],
    [1.5, '720p'],
    [0.4, '480p'],
    [0.3, '360p'],
    [0,   '240p']
  ];

  var BARE = /^\s*(\d+(?:\.\d+)?)\s*(Mbps|kbps)\s*$/i;
  var LADDER = /^\s*(4K|\d{3,4}p)\s*-\s*(\d+(?:\.\d+)?)\s*(Mbps|kbps)\s*$/i;
  var DONE = /^\s*(4K|\d{3,4}p)\s*\(/i;

  function resFor(mbps) {
    for (var i = 0; i < MAP.length; i++) {
      if (mbps >= MAP[i][0]) return MAP[i][1];
    }
    return MAP[MAP.length - 1][1];
  }

  function toMbps(n, unit) {
    var v = parseFloat(n);
    return /kbps/i.test(unit) ? v / 1000 : v;
  }

  function squash(el) {
    return (el.textContent || '').replace(/\s+/g, ' ').trim();
  }

  // The "Quality   4 Mbps" row in the main settings menu
  function isQualityRow(node) {
    var el = node.parentElement;
    for (var i = 0; el && i < 5; i++, el = el.parentElement) {
      var t = squash(el);
      if (t.length < 40 && /^Quality\b/i.test(t)) return true;
    }
    return false;
  }

  // The submenu / dropdown that contains nothing but "Auto" and bitrates
  function isQualityList(node) {
    var el = node.parentElement;
    for (var i = 0; el && i < 8; i++, el = el.parentElement) {
      var t = squash(el);
      if (t.length > 300) return false;
      var hits = t.match(/(\d+(?:\.\d+)?)\s*(Mbps|kbps)/gi);
      if (!hits || hits.length < 2) continue;
      var rest = t
        .replace(/(\d+(?:\.\d+)?)\s*(Mbps|kbps)/gi, '')
        .replace(/\b(4K|\d{3,4}p)\b/gi, '')
        .replace(/\b(Auto|check|done)\b/gi, '')
        .replace(/[^A-Za-z0-9]/g, '');
      if (rest.length === 0) return true;
    }
    return false;
  }

  function plan(node) {
    var s = node.nodeValue;
    if (!s || s.length > 40 || DONE.test(s)) return null;
    var p = node.parentElement;
    if (!p || /^(SCRIPT|STYLE|TEXTAREA|INPUT)$/.test(p.tagName)) return null;

    var m = s.match(LADDER);
    if (m) return m[1] + ' (' + m[2] + ' ' + m[3] + ')';

    m = s.match(BARE);
    if (m && (isQualityRow(node) || isQualityList(node))) {
      return resFor(toMbps(m[1], m[2])) + ' (' + m[1] + ' ' + m[2] + ')';
    }
    return null;
  }

  function scan() {
    if (!document.body) return 0;
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    var jobs = [];
    // Decide everything first, then change the page, so edits can't affect detection
    while (walker.nextNode()) {
      var n = walker.currentNode;
      var out = plan(n);
      if (out !== null && out !== n.nodeValue) jobs.push([n, out]);
    }
    for (var i = 0; i < jobs.length; i++) jobs[i][0].nodeValue = jobs[i][1];
    return jobs.length;
  }

  var queued = false;
  function schedule() {
    if (queued) return;
    queued = true;
    (window.requestAnimationFrame || window.setTimeout)(function () {
      queued = false;
      try { scan(); } catch (e) { console.error('[quality-labels]', e); }
    });
  }

  // Run qualityLabelsDebug() in the browser console to see every bitrate text on screen
  window.qualityLabelsDebug = function () {
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    var out = [];
    while (walker.nextNode()) {
      var n = walker.currentNode;
      if (/(Mbps|kbps)/i.test(n.nodeValue) && n.parentElement) {
        var p = n.parentElement;
        out.push({
          text: n.nodeValue.trim(),
          tag: p.tagName,
          cls: p.className,
          row: isQualityRow(n),
          list: isQualityList(n),
          html: p.outerHTML.slice(0, 160)
        });
      }
    }
    console.table(out);
    return out;
  };

  function start() {
    new MutationObserver(schedule).observe(document.body, {
      childList: true, subtree: true, characterData: true
    });
    setInterval(schedule, 1000);
    schedule();
    console.log('[quality-labels] ' + VERSION + ' loaded');
  }

  if (document.body) start();
  else document.addEventListener('DOMContentLoaded', start);
})();
EOF

chmod 644 "$WEB/quality-labels.js"

sed -i -E 's#<script src="quality-labels\.js[^"]*"></script>##g' "$WEB/index.html"
sed -i "s#</body>#<script src=\"quality-labels.js?v=$(date +%s)\"></script></body>#" "$WEB/index.html"

if grep -q 'quality-labels.js' "$WEB/index.html"; then
  echo "OK: script tag present in index.html"
else
  echo "FAILED: script tag was not added to index.html"
  exit 1
fi

CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:8096/web/quality-labels.js" || true)
echo "Server check: HTTP ${CODE:-n/a} (200 means Jellyfin is serving the script)"
echo "Done. Hard refresh your browser (Ctrl+Shift+R)."
