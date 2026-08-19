# Repository Instructions

This repository ships two Dev Container Features: standalone `codex` and
Node.js-based `codex-node`.

## Core rules

- Never edit, reformat, or add comments to
  `devcontainer-features/src/codex/install-codex-standalone.sh`. It is vendored
  byte-for-byte from `https://chatgpt.com/codex/install.sh`. Keep feature-owned
  behavior in `install.sh`, `update.sh`, and `version-policy.sh`.
- Keep `entrypoint.sh`, `link-folders.sh`, and `sync-config.sh` synchronized
  between `codex` and `codex-node`. Their only intentional difference is
  `INSTALL_DIR`. Apply shared behavior changes and tests to both features.
- Preserve each script's shell dialect. Standalone wrappers and tests use POSIX
  `sh`; shared runtime helpers and `codex-node` scripts/tests use Bash.
- Keep standalone release policy centralized in `version-policy.sh`. Initial
  installs and updates must enforce the same minimum release (`0.146.1`).
- Preserve user data: folder links must not replace non-empty directories, and
  config sync must never let missing or empty content erase non-empty content.
  Conflicting non-empty configs must remain untouched instead of choosing a
  winner automatically.
- Add concise comments only where control flow, safety behavior, or test setup
  is not obvious. Never annotate the vendored installer.

## Keep changes consistent

- Keep feature manifests, implementation, tests, feature READMEs, and the root
  README aligned when options or behavior change.
- Feature versions come from each `devcontainer-feature.json`. Do not publish
  without an explicit request.

## Before handoff

- Run `sh -n` or `bash -n` as appropriate for changed scripts, validate changed
  JSON, and run `git diff --check`.
- Verify mirrored helpers still differ only by `INSTALL_DIR`.
- Run the affected Dev Container Feature tests. Entrypoint changes also need a
  test that actually invokes the entrypoint. Run the complete base-image matrix
  documented in `README.md` before publishing.
