# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-05

### Added
- Initial implementation of the Altertable Lakehouse CLI (`altertable`).
- Supported commands: `query`, `append`, `upload`, `get-query`, `cancel`, `validate`.
- Dependency on `curl` (required) and `jq` (optional but recommended).
- `specs` submodule pinned to `v0.4.0`.
