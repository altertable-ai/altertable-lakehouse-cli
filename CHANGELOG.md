# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0](https://github.com/altertable-ai/altertable-lakehouse-cli/compare/altertable-lakehouse-cli-v0.4.1...altertable-lakehouse-cli-v0.5.0) (2026-06-30)


### Features

* add configure command ([#30](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/30)) ([7757cef](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/7757cefe5c90e9a78f3d16222c91256f6a2ded4c))
* cli commands for whoami and catalogs management ([#34](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/34)) ([0539b61](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/0539b613bb3dc153c7ef3bff7f69d2d9754bffe0))

## [0.4.1](https://github.com/altertable-ai/altertable-lakehouse-cli/compare/altertable-lakehouse-cli-v0.4.0...altertable-lakehouse-cli-v0.4.1) (2026-06-18)


### Bug Fixes

* **upsert:** replace `--data-binary` by `--upload-file` to benefit from actual streaming ([#31](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/31)) ([18a73b1](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/18a73b178c0faad334c02c75070925ffe4171252))
* use lakehouse username and password ([#27](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/27)) ([17ff015](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/17ff015c56cfe57e3c724ef457a98583cbc69403))

## [0.4.0](https://github.com/altertable-ai/altertable-lakehouse-cli/compare/altertable-lakehouse-cli-v0.3.0...altertable-lakehouse-cli-v0.4.0) (2026-05-28)


### Features

* upload CLI to release ([#25](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/25)) ([f3d18d3](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/f3d18d3280cd672af009ad7d19a33c2f2f8e0fa5))

## [0.3.0](https://github.com/altertable-ai/altertable-lakehouse-cli/compare/altertable-lakehouse-cli-v0.2.1...altertable-lakehouse-cli-v0.3.0) (2026-05-07)


### Features

* **help:** improve help outputs ([#22](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/22)) ([4b7f362](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/4b7f362d205dfb88f95707356d9b1584a0c17dc8))

## [0.2.1](https://github.com/altertable-ai/altertable-lakehouse-cli/compare/altertable-lakehouse-cli-v0.2.0...altertable-lakehouse-cli-v0.2.1) (2026-05-07)


### Bug Fixes

* **debug:** actually implement --debug, add cURL verbosiness for further debug ([#16](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/16)) ([5fc8eae](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/5fc8eaec3d734f4a9e73857e0fb0da51509d8733))
* Fix append sending payload wrapped in single or batch payload ([#19](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/19)) ([3851dec](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/3851dec7593f94bb0d1fe9ee4f97977cb661f50b))
* **version:** ensure release-please updates the version ([#20](https://github.com/altertable-ai/altertable-lakehouse-cli/issues/20)) ([26a711b](https://github.com/altertable-ai/altertable-lakehouse-cli/commit/26a711b7e6cb38a99dea63f76896b95d4a7696b8))

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
