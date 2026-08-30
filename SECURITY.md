# Security Policy

GitHub Course Sync performs privileged operations on private organization
repositories. Security reports are taken seriously.

## Supported versions

Until the first stable release, only the latest tagged release and the current
`main` branch receive security fixes.

## Reporting a vulnerability

Do not report a vulnerability in a public issue. Use GitHub's private
vulnerability reporting feature:

1. Open the repository's **Security** tab.
2. Select **Advisories**.
3. Select **Report a vulnerability**.

If private reporting is temporarily unavailable, open a public issue that asks
the maintainer to provide a private contact channel. Do not include technical
details that could enable abuse.

Include only sanitized information:

- affected version or commit;
- PowerShell, Git, and GitHub CLI versions;
- a minimal reproduction using fictional organization, repository, and account
  names;
- the security impact.

Never include access tokens, authentication output, real student names,
`students.csv`, private repository URLs, school-internal links, or complete
diagnostic logs.

## Operational security

- Authenticate using GitHub CLI's credential store. Do not put tokens in the
  configuration files.
- Keep `classroom.psd1` and `students.csv` private and untracked.
- Use a dedicated test repository and dummy student account before managing
  real student repositories.
- Grant students only `Write` on their assigned repository.
- Keep every course, unit, or assignment base private and student-safe.
- Maintain at least two trusted organization owners for recovery.
- Review every release before using it with elevated organization permissions.
- Do not run untrusted pull-request code with organization secrets.

## Scope

Reports about vulnerabilities in GitHub, Git, GitHub CLI, PowerShell, or the
operating system should be sent to the relevant upstream project. Reports
about unsafe command construction, permission handling, data exposure, or
repository corruption caused by GitHub Course Sync belong here.
