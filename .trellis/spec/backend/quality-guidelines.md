# Quality Guidelines

> Code quality standards for the Bash installer in this project.

---

## Overview

This project values small, surgical shell scripts over abstraction-heavy frameworks. The main risks are destructive system changes, silent command failures, and brittle string parsing, so quality checks should focus on safety and repeatability first.

---

## Forbidden Patterns

- Do not edit `/etc` files without creating a backup first.
- Do not hide risky operations such as SSH changes, firewall enablement, or swap rewrites behind implicit defaults.
- Do not add large generic helper layers for one-off behavior. Prefer focused functions with clear callers.
- Do not assume packages or commands exist before checking (`apt-get`, `whiptail`, `systemctl`, `timedatectl`, etc.).
- Do not mix user-facing status text with machine-readable function output when a caller parses stdout.
- Do not launch `whiptail` from a non-interactive stdin without rebinding to `/dev/tty` or failing early with a clear message.

---

## Required Patterns

- Use `set -euo pipefail` in executable scripts.
- Keep reusable helpers in `lib/` and feature group logic in `modules/`.
- Perform state detection before installation or configuration so repeated runs can skip completed work.
- Keep comments brief and only where parsing or safety logic is non-obvious.
- Emit user-facing progress through logging helpers and reserve structured stdout for command results.
- When bootstrap entrypoints may run through pipes (`curl | bash`), restore interactive stdin before the first `whiptail` prompt.

---

## Testing Requirements

- Every new behavior should have at least one Bash-level automated check when it is practical to test without mutating the host system.
- Run `bash tests/run.sh` for lightweight behavior checks.
- Run `bash -n` against all project shell scripts before claiming completion.
- For risky configuration logic that cannot be fully integration-tested locally, require validation of the parsing and preflight helpers that gate the action.

---

## Code Review Checklist

- Does the change preserve the `bootstrap.sh` / `install.sh` / `lib/` / `modules/` responsibility split?
- Are backups created before any `/etc` mutation?
- Are unsupported environments rejected early with clear messages?
- Can repeated execution skip already-satisfied package installs or configuration states?
- Do tests and syntax checks cover the newly added parsing or validation logic?
