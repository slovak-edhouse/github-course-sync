# Manual acceptance test

Run this scenario before the first real repository set and after any release
that changes GitHub operations. Use a dummy base repository and a test student
account. Never use a real student account for destructive testing. The same
scenario applies whether the real scope will be a school year, course, unit,
or individual assignment.

The examples below use:

```text
Organization:      school-org
Base repository:   course-sync-test-base
Student repository course-sync-test-student
Student name:       Test Student
Test account:      test-student
Teacher team:      programming-teachers
```

Replace every example value with your exact test resources.

## 1. Verify local tools

```powershell
git --version
gh --version
gh auth status
```

The authenticated account must have the organization permissions documented in
the README.

## 2. Prepare the isolated test configuration

Create `_local-test/classroom.psd1` and `_local-test/students.csv`. This
directory is ignored by Git.

```powershell
New-Item -ItemType Directory -Path .\_local-test
Copy-Item .\classroom.example.psd1 .\_local-test\classroom.psd1
Copy-Item .\students.example.csv .\_local-test\students.csv
```

Configure only the dummy repository and test account.

## 3. Preview setup

```powershell
.\scripts\Setup-Classroom.ps1 `
    -ConfigPath .\_local-test\classroom.psd1 `
    -WhatIf
```

Verify the displayed mapping. No GitHub repository, permission, or setting
should change.

## 4. Run setup

```powershell
.\scripts\Setup-Classroom.ps1 `
    -ConfigPath .\_local-test\classroom.psd1
```

Verify that the student repository is private and has the same initial `main`
commit as the base repository.

## 5. Verify repository security

Check visibility and forking:

```powershell
gh api repos/school-org/course-sync-test-student `
    --jq '{visibility: .visibility, allow_forking: .allow_forking}'
```

Expected values are `private` and `false`.

Check the student-repository description and **Website** link:

```powershell
gh api repos/school-org/course-sync-test-student `
    --jq '{description: .description, homepage: .homepage}'
```

Expected result:

```text
{
  "description": "Course repository for Test Student (@test-student), managed with GitHub Course Sync.",
  "homepage": "https://github.com/slovak-edhouse/github-course-sync/blob/main/docs/STUDENT_WORKFLOW.en.md"
}
```

Check the student's permission:

```powershell
gh api repos/school-org/course-sync-test-student/collaborators/test-student/permission `
    --jq '.permission'
```

Expected result:

```text
write
```

Check teacher-team access:

```powershell
gh api orgs/school-org/teams/programming-teachers/repos/school-org/course-sync-test-student `
    --jq '.permission'
```

Expected result:

```text
admin
```

Check base and student `main` protection:

```powershell
gh api repos/school-org/course-sync-test-base/branches/main/protection `
    --jq '{force_pushes_allowed: .allow_force_pushes.enabled, deletion_allowed: .allow_deletions.enabled}'

gh api repos/school-org/course-sync-test-student/branches/main/protection `
    --jq '{force_pushes_allowed: .allow_force_pushes.enabled, deletion_allowed: .allow_deletions.enabled}'
```

Both values should be `false`. A `404 Branch not protected` response means
that protection was not applied. Review setup warnings and the organization's
GitHub plan.

## 6. Verify the student workflow

Sign in as the test student in a separate browser profile:

1. Accept the invitation.
2. Open and clone the assigned repository.
3. Commit and push a harmless change to `main`.
4. Confirm that repository administration, visibility changes, transfer, and
   deletion are unavailable.
5. Confirm that the private base repository and another student's repository
   are inaccessible.
6. Confirm that private forking is unavailable. Do not enable organization-wide
   private forking just for this test.

## 7. Distribute a normal update

Add a new directory to the base repository, commit it, and push `main`. Preview
and run synchronization:

```powershell
.\scripts\Sync-Classroom.ps1 `
    -ConfigPath .\_local-test\classroom.psd1 `
    -WhatIf

.\scripts\Sync-Classroom.ps1 `
    -ConfigPath .\_local-test\classroom.psd1
```

Expected results:

- a `github-course-sync/<commit>` branch is pushed;
- an internal pull request titled
  `GitHub Course Sync: Course materials update (<commit>)` is created and
  merged;
- the student's earlier commit remains in history;
- the new base directory appears on student `main`.

## 8. Verify repeated synchronization

Run the same synchronization again. It should report the repository as already
current and should not create another pull request.

## 9. Verify conflict handling

Change the same existing line differently in the base and student repositories.
Commit and push both changes, then run synchronization.

Expected results:

- the script prints `Status: CONFLICT` in yellow;
- it prints the pull-request URL and a clear action;
- the script continues processing other students;
- the summary reports one repository needing attention, not a PowerShell
  failure stack trace.

Run synchronization again without resolving the conflict. The existing branch
and pull request should be reused; no duplicate pull request should be created.

Resolve the conflict as the test student or teacher, commit the resolution, and
merge the pull request. Run synchronization again. The repository should now
be reported as already current.

## 10. Record the result

Record the tested tool version, date, PowerShell version, GitHub CLI version,
Git version, and organization plan. Remove test repositories only after
manually verifying their exact names and confirming that no retained test
history is needed.
