# Claude Shannigans website and public downloads

Static brochure, help, and privacy pages for https://shannigans.app.
The macOS app source remains in the separate private `dnorman/claude-desktop-switcher` repository.

## Layout

- `dist/`: deployable static HTML, CSS, JavaScript, and assets. No build step.
- `scripts/check-site.py`: dependency-free link and asset validation.
- `.github/workflows/site.yml`: validates and deploys `dist/` to GitHub Pages.
- GitHub Releases: signed, notarized universal DMGs, published by the app's CI.
- Homebrew cask: `synestheticsystems/homebrew-tap`, generated from the finished DMG's SHA-256.

Run `python3 scripts/check-site.py` and `node scripts/test-release.mjs` before deployment.
Pushes to `main` publish automatically after checks pass. Pull requests only run checks.
No credentials belong in this repository; Pages uses GitHub's scoped workflow identity.
Screenshots use disposable example accounts, never real user profiles.

The install area asks GitHub for the latest public release. It shows a download only
for the expected versioned DMG and shows the brew command only when the tap has the
matching version and a SHA-256. A failed request leaves an honest release-page link,
not a made-up download. No analytics or third-party scripts are loaded.

App release assets are immutable. Do not replace a DMG behind a published checksum.
Support issues are public; never include login cookies or unredacted profile data.

## Hosting

Daniel selected GitHub Pages on October 30, 2026. Configure the repository's Pages
source as GitHub Actions and its custom domain as `shannigans.app`. The apex uses
GitHub Pages' published A records. Keep HTTPS enforcement enabled after the
certificate is issued. `dist/CNAME` documents the domain; Actions-based Pages
uses the repository's Pages setting, not that file, as the authoritative binding.

An earlier preview used OpenAI Sites project
`appgprj_6ae4ee7e95bc8191a044d6edb4a6a01b`; it is not the production hosting path.
Do not recreate that project or reintroduce its repository credentials.
