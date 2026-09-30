#!/usr/bin/env bash
set -euo pipefail

DIRS=(/usr/share/jellyfin/web /jellyfin/jellyfin-web /usr/lib/jellyfin/bin/jellyfin-web /opt/jellyfin/web)
WEB=""
for d in "${DIRS[@]}"; do [ -f "$d/index.html" ] && WEB="$d" && break; done
[ -n "$WEB" ] || WEB="${JELLYFIN_WEB:-}"
[ -n "$WEB" ] && [ -f "$WEB/index.html" ] || { echo "jellyfin-web not found. Run with JELLYFIN_WEB=/path/to/web"; exit 1; }

cat > "$WEB/quality-labels.js" <<'EOF'
(function () {
  const MAP = [[40,'4K'],[15,'1440p'],[8,'1080p'],[4,'720p'],[1.5,'480p'],[0.5,'360p'],[0,'240p']];
  const EXACT = /^\s*(\d+(?:\.\d+)?)\s*(Mbps|Kbps)\s*$/i;

  function inQualityRow(node) {
    let el = node.parentElement;
    for (let i = 0; el && i < 4; i++, el = el.parentElement) {
      if (/^\s*Quality\b/i.test(el.textContent)) return true;
    }
    return false;
  }

  function fix() {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const hits = [];
    while (walker.nextNode()) {
      const n = walker.currentNode;
      if (EXACT.test(n.nodeValue)) hits.push(n);
    }
    hits.forEach(n => {
      const isOption = n.parentElement && n.parentElement.tagName === 'OPTION';
      if (!isOption && !inQualityRow(n)) return;
      const m = n.nodeValue.match(EXACT);
      let mbps = parseFloat(m[1]);
      if (/kbps/i.test(m[2])) mbps /= 1000;
      n.nodeValue = `${MAP.find(([min]) => mbps >= min)[1]} (${m[1]} ${m[2]})`;
    });
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

if ! grep -q 'quality-labels.js' "$WEB/index.html"; then
  sed -i 's#</body>#<script src="quality-labels.js"></script></body>#' "$WEB/index.html"
fi

echo "Installed. Hard refresh your browser (Ctrl+Shift+R)."
