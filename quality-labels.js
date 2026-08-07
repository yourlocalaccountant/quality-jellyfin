(function () {
    'use strict';

    const LABEL_MAP = [
        { match: /^auto$/i, replace: 'Auto (Direct Play)' },
        { match: /20\s*mbps/i, replace: '1080p Blu-ray (20 Mbps)' },
        { match: /8\s*mbps/i, replace: '1080p High (8 Mbps)' },
        { match: /4\s*mbps/i, replace: '1080p Medium (4 Mbps)' },
        { match: /2\s*mbps/i, replace: '720p (2 Mbps)' },
        { match: /1\s*mbps/i, replace: '480p (1 Mbps)' }
    ];

    function relabelElement(element) {
        if (element.dataset.qualityRelabeled === '1') return;

        const text = element.textContent.trim();
        if (!text) return;

        for (const label of LABEL_MAP) {
            if (label.match.test(text)) {
                element.textContent = label.replace;
                element.dataset.qualityRelabeled = '1';

                if (label.replace.includes('Direct Play')) {
                    element.style.fontWeight = '700';
                    element.style.color = 'var(--theme-primary-color, #00a4dc)';
                }

                return;
            }
        }
    }

    function scan(root) {
        root.querySelectorAll(
            'li, button, span, div[role="menuitem"], div.listItem'
        ).forEach(element => {
            if (element.children.length === 0) {
                relabelElement(element);
            }
        });
    }

    const observer = new MutationObserver(mutations => {
        mutations.forEach(mutation => {
            mutation.addedNodes.forEach(node => {
                if (node.nodeType === 1) {
                    scan(node);
                }
            });
        });
    });

    observer.observe(document.body, {
        childList: true,
        subtree: true
    });

    scan(document);

    console.log('[Jellyfin Quality Labels] Active');
})();
