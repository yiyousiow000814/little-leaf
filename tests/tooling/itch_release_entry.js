'use strict';
const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const html = fs.readFileSync(process.argv[2], 'utf8');
const controller = html.match(/\/\* Little Leaf release entry\.[\s\S]*?<\/script>/)[0].replace('</script>', '');
function fixture(hostname) {
    const elements = new Map();
    for (const id of ['itch-release-entry', 'itch-release-local', 'canvas', 'status']) {
        elements.set(id, {hidden: id === 'itch-release-entry', handlers: {}, focuses: 0,
            focus() { this.focuses++; }, addEventListener(type, fn) { this.handlers[type] = fn; }});
    }
    const window = {location: {hostname}};
    const document = {getElementById(id) { assert(elements.has(id)); return elements.get(id); }};
    vm.runInNewContext(controller, {window, document});
    let boots = 0;
    window.LittleLeafItchReleaseEntryReady.then(() => { boots++; });
    return {window, elements, boots: () => boots};
}
(async () => {
    const itch = fixture('html-classic.itch.zone');
    await Promise.resolve();
    assert.equal(itch.boots(), 0);
    assert.equal(itch.elements.get('itch-release-entry').hidden, false);
    assert.equal(itch.elements.get('canvas').hidden, true);
    // Account is a native anchor: no handler disables the remaining local choice.
    assert.match(html, /href="https:\/\/little-leaf-41e5d\.firebaseapp\.com\/" target="_blank" rel="noopener noreferrer"/);
    itch.elements.get('itch-release-local').handlers.click();
    itch.elements.get('itch-release-local').handlers.click();
    await Promise.resolve();
    assert.equal(itch.boots(), 1);
    assert.equal(itch.elements.get('canvas').focuses, 1);
    for (const host of ['localhost', 'little-leaf-41e5d.firebaseapp.com', 'html-classic.itch.zone.evil.invalid']) {
        const other = fixture(host); await Promise.resolve();
        assert.equal(other.boots(), 1);
        assert.equal(other.elements.get('itch-release-entry').hidden, true);
        assert.deepEqual(other.elements.get('itch-release-local').handlers, {});
    }
    assert(!/indexedDB|localStorage|postMessage|iframe|firebase-auth|window\.open/.test(controller));
    console.log('Ordinary itch entry: explicit single local boot, native new-tab account link, normal-origin bypass passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
