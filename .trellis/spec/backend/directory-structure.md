# Directory Structure

> How shell-based installer code is organized in this project.

---

## Overview

This repository is a Bash-first bootstrap project rather than a traditional service backend. The runtime entrypoint is `install.sh`, while `bootstrap.sh` is the remote bootstrap wrapper used by `curl + bootstrap` distribution.

The structure is intentionally shallow:

- shared helpers live under `lib/`
- feature-oriented installer modules live under `modules/`
- lightweight script-level verification lives under `tests/`
- Trellis task and spec context lives under `.trellis/`

---

## Directory Layout

```text
bootstrap.sh
install.sh
lib/
├── apt.sh
├── backup.sh
├── detect.sh
├── log.sh
└── ui.sh
modules/
├── ops_helpers.sh
├── security.sh
├── system_config.sh
└── system_tools.sh
tests/
├── fixtures/
│   ├── os-release-22.04
│   └── os-release-unsupported
└── run.sh
```

---

## Module Organization

- `install.sh` owns the top-level flow: preflight checks, menu orchestration, plan preview, action execution, and summary rendering.
- `lib/` contains reusable low-level helpers only. Keep these files free of product-specific menu logic.
- `modules/` contains user-facing feature groups. Each module should expose a uniform command surface through `<module>_show_menu`, `<module>_plan_actions`, and `<module>_run_action`.
- `tests/run.sh` should stay lightweight and executable with plain Bash. Use it for smoke tests around parsing, validation, and entrypoint behavior.

---

## Naming Conventions

- Shell files use lowercase snake-style names, grouped by responsibility.
- Shared helpers should be named by concern (`detect.sh`, `backup.sh`) rather than by caller.
- Action identifiers passed between modules and `install.sh` should remain stable, machine-friendly strings such as `security:ufw` or `system_config:swap`.

---

## Examples

- `install.sh` is the reference for orchestration responsibilities.
- `modules/security.sh` is the reference for interactive module design with additional prompts and risky-operation confirmation.
- `lib/detect.sh` is the reference for pure helper functions that can be sourced directly from tests.
