# Contributing

Thank you for helping improve GitHub Course Sync. The project favors a small,
auditable implementation and predictable teacher and student workflows.

## Before opening an issue

- Read the README and search existing issues.
- Reproduce the problem with a dummy organization repository and fictional
  account names whenever possible.
- Run the command again with `-Verbose` only if more detail is needed.
- Remove student data, private repository URLs, organization secrets, tokens,
  and authentication output before sharing diagnostics.

For a bug report, include:

- the script and command used;
- Windows and PowerShell versions;
- `git --version` and `gh --version`;
- the expected and actual behavior;
- sanitized output;
- whether the GitHub account is an organization owner or has delegated
  administrative access.

Report security vulnerabilities privately according to [SECURITY.md](SECURITY.md).

## Development setup

The scripts support Windows PowerShell 5.1 and PowerShell 7. Install Git and
GitHub CLI for manual integration testing. The offline test suite has no
external module dependencies:

```powershell
.\tests\Test-Common.ps1
```

Run it in both shells:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Common.ps1
pwsh.exe -NoProfile -File .\tests\Test-Common.ps1
```

Automated tests must not call live GitHub APIs, create repositories, change
permissions, or require secrets. Use test doubles or validate pure functions.
Live behavior belongs in the documented manual acceptance scenario.

## Pull requests

1. Keep the change focused.
2. Preserve Windows PowerShell 5.1 compatibility unless a major release
   explicitly changes the requirement.
3. Add or update offline tests.
4. Update user documentation and `CHANGELOG.md` when behavior changes.
5. Run both supported PowerShell test commands.
6. Do not commit real `classroom.psd1`, `students.csv`, `_local-test` content,
   tokens, or student information.

Avoid adding production dependencies unless they materially simplify the tool
and are available on ordinary school-managed Windows computers.

## Design principles

- Organization-owned repositories remain under school control.
- Existing student commits are preserved.
- Synchronization never uses force-push as a shortcut.
- Expected conflicts are clear manual actions, not noisy failures.
- Re-running setup and synchronization is safe.
- Configuration stays explicit and understandable to a teacher.
- Student instructions describe standard Git operations without requiring a
  specific desktop client.
