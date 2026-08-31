# GitHub Course Sync

[![Tests](https://github.com/slovak-edhouse/github-course-sync/actions/workflows/test.yml/badge.svg)](https://github.com/slovak-edhouse/github-course-sync/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

GitHub Course Sync is a small PowerShell toolkit for teachers who want a
GitHub Classroom-style workflow based on ordinary organization-owned private
repositories.

Two commands manage a repository set:

1. `Setup-Classroom.ps1` creates and secures one private repository per student
   for the configured scope.
2. `Sync-Classroom.ps1` distributes the complete current contents and Git
   history of a private base repository to every corresponding student
   repository.

Students use ordinary **Pull**, **Commit**, and **Push**. They do not create
forks, configure an `upstream` remote, or open pull requests for normal class
work.

Students may use any Git client that supports the standard clone, fetch, pull,
commit, and push operations. Command-line Git, IDE integrations, and graphical
clients are all compatible. The scripts work with repositories on GitHub and
do not depend on the student's local client.

> [!IMPORTANT]
> This is an independent community project. It is not affiliated with or
> supported by GitHub, Microsoft, or the author's school. Test it with a dummy
> repository and test account before using it with real students.

## Repository model

One configuration represents one **synchronization scope**: a base repository
and the student repositories derived from it. The scope can be a complete
course, a school year, a unit, or one assignment.

```text
school organization
|
+-- <scope>-base               private, teacher-only source
|
+-- <scope>-novak-jan          private, Jan has Write
+-- <scope>-svobodova          private, Petra has Write
+-- ...                        teacher team has Admin on every repository
```

The organization owns every student repository. Students cannot transfer or
delete the repository, change its visibility, or revoke the teacher team's
access. Organization owners retain administrative control.

The base repository must contain only student-safe material: assignments,
starter code, inputs, and resources. Never put teacher solutions, grading
notes, credentials, student data, or private preparation material in it.

## Choose a repository scope

The scripts do not prescribe how long a student repository should live. They
always copy and later synchronize the **complete base repository**, so the
contents of that base define the scope.

| Model | Example | Advantages | Tradeoffs |
| --- | --- | --- | --- |
| Course or school year | `programming-2026-base` -> `programming-2026-novak-jan` | One clone and invitation per student; continuous history; simple student routine | Repositories grow and later releases can conflict with earlier student changes |
| One assignment or unit | `arrays-base` -> `arrays-novak-jan` | Isolated history and grading; fewer cross-assignment conflicts | More repositories, invitations, prefixes, and configurations |
| Hybrid | one scope per term or topic | Balances repository count and isolation | The teacher must define and communicate the boundaries |

For the course model, keep adding student-safe material to the same base and
run synchronization whenever material is released. For the assignment model,
create a new private base, unique repository prefix, and configuration for each
assignment. Run setup to create that assignment's student repositories; run
synchronization later only when correcting or extending that assignment.

Do not reuse a repository prefix for a different scope in the same
organization. Repository names are the mechanism that keeps independently
managed sets separate.

## How synchronization works

The base repository and all student repositories share the same initial Git
history. For each release, the synchronization script:

1. reads the current `main` commit from the base repository;
2. pushes that exact commit to a `classroom-sync/<commit>` branch in each
   student repository;
3. creates an internal pull request from that branch to the student's `main`;
4. merges the pull request when GitHub reports no conflict.

This is a Git merge, not a file mirror or destructive overwrite. Student
commits remain in the repository. Every committed base-repository change,
including additions, edits, renames, and deletions, is distributed. The base
commit SHA identifies a release, so running the same synchronization again is
safe and does not need a separate state file.

In a long-lived repository, reduce conflicts by placing each new assignment in
a new directory and avoiding files students may already have changed. In an
assignment-scoped repository, avoid changing starter files after students have
begun work unless the correction is necessary. If GitHub cannot merge a
release automatically, the pull request remains open for the student or
teacher to resolve. The script will not start a newer synchronization for that
student while an older synchronization pull request remains unresolved.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7
- Git
- [GitHub CLI](https://cli.github.com/)
- for students, any Git client permitted and supported by the school
- a GitHub organization
- an account allowed to create private organization repositories, manage
  repository access, and configure repository settings
- one existing teacher team with a stable slug, for example
  `programming-teachers`

Some branch-protection capabilities for private repositories depend on the
organization's GitHub plan. The scripts report a warning when GitHub refuses a
protection setting.

## Package contents

- `classroom.example.psd1` - synchronization-scope configuration template
- `students.example.csv` - student-name and repository-name template
- `scripts/Setup-Classroom.ps1` - initial provisioning and later additions
- `scripts/Sync-Classroom.ps1` - complete base-repository distribution
- `scripts/Common.ps1` - shared implementation
- `docs/STUDENT_WORKFLOW.en.md` - English student instructions
- `docs/STUDENT_WORKFLOW.cs.md` - Czech student instructions
- `docs/ACCEPTANCE_TEST.md` - safe manual acceptance scenario
- `tests/Test-Common.ps1` - offline automated checks

## 1. Secure the GitHub organization

Review the organization settings before managing a class. The intended policy
is:

- default member repository permission: `None`;
- members cannot create, delete, or transfer repositories unless needed;
- private repository forking disabled;
- outside-collaborator invitations restricted to organization owners;
- two-factor authentication required when school policy permits it;
- at least two trusted organization owners for recovery;
- one teacher team, for example `programming-teachers`.

The scripts additionally require managed repositories to be private, disable
forking, grant the teacher team `Admin`, grant each student `Write` only on
their repository, and protect `main` against force-pushes and deletion.

Do not store organization tokens, personal access tokens, or deployment
secrets in this repository or in student repositories. Authentication remains
in GitHub CLI's credential store on the teacher computer.

## 2. Install the tools

On Windows, Git and GitHub CLI can be installed with:

```powershell
winget install --id Git.Git
winget install --id GitHub.cli
```

Close and reopen PowerShell after installation, then authenticate:

```powershell
git --version
gh --version
gh auth login
gh auth setup-git
gh auth status
```

If Windows PowerShell blocks local scripts, use PowerShell 7 or follow the
execution policy approved by your organization. Do not bypass a centrally
managed security policy.

## 3. Install GitHub Course Sync

Clone the repository:

```powershell
git clone https://github.com/slovak-edhouse/github-course-sync.git
Set-Location github-course-sync
```

Alternatively, download a tagged release archive from the repository's
**Releases** page. Prefer a tagged release for real student repositories rather
than an unreviewed development commit.

## 4. Choose the scope and create its base repository

First decide whether this configuration represents a course, school year,
unit, or assignment. Then create one private base repository in the school
organization. For example:

```text
school-org/programming-2026-base
school-org/arrays-assignment-base
```

Use `main` as its default branch and make at least one initial commit. Give only
the teacher team access. Commit the complete student-visible repository as it
should appear when that course, unit, or assignment begins.

## 5. Configure the synchronization scope

For one active scope, the simplest arrangement is to copy the examples into the
repository root:

```powershell
Copy-Item classroom.example.psd1 classroom.psd1
Copy-Item students.example.csv students.csv
```

The two real files are ignored by Git. Keep them private and back them up using
your school's approved storage.

To manage several scopes, keep each configuration and its adjacent student CSV
in a separate ignored directory:

```text
_local/
+-- programming-2026/
|   +-- classroom.psd1
|   +-- students.csv
+-- arrays-assignment/
    +-- classroom.psd1
    +-- students.csv
```

Pass the chosen configuration explicitly when running a script:

```powershell
.\scripts\Setup-Classroom.ps1 `
    -ConfigPath .\_local\arrays-assignment\classroom.psd1 `
    -WhatIf
```

`students.csv` is always read from the same directory as its
`classroom.psd1`. This allows the same tool clone to manage multiple independent
repository sets. Keep every real configuration directory private.

Edit `classroom.psd1`:

```powershell
@{
    Organization     = 'school-org'
    BaseRepository   = 'school-org/programming-2026-base'
    RepositoryPrefix = 'programming-2026-'
    TeacherTeamSlug  = 'programming-teachers'
}
```

For an assignment-scoped set, use a unique base and prefix instead:

```powershell
@{
    Organization     = 'school-org'
    BaseRepository   = 'school-org/arrays-assignment-base'
    RepositoryPrefix = 'arrays-assignment-'
    TeacherTeamSlug  = 'programming-teachers'
}
```

Edit `students.csv`. Keep the columns in exactly this order and save the file
as UTF-8:

```csv
StudentName,GitHubUsername,RepositorySuffix
"Jan Novak",xXdragon42Xx,novak-jan
"Petra Svobodova",coder-girl-987,svobodova-petra
```

The fields have separate purposes:

- `StudentName` is the readable name in teacher reports. It may contain spaces
  and non-ASCII characters.
- `GitHubUsername` is the student's personal GitHub username. It is used to
  verify the account and grant `Write` access.
- `RepositorySuffix` is the stable, teacher-selected part of the repository
  name.

The final repository name is `RepositoryPrefix` plus `RepositorySuffix`. For
example, the assignment prefix above produces
`school-org/arrays-assignment-novak-jan`. The suffix is used exactly as entered;
it is not generated from the student name. Use only lowercase letters, digits,
`.`, `_`, and `-`. GitHub usernames and repository suffixes must each be
unique within a configuration.

## 6. Create student repositories

First preview the operation:

```powershell
.\scripts\Setup-Classroom.ps1 -WhatIf
```

The dry run creates and removes a temporary local bare clone to validate the
base history. `-WhatIf` prevents GitHub repository, permission, and settings
changes; it does not skip this temporary read-only workspace.

Then provision the repositories:

```powershell
.\scripts\Setup-Classroom.ps1
```

For every CSV row, the script:

- secures the base repository and grants the teacher team `Admin`;
- verifies that the GitHub account exists;
- creates a private organization-owned repository when it is missing;
- copies the base repository's `main` history into the new repository;
- grants the teacher team `Admin` and the individual student `Write`;
- verifies that forking is disabled by either the organization or repository
  policy, and protects `main` from force-pushes and deletion.

Re-running setup is safe: existing repositories are validated instead of
recreated. A student who is not already an organization member may need to
accept an invitation before cloning the repository.

To add selected students later, add their CSV rows and run:

```powershell
.\scripts\Setup-Classroom.ps1 -GitHubUsername new-student
```

## 7. Release or update the selected scope

Commit and push the complete student-safe state to the base repository's
`main`, then preview and run synchronization:

```powershell
.\scripts\Sync-Classroom.ps1 -WhatIf
.\scripts\Sync-Classroom.ps1
```

There is no assignment path, assignment ID, release title, or state file. The
unit of distribution is always the entire configured base repository, and the
base commit SHA is the release identity. A long-lived base may therefore
contain many assignments, while an assignment-scoped base may contain only one.

The final summary distinguishes synchronized, already current, needs
attention, and failed repositories. A merge conflict is displayed in yellow
as `CONFLICT` with the pull-request URL. It is a manual action, not a
PowerShell failure. Repository, permission, and history problems are displayed
in red. Use `-Verbose` for detailed GitHub CLI diagnostics.

A conflict affects only one student's repository. The student or teacher can
resolve a simple conflict on GitHub and merge the pull request. Complex
conflicts should be resolved locally with teacher guidance. A resolved
synchronization branch is accepted as long as it still contains the expected
base commit.

## Student routine

Give students the appropriate guide:

- [English student workflow](docs/STUDENT_WORKFLOW.en.md)
- [Czech student workflow](docs/STUDENT_WORKFLOW.cs.md)

The guides intentionally describe Git operations rather than product-specific
buttons. A teacher may demonstrate those operations in the Git client used at
their school.

Their normal cycle is:

```text
Fetch/Pull -> work -> Commit -> Push
```

Students do not create a fork or configure repository permissions. Each
organization-owned repository is their submission history for the course,
unit, or assignment represented by that repository.

## Recovery and maintenance

- **Wrong username:** correct `students.csv` and rerun setup. Remove an
  accidentally invited account only after verifying the exact repository.
- **Wrong suffix:** correct it before repository creation. After creation,
  deliberately rename the repository in GitHub and update the student's
  `origin` URL.
- **Pending invitation:** ask the student to accept it, then rerun setup.
- **Unrelated Git history:** inspect the repository manually. The scripts stop
  instead of force-pushing over it.
- **Synchronization conflict:** resolve and merge the printed pull request
  before releasing a newer base commit.
- **Student leaves:** remove the student's access but retain the repository
  according to school policy.
- **Teacher unavailable:** another organization owner can restore teacher-team
  access.

Before creating a real course, unit, or assignment repository set, choose a
unique base and prefix, review the organization policy, and run the
[acceptance scenario](docs/ACCEPTANCE_TEST.md). Retain or archive completed
student repositories according to school policy.

## Security and privacy

This tool manages private repositories with elevated organization permissions.
Read [SECURITY.md](SECURITY.md) before using it. Never publish a real
`classroom.psd1`, `students.csv`, diagnostic log containing student data, or
GitHub authentication output.

## Development

The offline checks require no external PowerShell modules and never call
GitHub:

```powershell
.\tests\Test-Common.ps1
```

Run them in both Windows PowerShell 5.1 and PowerShell 7 before releasing.
Live GitHub behavior is covered by the separate manual acceptance scenario.

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Changes are
recorded in [CHANGELOG.md](CHANGELOG.md).

## License

GitHub Course Sync is available under the [MIT License](LICENSE).
