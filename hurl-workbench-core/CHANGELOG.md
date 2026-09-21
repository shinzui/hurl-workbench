# Changelog

All notable changes to hurl-workbench are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0.0] - Unreleased

### Added

- Versioned Dhall workspaces with compatible record completion, upward discovery, accumulated
  semantic validation, and category-specific names.
- Byte-preserving fragment composition, source-mapped Hurlfmt validation, and inspectable rendering.
- Secure Hurl 8.x execution with separate plain/secret files, filtered ambient configuration,
  exact child statuses, and typed Hurl option passthrough.
- Read-only/mutating recipes, bounded matrices, isolated client artifacts, managed services, suite
  preflight, and isolated JUnit, HTML, JSON, and TAP reports.
- Revision-aware version output and generated Bash, Zsh, and Fish completions.
- Local vendor-exploration and managed integration-service examples.

### Security

- Secrets never enter child argv; temporary inputs and output artifacts use owner-only permissions.
- Managed services are cleaned up as POSIX process groups, including on timeout and interruption.

### Compatibility

- Hurl and Hurlfmt 8.0 or newer are required. Later major versions are reported as untested by
  `doctor` rather than rejected automatically.
