/* Little Leaf release entry. Account play opens its own top-level origin. */
(function (root) {
    'use strict';
    root.LittleLeafItchReleaseEntryReady = new Promise(resolve => {
        // Ordinary browser tests and the official Firebase game keep their boot path.
        if (root.location.hostname !== 'html-classic.itch.zone') {
            resolve();
            return;
        }
        const entry = document.getElementById('itch-release-entry');
        const local = document.getElementById('itch-release-local');
        const canvas = document.getElementById('canvas');
        const status = document.getElementById('status');
        let selected = false;
        entry.hidden = false;
        canvas.hidden = true;
        status.hidden = true;
        local.addEventListener('click', () => {
            if (selected) return;
            selected = true;
            entry.hidden = true;
            canvas.hidden = false;
            status.hidden = false;
            canvas.focus();
            resolve();
        });
        // The account anchor needs no handler. Local play stays available if the
        // new tab is blocked or closed; no storage or account state crosses it.
    });
})(window);
