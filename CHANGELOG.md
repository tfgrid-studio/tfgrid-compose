# Changelog

All notable changes to tfgrid-compose will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.10.12] - 2025-10-17

### Changed
- **Centralized version management**: Version now stored in single `VERSION` file instead of hardcoded in multiple places

## [0.10.11] - 2025-10-17

### Fixed
- **Global STATE_DIR override**: Removed global `STATE_DIR=".tfgrid-compose"` from common.sh that was overriding dynamic state paths

## [0.10.10] - 2025-10-17

### Fixed
- **Pattern scripts using hardcoded paths**: Updated pattern scripts to use global state directory and exported STATE_BASE_DIR/APP_NAME for subshells

## [0.10.9] - 2025-10-17

### Fixed
- **STATE_BASE_DIR fallback**: Added fallback value for STATE_BASE_DIR in validation to ensure correct state path resolution

## [0.10.8] - 2025-10-17

### Fixed
- **State validation using wrong directory**: Fixed `validate_deployment_exists()` to properly construct state path from app name

## [0.10.7] - 2025-10-17

### Fixed
- **Registry apps not resolved in status/logs/ssh**: Commands now properly resolve registry app names to cached paths

## [0.10.6] - 2025-10-17

### Fixed
- **App source not copied to VM**: Now copies `src/` directory to VM for apps that need source files during setup

## [0.10.5] - 2025-10-17

### Fixed
- **Destroy prompting for input**: Added `-input=false` to destroy command to use existing state without prompts

## [0.10.4] - 2025-10-17

### Fixed
- **Destroy deployment bug**: Fixed duplicate log paths in destroy command

## [0.10.3] - 2025-10-17

### Fixed
- **Force flag in unhealthy state**: `--force` now properly triggers cleanup for unhealthy deployments

## [0.10.2] - 2025-10-17

### Fixed - Critical Production Bugs 🐛
- **Missing `primary_ip_type` extraction**: Now properly extracted from Terraform outputs to fix connectivity detection
- **Stale Terraform state handling**: Auto-detects and cleans corrupted state from deleted deployments
- **Error state cleanup**: Automatically cleans partial state on deployment failures (disable with `TFGRID_DEBUG=1`)
- **State detection bug**: Fixed `is_app_deployed()` to check `state.yaml` instead of non-existent `vm_ip` file
- **Health check improvement**: `is_deployment_healthy()` now validates Terraform state integrity
- **Log-based detection**: Validates against previous deployment errors in terraform logs

### Added - Deployment Resilience ✨
- **`--force` flag**: Force redeploy with `tfgrid-compose up <app> --force`
- **State validation**: `validate_terraform_state()`, `clean_stale_state()`, `is_deployment_healthy()`
- **Auto-recovery**: Detects stale state and cleans automatically on next deployment
- **Error trap**: Prevents corrupt state files from failed deployments
- **Multi-layer detection**: Checks state.yaml, terraform state, and error logs for stale deployments

### Changed
- Version bumped to v0.10.2
- Improved deployment error messages with recovery suggestions
- Enhanced state detection to support both old and new formats

## [0.10.1] - 2025-10-16

### Added - UX Improvements 🎯
- **`login` command**: Interactive credential setup with validation
- **`logout` command**: Securely remove stored credentials
- **`config` command**: Manage configuration (list, get, set, delete)
- **`docs` command**: Open documentation in browser (auto-detects xdg-open/open)
- **Credentials file**: Secure storage at `~/.config/tfgrid-compose/credentials.yaml`
- **Improved help**: Updated help text with setup commands and new user quick start
- **Enhanced .gitignore**: Added credential files for extra security
- **Mnemonic validation**: Support for both 12 and 24 word seed phrases

### Fixed
- **Login/Config commands**: Fixed `set -e` issue causing silent exit when no arguments provided
- **Error messages**: Enhanced error messages with helpful guidance and next steps
  - Login errors now show setup guide links
  - Config errors provide usage examples
  - Validation errors include installation instructions
  - All errors follow consistent format with clear solutions
- **CRITICAL: Makefile install bug**: Fixed wrapper script generation - the installed binary was only a shebang line and didn't execute the actual script, causing all commands to silently fail
- **Registry URL**: Fixed registry URL to point to correct repo (`app-registry` not `registry`)
- **Registry parser**: Updated YAML parser to handle nested `apps.official`/`apps.verified` format
- **`update` command**: Added missing `exit 0` to prevent script from continuing after update completes

## [0.10.0] - 2025-10-15

### Added - Registry CLI Integration 🚀
- **Registry Integration**: Deploy apps by name from the registry
  - `search` command - Browse and search available apps
  - `list` command - List locally deployed apps  
  - `switch` command - Switch between deployed apps
- **App Caching**: Automatic download and caching of registry apps
  - Apps cached in `~/.config/tfgrid-compose/apps/`
  - Smart caching with Git-based updates
