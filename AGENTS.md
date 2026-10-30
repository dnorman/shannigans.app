# Website publishing

This is the public Claude Shannigans brochure and release-asset repository.
Daniel explicitly selected GitHub Pages, deployed through `.github/workflows/site.yml`.
Preserve that hosting choice unless he asks to change it. No OpenAI Sites source
credential is needed. Keep the app source in its separate private repository.

Run `python3 scripts/check-site.py` and `node scripts/test-release.mjs` for edits.
Use example accounts only. Do not publish real profiles, cookies, or signing secrets.
Never replace a published DMG behind an existing Homebrew checksum.
