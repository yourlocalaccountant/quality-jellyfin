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
  const RE = /^\s*(\d+(?:\.\d+)?)\s*(Mbps|Kbps)\b(.*)$/i;
  function label(text) {
    const m = text.match(RE);
    if (!m) return null;
    let mbps = parseFloat(m[1]);
    if (/kbps/i.test(m[2])) mbps /= 1000;
    return `${MAP.find(([min]) => mbps >= min)[1]} (${m[1]} ${m[2]})`;
  }
  function fix(root) {
    root.querySelectorAll('select.selectVideoQuality option').forEach(o => {
      const t = label(o.textContent); if (t) o.textContent = t;
    });
    root.querySelectorAll('.actionSheetContent .listItemBodyText, .actionSheetContent .actionSheetItemText').forEach(el => {
      const t = label(el.textContent); if (t) el.textContent = t;
    });
  }
  new MutationObserver(muts => {
    for (const m of muts) for (const n of m.addedNodes) if (n.nodeType === 1) fix(n);
  }).observe(document.body, { childList: true, subtree: true });
})();
EOF

if ! grep -q 'quality-labels.js' "$WEB/index.html"; then
  sed -i 's#</body>#<script src="quality-labels.js"></script></body>#' "$WEB/index.html"
fi

echo "Installed. Hard refresh your browser (Ctrl+Shift+R)."
