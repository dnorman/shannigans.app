# Website publishing

This is the public Claude Shannigans brochure and release-asset repository.
Daniel explicitly selected GitHub Pages, deployed through `.github/workflows/site.yml`.
Preserve that hosting choice unless he asks to change it. No OpenAI Sites source
credential is needed. Keep the app source in its separate private repository.

Use `./dev.sh` for local development, following the Synesthetic Systems Sutra
contract in `~/.dev-runner/`. No ChatGPT hosting, preview tunnels, Sites helpers,
or OpenAI deployment services, including for local development.

Keep the copy direct and deadpan. Do not explain the joke or comment on the
website's own design. Avoid cute product-marketing asides and fake testimonials.
This is a noncommercial indie project, not a product launch or conversion funnel.
The name and illustration carry the humor. Keep the rest plain and useful.

Run `python3 scripts/check-site.py` and `node scripts/test-release.mjs` for edits.
For runner changes also run `python3 scripts/test-dev-runner.py`; its fixtures and
registry are isolated from the actual checkout's running preview.
Use example accounts only. Do not publish real profiles, cookies, or signing secrets.
Never replace a published DMG behind an existing Homebrew checksum.
