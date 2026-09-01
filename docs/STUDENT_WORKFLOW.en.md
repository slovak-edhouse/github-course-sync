# Working with your assigned repository

You have one or more private repositories in the school's GitHub organization.
A repository may be used for the whole course, one unit, or one assignment.
Your teacher will tell you which repository to use. The teacher chose its name,
so it may not contain your GitHub username. The school owns the repository, you
can write to it, and the teacher has administrative access. Other students
cannot see your repository.

## First sign-in

1. Accept the invitation to the school organization or repository.
2. Open the repository link provided by your teacher.
3. Clone it using the Git client selected for your class.
4. Work on the `main` branch.

Do not create your own repository or fork. Your teacher creates the repository
and may add new assignments, corrections, or supporting materials to it.

## Before each work session

Use your Git client to:

1. fetch changes from the remote repository named `origin`;
2. pull changes from the `main` branch on `origin` into your local `main` when
   changes are available.

Some clients combine these operations or perform a fetch automatically. Their
button names may differ, but the underlying Git operations are the same.

You should then see new or corrected materials relevant to that repository. If
your Git client reports a conflict or expected materials are missing, do not
use force-push and do not rewrite history. Ask your teacher for help.

## While working

- Work only in your assigned repository.
- Do not create directories or files reserved by the teacher for future
  materials.
- Save your work in small, meaningful commits.
- Never commit passwords, tokens, personal information, or other secrets.

## At the end of your work

1. Review the changed files.
2. Create a commit with a short, meaningful description.
3. Push your local `main` branch to `origin`.
4. Open the repository on GitHub and verify that your latest commit is visible.

A commit that remains only on a school computer has not been submitted.

## Conflict while receiving an assignment

When your changes overlap new teacher material, an open synchronization pull
request remains in your repository. After consulting your teacher, you may
resolve a simple conflict on GitHub:

1. Open the pull request whose title begins with
   `GitHub Course Sync: Course materials update`.
2. Select **Resolve conflicts**.
3. Decide with your teacher what the correct final file should contain and
   remove all conflict markers.
4. Select **Mark as resolved**, then **Commit merge**.
5. Select **Merge pull request**.

Complete both conflict resolution and the pull-request merge. If **Resolve
conflicts** is unavailable or the conflict is complicated, do not delete or
close anything. Ask your teacher for help.

## What you normally do not need

For ordinary course work, do not use:

- **Fork** or **Sync fork**;
- an `upstream` remote;
- force-push;
- repository permission or settings changes;
- deletion of synchronization branches created by the teacher.

Your normal workflow is simply:

```text
Fetch/Pull -> work -> Commit -> Push
```
