# Changelog

All notable changes to this project will be documented in this file. The
project uses semantic versioning after the initial public preview.

## [Unreleased]

## [0.1.0] - 2026-08-31

### Added

- Provisioning of private, organization-owned student repositories.
- Complete base-repository synchronization through internal pull requests.
- Teacher-team `Admin` and individual student `Write` permissions.
- Protection of `main` against force-pushes and deletion when supported by the
  organization's GitHub plan.
- Explicit student names, GitHub usernames, and stable repository suffixes.
- Safe repeated execution without a separate synchronization state file.
- Clear conflict reporting and student-or-teacher conflict resolution.
- English and Czech student workflow guides.
- Offline PowerShell tests and Windows CI coverage.

### Documentation

- Explained year-long, assignment-scoped, and hybrid repository models.
- Documented separate configuration directories for multiple synchronization
  scopes.
- Made student instructions independent of a specific Git client.

### Fixed

- Run Windows PowerShell 5.1 and PowerShell 7 checks as explicit GitHub Actions
  jobs so the workflow does not depend on a dynamic `shell` expression.
- Clear the expected native-command failure code after successful offline tests
  so GitHub Actions reports the passing suite correctly.
- Update `actions/checkout` to the Node.js 24-based `v7` release.

[Unreleased]: https://github.com/slovak-edhouse/github-course-sync/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/slovak-edhouse/github-course-sync/releases/tag/v0.1.0
