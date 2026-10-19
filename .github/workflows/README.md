# GitHub Workflows and Release Management

[![Build and Release](https://github.com/CIDEON-EC/Autodesk-Deployments/actions/workflows/build-and-release.yml/badge.svg)](https://github.com/CIDEON-EC/Autodesk-Deployments/actions/workflows/build-and-release.yml)

The `Build and Release` workflow (`build-and-release.yml`) tests every change and publishes a release when the `VERSION` file in the repository root changes. Releases are no longer created by tagging manually.

## Overview

| Trigger | `test` job | `version` job (release) |
|---------|-----------|-------------------------|
| Push to `main` | Runs | Runs; releases if the tag `v<VERSION>` does not exist yet |
| Push to `release/**` | Runs | Runs; pre-release versions only |
| Pull request against `main` | Runs | Does not run |

The `test` job runs PSScriptAnalyzer and Pester. A release is only created if it passes.

## Create a release

1. Set `VERSION` to the new version (SemVer, without `v`), e.g. `2.2.0` or `2.2.0-beta.1`.
2. In `CHANGELOG.md`, rename the `[Unreleased]` section to `[2.2.0] - <date>`.
3. Commit and push to `main`.

On a push (not on pull requests), the `version` job runs these steps:

1. **Read the version:** validates `VERSION` as SemVer. If the tag `v<VERSION>` already exists, nothing happens (e.g. after a pure correction of the file).
2. **Write the version:** sets the version in the `ModuleVersion:` line of `Install-ADSK.ps1` and `CIDEON.AutodeskDeployment.psm1`.
3. **Sign the module:** signs `CIDEON.AutodeskDeployment.psm1` with the GitHub secrets and verifies the signature.
4. **Build the package:** creates `Autodesk-Deployment-<VERSION>.zip` with `Install-ADSK.ps1`, `Copy-Local.ps1`, `New-DeploymentImage.ps1`, `New-DeploymentImage.cmd`, the module, the certificate, `readme.md`, `CHANGELOG.md` and `samples/`.
5. **Create the release:** creates the tag `v<VERSION>` on the pushed commit. The release notes come from the matching `CHANGELOG.md` section (`[<VERSION>]`, otherwise `[Unreleased]`).

A version with a suffix (`-alpha`, `-beta.1`, `-rc1`) is marked as a pre-release automatically.

## Test a pre-release without merging to main

A push to a `release/**` branch (e.g. `release/3.0.0-beta`) starts the same workflow. If the tag for `VERSION` does not exist yet, it creates the release.

- Only pre-release versions are allowed there (e.g. `3.0.0-beta.1`). A stable version is rejected.
- The tag is created on the branch commit.
- `workflow_dispatch` is deliberately not used: GitHub requires the workflow to exist on the default branch for it.

## Release assets

- `Autodesk-Deployment-<VERSION>.zip` (complete package)
- `Install-ADSK.ps1`, `New-DeploymentImage.ps1`, `New-DeploymentImage.cmd`
- `CIDEON.AutodeskDeployment.psm1` (signed), `CIDEON-CodeSigning.cer`

## Troubleshooting

- **No release despite a push:** the push must target `main` or `release/**`, and the tag `v<VERSION>` must not exist yet.
- **The run is green but there is no release:** the tag `v<VERSION>` already exists. Increase `VERSION`.
- **A release failed:** the tag is only created in the last step. Re-run the failed run in GitHub Actions; nothing needs to be deleted.
- **A tag was created by mistake:** run `git push origin --delete v<VERSION>` and delete the GitHub release.
