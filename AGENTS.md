# Repository guidance

## Project layout

- This repository contains vivo/iQOO temporary-root tooling, including Python build/version scripts, shell and PowerShell scripts, and an X200-specific toolkit.
- Keep changes scoped to the owning script or component. Preserve existing filenames, Chinese-language user-facing text, and platform-specific conventions.
- Treat `README.md`, `README_交接.md`, and component READMEs as the source of truth for documented workflows. Update relevant documentation when behavior changes.

## Safety and validation

- Treat exploit payloads, root scripts, kernel modules, and device command sequences as security-sensitive. Do not execute them or direct them at a device as part of routine development or testing.
- Prefer static checks, unit tests, and mocked subprocess/device interactions. Do not add tests that require a real device or trigger a root attempt.
- Keep changes limited to authorized research and defensive maintenance. Do not adapt the tooling for targeting third-party devices or for unattended, scaled exploitation.
- Build scripts may delete and recreate `_build_tmp/` or a configured apktool `build/` directory. Inspect the script and environment before invoking one; do not run builds unless explicitly needed for the task.

## Secrets and generated artifacts

- Never commit keystores, signing passwords, private keys, device data, or other credentials. Build configuration should continue to use environment variables.
- APKs, payload binaries, and temporary build products are not source files unless a task explicitly calls for managing them. Avoid adding generated outputs to commits.

## Editing and checks

- Make the smallest focused change and retain the surrounding language and formatting style.
- For Python changes, run an appropriate syntax check or focused test when available. For shell/PowerShell changes, use a static syntax or lint check when available.
- Before finishing, inspect the diff and ensure no secrets or unrelated generated files were included.