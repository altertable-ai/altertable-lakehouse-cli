# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1](https://github.com/altertable-ai/altertable-lakehouse-cli/compare/altertable-lakehouse-cli-v0.2.0...altertable-lakehouse-cli-v0.2.1) (2026-04-23)


### Bug Fixes

* **debug:** actually implement --debug, add cURL verbosiness for further debug ([#16](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/16)) ([5fc8eae](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/5fc8eaec3d734f4a9e73857e0fb0da51509d8733))
* Fix append sending payload wrapped in single or batch payload ([#19](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/19)) ([3851dec](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/3851dec7593f94bb0d1fe9ee4f97977cb661f50b))

## [0.2.0](https://github.com/altertable-ai/altertable-lakehouse-cli/compare/altertable-lakehouse-cli-v0.1.0...altertable-lakehouse-cli-v0.2.0) (2026-03-08)


### Features

* bootstrap Lakehouse CLI (0.1.0) against specs v0.4.0 ([#1](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/1)) ([53200ec](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/53200ec7aa5e934752c38e9655a4d6b2e08359ee))


### Bug Fixes

* Gracefully handle HTTP errors (Fixes [#3](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/3)) ([#4](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/4)) ([6ea82fa](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/6ea82fa965feb87f4e08860fdb059d90a27d0d6e))
* use http_request in cmd_validate to handle errors gracefully ([#6](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/6)) ([7eacb1a](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/7eacb1a8ba3e1f9bdd49abb462cab379859b8d55))

## [0.1.0] - 2026-03-05

### Added
- Initial implementation of the Altertable Lakehouse CLI (`altertable`).
- Supported commands: `query`, `append`, `upload`, `get-query`, `cancel`, `validate`.
- Dependency on `curl` (required) and `jq` (optional but recommended).
- `specs` submodule pinned to `v0.4.0`.
