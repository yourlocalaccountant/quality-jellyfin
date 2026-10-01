#!/usr/bin/env bash
set -euo pipefail

DIRS=(/usr/share/jellyfin/web /jellyfin/jellyfin-web /usr/lib/jellyfin/bin/jellyfin-web /opt/jellyfin/web)
WEB=""
for d in "${DIRS[@]}"; do [ -f "$d/index.html" ] && WEB="$d" && break; done
[ -n "$WEB" ] || WEB="${JELLYFIN_WEB:-}"
[ -n "$WEB" ] && [ -f "$WEB/index.html" ] || { echo "jellyfin-web not found. Run with JELLYFIN_WEB=/path/to/web"; exit 1; }

cat > "$WEB/quality-labels.js" <<'EOF'
(function () {
  const LADDER = /^\s*(4K|\d{3,4}p) - (\d+(?:\.\d+)?) (Mbps|kbps)\s*$/i;
  const BARE = /^\s*(\d+(?:\.\d+)?) (Mbps|kbps)\s*$/i;

  function resolution() {
    const v = document.querySelector('video');
    if (!v || !v.videoWidth) return null;
    const w = v.videoWidth, h = v.videoHeight;
    if (w >= 3800 || h >= 2160) return '4K';
    if (w >= 1900 || h >= 1080) return '1080p';
    if (w >= 1260 || h >= 720) return '720p';
    if (w >= 620 || h >= 480) return '480p';
    if (h >= 360) return '360p';
    if (h >= 240) return '240p';
    return '144p';
  }

  function inQualityRow(node) {
    let el = node.parentElement;
    for (let i = 0; el && i < 4; i++, el = el.parentElement) {
      const t = el.textContent.trim();
      if (t.length < 40 && /^Quality\b/i.test(t)) return true;
    }
    return false;
  }

  function fix() {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const n of nodes) {
      const s = n.nodeValue;
      if (s.length > 40) continue;
      let m = s.match(LADDER);
      if (m) { n.nodeValue = `${m[1]} (${m[2]} ${m[3]})`; continue; }
      m = s.match(BARE);
      if (m && inQualityRow(n)) {
        const r = resolution();
        if (r) n.nodeValue = `${r} (${m[1]} ${m[2]})`;
      }
    }
  }

  let queued = false;
  new MutationObserver(() => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; fix(); });
  }).observe(document.body, { childList: true, subtree: true, characterData: true });
  fix();
})();
EOF

sed -i -E 's#<script src="quality-labels\.js[^"]*"></script>##g' "$WEB/index.html"
sed -i "s#</body>#<script src=\"quality-labels.js?v=$(date +%s)\"></script></body>#" "$WEB/index.html"

echo "Installed. Hard refresh your browser (Ctrl+Shift+R)."
