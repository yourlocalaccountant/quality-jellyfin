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
  var VERSION = 'v4';
  if (window.__qualityLabelsLoaded) return;
  window.__qualityLabelsLoaded = true;

  // "1080p - 10 Mbps" (Jellyfin's own names) and bare "4 Mbps" (settings row)
  var LADDER = /^\s*(4K|\d{3,4}p) - (\d+(?:\.\d+)?) ?(Mbps|kbps)\s*$/i;
  var BARE = /^\s*(\d+(?:\.\d+)?) ?(Mbps|kbps)\s*$/i;
  var DONE = /^\s*(4K|\d{3,4}p) \(\d/i;

  // Only used when no video is playing, so it is approximate
  var FALLBACK = [[80, '4K'], [8, '1080p'], [1.5, '720p'], [0.4, '480p'], [0.3, '360p'], [0, '240p']];

  function fmtRes(w, h) {
    if (w >= 3800 || h >= 2160) return '4K';
    if (w >= 1900 || h >= 1080) return '1080p';
    if (w >= 1260 || h >= 720) return '720p';
    if (w >= 620 || h >= 480) return '480p';
    if (h >= 360) return '360p';
    if (h >= 240) return '240p';
    return '144p';
  }

  function currentResolution() {
    var v = document.querySelector('video');
    if (v && v.videoWidth) return fmtRes(v.videoWidth, v.videoHeight);
    return null;
  }

  function toMbps(num, unit) {
    var n = parseFloat(num);
    return /kbps/i.test(unit) ? n / 1000 : n;
  }

  function fallbackRes(mbps) {
    for (var i = 0; i < FALLBACK.length; i++) {
      if (mbps >= FALLBACK[i][0]) return FALLBACK[i][1];
    }
    return '240p';
  }

  function inQualityRow(node) {
    var el = node.parentElement;
    for (var i = 0; el && i < 5; i++, el = el.parentElement) {
      var t = (el.textContent || '').trim();
      if (t.length < 40 && /^Quality\b/i.test(t)) return true;
    }
    return false;
  }

  function inQualitySelect(node) {
    var p = node.parentElement;
    if (!p || p.tagName !== 'OPTION') return false;
    var sel = p.closest('select');
    return !!sel && /quality/i.test((sel.className || '') + ' ' + (sel.id || '') + ' ' + (sel.name || ''));
  }

  function rewrite(node) {
    var s = node.nodeValue;
    if (!s || s.length > 40 || DONE.test(s)) return;
    var p = node.parentElement;
    if (!p || /^(SCRIPT|STYLE|TEXTAREA)$/.test(p.tagName)) return;

    var m = s.match(LADDER);
    if (m) {
      node.nodeValue = m[1] + ' (' + m[2] + ' ' + m[3] + ')';
      return;
    }

    m = s.match(BARE);
    if (m && (inQualitySelect(node) || inQualityRow(node))) {
      var res = currentResolution() || fallbackRes(toMbps(m[1], m[2]));
      node.nodeValue = res + ' (' + m[1] + ' ' + m[2] + ')';
    }
  }

  function scan() {
    if (!document.body) return;
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    var list = [];
    while (walker.nextNode()) list.push(walker.currentNode);
    for (var i = 0; i < list.length; i++) rewrite(list[i]);
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

  // Run this in the browser console if a label does not change
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
          row: p.parentElement ? p.parentElement.textContent.trim().slice(0, 60) : '',
          html: p.outerHTML.slice(0, 200)
        });
      }
    }
    var v = document.querySelector('video');
    console.log('[quality-labels] video:', v ? v.videoWidth + 'x' + v.videoHeight : 'none');
    console.table(out);
    return out;
  };

  function start() {
    new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true, characterData: true });
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
