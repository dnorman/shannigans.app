import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../dist/release.js', import.meta.url), 'utf8');
const url = 'https://github.com/dnorman/shannigans.app/releases/download/v0.3.0/Claude-Shannigans-0.3.0.dmg';
const valid = { tag_name: 'v0.3.0', draft: false, prerelease: false, assets: [{ name: 'Claude-Shannigans-0.3.0.dmg', browser_download_url: url, size: 100 }] };
const cask = `cask "claude-shannigans" do\n  version "0.3.0"\n  sha256 "${'a'.repeat(64)}"\nend`;
function check(release, caskText = cask) {
  const nodes = Object.fromEntries(['download', 'release-status', 'release-pending', 'brew', 'copy', 'copy-status'].map(name => [name, { hidden: name !== 'release-pending', textContent: '', addEventListener() {} }]));
  const document = {
    querySelector: selector => nodes[selector.slice(6, -1)],
    querySelectorAll: selector => [nodes[selector.slice(6, -1)]]
  };
  const context = { document, fetch: async () => ({ ok: false }), AbortSignal, release, caskText };
  const result = runInNewContext(`${source}\ninstallRelease(release, caskText);`, context);
  return { result, nodes };
}
for (const release of [null, {}, { ...valid, draft: true }, { ...valid, prerelease: true }, { ...valid, tag_name: 'v0.3.0-rc1' }, { ...valid, assets: {} }, { ...valid, assets: [null] }, { ...valid, assets: [{ ...valid.assets[0], size: 0 }] }, { ...valid, assets: [{ ...valid.assets[0], browser_download_url: 'https://example.com/untrusted.dmg' }] }]) {
  const { result, nodes } = check(release);
  assert.equal(result, false);
  assert.equal(nodes.download.hidden, true);
  assert.equal(nodes.brew.hidden, true);
  assert.equal(nodes['release-pending'].hidden, false);
}
const ready = check(valid);
assert.equal(ready.result, true);
assert.equal(ready.nodes.download.href, url);
assert.equal(ready.nodes.download.hidden, false);
assert.equal(ready.nodes.brew.hidden, false);
assert.equal(ready.nodes['release-pending'].hidden, true);
for (const text of ['', cask.replace('0.3.0', '0.2.0'), cask.replace('a'.repeat(64), ':no_check')]) {
  const { nodes } = check(valid, text);
  assert.equal(nodes.download.hidden, false);
  assert.equal(nodes.brew.hidden, true);
}
console.log('Release UI checks passed: 13 release/cask combinations. No network requests made.');