- **Multi-App Deployment**: Deploy and manage multiple apps simultaneously
  - Per-app state management in `~/.config/tfgrid-compose/state/`
  - Active app context switching
  - No conflicts between deployments

### Changed
- **`up` command**: Now accepts app name or path
  - `tfgrid-compose up wordpress` - Deploy from registry
  - `tfgrid-compose up ./my-app` - Deploy from local path
- **Help system**: Reorganized into logical sections
  - Registry Commands (search, list, switch)
  - Deployment Commands (init, up, down, clean)
  - Management Commands (exec, logs, status, ssh, address)
- **Version**: Updated to 0.10.0

### Technical Details
- New module: `core/registry.sh` - Registry fetching and search
- New module: `core/app-cache.sh` - App download and caching
- New module: `core/deployment-state.sh` - Multi-app state management
- Registry cached with 1-hour TTL
- Backward compatible with existing deployments

---

## [0.9.0] - 2025-10-14

### Added
- **OpenTofu Priority Support**: Now checks for and prefers OpenTofu over Terraform
  - Validates OpenTofu first, falls back to Terraform
  - Exports `TF_CMD` environment variable for consistent tool usage
  - Updated all scripts to use dynamic tool detection
- **Versioning Policy**: Comprehensive versioning documentation in tfgrid-docs
- **Focused Roadmap**: Detailed enhancement roadmap for future development

### Changed
- **Version Standardization**: Unified version to 0.9.0 across all files
  - CLI: v0.9.0
  - Makefile: v0.9.0
  - README: v0.9.0
  - Documentation: v0.9.0
- **Install Messages**: Updated to recommend OpenTofu as primary option
- **Validation Messages**: Now shows which tool (OpenTofu/Terraform) is actually found

### Fixed
- **Version Inconsistency**: Resolved conflicting versions (was 2.0.0, 1.0.0, 0.1.0-mvp)
- **Tool Detection**: Fixed hardcoded `terraform` references in orchestrator destroy function
- **Common Checks**: Updated requirement checks to accept either OpenTofu or Terraform
- **Pattern Validation**: Now validates for either tool, not just Terraform

### Documentation
- Added comprehensive versioning policy to tfgrid-docs
- Documented OpenTofu priority rationale
- Created focused roadmap for quality improvements

---

## [Pre-0.9.0] - Historical

### Completed Features
- ✅ All 3 core patterns production-ready (single-vm, gateway, k3s)
- ✅ Full deployment orchestration (Terraform + WireGuard + Ansible)
- ✅ Context file support (`.tfgrid-compose.yaml`)
- ✅ Agent subcommand for AI agent management
- ✅ Automatic PATH setup during installation
- ✅ Input validation and error handling
- ✅ Idempotency protection
- ✅ Remote command execution (`exec`)
- ✅ Comprehensive documentation
- ✅ Auto-install with `make install`
- ✅ WireGuard + Mycelium dual networking
- ✅ State management
- ✅ Pattern-based architecture

### Patterns
- ✅ **Single-VM**: Development, databases, AI agents
- ✅ **Gateway**: Production web apps with public IPv4, SSL, load balancing
- ✅ **K3s**: Kubernetes clusters for cloud-native apps

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 0.10.0 | 2025-10-15 | Registry CLI integration, multi-app deployment, search/list/switch |
| 0.9.0 | 2025-10-14 | OpenTofu support, version standardization, focused roadmap |
| Pre-0.9.0 | 2025-10-09 | Core features complete, all patterns production-ready |

---

## Upgrade Guide

### From Pre-0.9.0 to 0.9.0

No breaking changes. This release is fully backward compatible.

**New Features:**
- OpenTofu is now automatically detected and preferred
- If you have both tools, OpenTofu will be used
- All existing Terraform deployments continue to work

**Action Required:**
- None! Upgrade is seamless.

**Recommended:**
- Consider installing OpenTofu for the open-source benefits:
  ```bash
  # Install OpenTofu (see https://opentofu.org/docs/intro/install/)
  ```

---

## Future Releases

### Planned for 0.11.0
- Enhanced monitoring capabilities
- Architecture documentation
- Troubleshooting guide
- Shell completion (bash/zsh/fish)

### Planned for 0.12.0
- CI/CD pipeline
- Expanded test coverage
- Pre-commit hooks
- Debug mode

### Planned for 1.0.0 (Q1 2026)
- API stability guarantee
- Comprehensive test coverage (>80%)
- Complete documentation
- Community feedback incorporated
- Production hardening complete

---

## Links

- [Versioning Policy](https://docs.tfgrid.studio/development/versioning-policy/)
- [GitHub Releases](https://github.com/tfgrid-studio/tfgrid-compose/releases)
- [Documentation](https://docs.tfgrid.studio)
- [Issue Tracker](https://github.com/tfgrid-studio/tfgrid-compose/issues)

---

**Note:** This changelog started with v0.9.0. Previous development history is summarized in the Pre-0.9.0 section.
