# Changelog

All notable changes to tfgrid-compose will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Planned for 0.10.0
- Multi-deployment management
- Deployment list/switch commands
- Enhanced monitoring capabilities
- Architecture documentation
- Troubleshooting guide

### Planned for 0.11.0
- CI/CD pipeline
- Shell completion (bash/zsh/fish)
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
