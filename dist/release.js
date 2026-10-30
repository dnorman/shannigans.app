const releaseAPI = 'https://api.github.com/repos/dnorman/shannigans.app/releases/latest';
const tapURL = 'https://raw.githubusercontent.com/synestheticsystems/homebrew-tap/main/Casks/claude-shannigans.rb';
const installCommand = 'brew install --cask synestheticsystems/tap/claude-shannigans';

function installRelease(release, cask) {
  if (!release || typeof release !== 'object' || release.draft || release.prerelease || !/^v\d+\.\d+\.\d+$/.test(release.tag_name)) return false;
  const version = release.tag_name.slice(1);
  const filename = `Claude-Shannigans-${version}.dmg`;
  const url = `https://github.com/dnorman/shannigans.app/releases/download/v${version}/${filename}`;
  const asset = Array.isArray(release.assets) && release.assets.find(item => item && item.name === filename && item.browser_download_url === url && item.size > 0);
  if (!asset) return false;
  document.querySelectorAll('[data-download]').forEach(link => {
    link.href = url;
    link.hidden = false;
  });
  document.querySelector('[data-release-status]').textContent = `Version ${version} · macOS 13+ · Apple silicon + Intel`;
  document.querySelector('[data-release-pending]').hidden = true;
  if (cask.includes(`version "${version}"`) && /sha256 "[a-f0-9]{64}"/.test(cask)) {
    document.querySelector('[data-brew]').hidden = false;
  }
  return true;
}

async function loadRelease() {
  try {
    const response = await fetch(releaseAPI, { credentials: 'omit', signal: AbortSignal.timeout(6000) });
    if (!response.ok) return;
    const release = await response.json();
    let cask = '';
    try {
      const tap = await fetch(tapURL, { credentials: 'omit', signal: AbortSignal.timeout(6000) });
      if (tap.ok) cask = await tap.text();
    } catch { /* Direct downloads remain usable if the tap is unavailable. */ }
    installRelease(release, cask);
  } catch { /* The static release-page link remains available offline or on API errors. */ }
}

document.querySelector('[data-copy]')?.addEventListener('click', async () => {
  const status = document.querySelector('[data-copy-status]');
  try {
    await navigator.clipboard.writeText(installCommand);
    status.textContent = 'Copied.';
  } catch {
    status.textContent = 'Select the command to copy it.';
  }
});
loadRelease();
