#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\classroom.psd1')
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$configuration = Import-ClassroomConfiguration -Path $ConfigPath
$students = @(Get-ClassroomStudents -Configuration $configuration)
Assert-ClassroomTooling

$baseRepository = Get-GitHubRepository -FullName $configuration.BaseRepository
if (-not [bool]$baseRepository.private) {
    throw "Base repository '$($configuration.BaseRepository)' must be private."
}
if ([string]$baseRepository.default_branch -ne 'main') {
    throw "Base repository default branch must be 'main', but it is '$($baseRepository.default_branch)'."
}

$temporaryDirectory = New-ClassroomTemporaryDirectory
$bareRepository = Join-Path $temporaryDirectory 'base.git'
$pullRequestBodyFile = Join-Path $temporaryDirectory 'sync-body.md'
$baseUrl = "https://github.com/$($configuration.BaseRepository).git"
$results = @()

try {
    Write-Host "Reading complete classroom base from $($configuration.BaseRepository)..."
    Invoke-NativeCommand -FilePath 'git' -Arguments @(
        'clone', '--bare', '--single-branch', '--branch', 'main', $baseUrl, $bareRepository
    ) | Out-Null

    $baseHead = (Invoke-NativeCommand -FilePath 'git' -Arguments @(
        '--git-dir', $bareRepository, 'rev-parse', 'refs/heads/main'
    )).Output.Trim()
    $shortCommit = $baseHead.Substring(0, 12)
    $syncBranch = "classroom-sync/$shortCommit"
    $pullRequestTitle = "Classroom synchronization $shortCommit"
    $pullRequestBody = @"
This pull request synchronizes the complete current classroom base repository.

Base repository: $($configuration.BaseRepository)
Base commit: $baseHead

The pull request is managed automatically when there is no conflict.
If GitHub reports a conflict, the student or teacher may resolve and merge this pull request.
"@
    [System.IO.File]::WriteAllText(
        $pullRequestBodyFile,
        $pullRequestBody,
        (New-Object System.Text.UTF8Encoding($false))
    )

    Write-Host "Base commit: $baseHead"
    Write-Host "Synchronization branch: $syncBranch"

    foreach ($student in $students) {
        $studentName = $student.StudentName
        $username = $student.GitHubUsername
        $repositoryName = $student.RepositoryName
        $fullRepositoryName = "$($configuration.Organization)/$repositoryName"
        $studentUrl = "https://github.com/$fullRepositoryName.git"
        $studentMainRef = "refs/heads/student-main/$username"
        Write-Host "`n[$studentName | @$username] $fullRepositoryName"

        try {
            if (-not (Test-GitHubRepositoryExists -FullName $fullRepositoryName)) {
                $legacyRepositoryName = "$($configuration.RepositoryPrefix)$username"
                $legacyFullRepositoryName = "$($configuration.Organization)/$legacyRepositoryName"
                if ((-not $legacyFullRepositoryName.Equals($fullRepositoryName, [System.StringComparison]::OrdinalIgnoreCase)) -and
                    (Test-GitHubRepositoryExists -FullName $legacyFullRepositoryName)) {
                    throw "Expected repository '$fullRepositoryName' is missing, but possible legacy username-based repository '$legacyFullRepositoryName' exists. Review and rename it manually before continuing."
                }
                throw 'Student repository does not exist. Run Setup-Classroom.ps1.'
            }

            $studentRepository = Get-GitHubRepository -FullName $fullRepositoryName
            if (-not [bool]$studentRepository.private) {
                throw 'Student repository is not private.'
            }

            Invoke-NativeCommand -FilePath 'git' -Arguments @(
                '--git-dir', $bareRepository, 'fetch', '--force', '--no-tags', $studentUrl,
                "refs/heads/main:$studentMainRef"
            ) | Out-Null

            if (-not (Test-GitCommitsRelated -GitDirectory $bareRepository -FirstCommit $baseHead -SecondCommit $studentMainRef)) {
                throw 'Student main does not share history with the classroom base. It was not modified.'
            }

            if (Test-GitCommitAncestor -GitDirectory $bareRepository -Ancestor $baseHead -Descendant $studentMainRef) {
                Write-Host '  Already synchronized.'
                $results += [pscustomobject]@{
                    StudentName    = $studentName
                    GitHubUsername = $username
                    Repository     = $fullRepositoryName
                    Status         = 'Already current'
                    PullRequest    = ''
                    Message        = ''
                }
                continue
            }

            $openPullRequests = @((Invoke-GhJson -Arguments @(
                'pr', 'list', '--repo', $fullRepositoryName,
                '--state', 'open', '--json', 'number,headRefName,url', '--limit', '100'
            )).Value)
            $openSyncPullRequests = @($openPullRequests | Where-Object {
                ([string]$_.headRefName).StartsWith('classroom-sync/', [System.StringComparison]::OrdinalIgnoreCase)
            })
            $stalePullRequests = @($openSyncPullRequests | Where-Object { [string]$_.headRefName -ne $syncBranch })
            if ($stalePullRequests.Count -gt 0) {
                $numbers = $stalePullRequests | ForEach-Object { "#$($_.number)" }
                throw "Older classroom synchronization PR(s) remain open: $($numbers -join ', '). Resolve or close them before distributing a newer base commit."
            }

            $remoteSyncSha = Get-RemoteBranchSha -RepositoryUrl $studentUrl -Branch $syncBranch
            if ($null -ne $remoteSyncSha) {
                $studentSyncRef = "refs/heads/student-sync/$username"
                Invoke-NativeCommand -FilePath 'git' -Arguments @(
                    '--git-dir', $bareRepository, 'fetch', '--force', '--no-tags', $studentUrl,
                    "refs/heads/$syncBranch`:$studentSyncRef"
                ) | Out-Null
                if (-not (Test-GitCommitAncestor -GitDirectory $bareRepository -Ancestor $baseHead -Descendant $studentSyncRef)) {
                    throw "Remote synchronization branch '$syncBranch' no longer contains the expected base commit $baseHead."
                }
                if ($remoteSyncSha -ne $baseHead) {
                    Write-Host '  Reusing a conflict-resolution commit on the synchronization branch.'
                }
            }
            if ($null -eq $remoteSyncSha) {
                if ($PSCmdlet.ShouldProcess($fullRepositoryName, "Push complete base commit to $syncBranch")) {
                    Invoke-NativeCommand -FilePath 'git' -Arguments @(
                        '--git-dir', $bareRepository, 'push', $studentUrl,
                        "refs/heads/main:refs/heads/$syncBranch"
                    ) | Out-Null
                    $remoteSyncSha = $baseHead
                    Write-Host "  Pushed $syncBranch."
                }
                else {
                    Write-Host "  Would push $syncBranch."
                }
            }

            $pullRequest = @($openSyncPullRequests | Where-Object { [string]$_.headRefName -eq $syncBranch } | Select-Object -First 1)
            if ($pullRequest.Count -gt 0) {
                $pullRequest = $pullRequest[0]
                Write-Host "  Reusing open PR #$($pullRequest.number)."
            }
            else {
                $allCurrentPullRequests = @((Invoke-GhJson -Arguments @(
                    'pr', 'list', '--repo', $fullRepositoryName,
                    '--state', 'all', '--head', $syncBranch,
                    '--json', 'number,state,mergedAt,url,headRefName', '--limit', '1'
                )).Value)

                if ($allCurrentPullRequests.Count -gt 0) {
                    $pullRequest = $allCurrentPullRequests[0]
                    if (-not [string]::IsNullOrWhiteSpace([string]$pullRequest.mergedAt)) {
                        throw "Synchronization PR #$($pullRequest.number) is recorded as merged, but main does not contain base commit $baseHead. Inspect the repository manually."
                    }
                    if ([string]$pullRequest.state -eq 'CLOSED') {
                        if ($PSCmdlet.ShouldProcess($fullRepositoryName, "Reopen synchronization PR #$($pullRequest.number)")) {
                            Invoke-NativeCommand -FilePath 'gh' -Arguments @(
                                'pr', 'reopen', ([string]$pullRequest.number), '--repo', $fullRepositoryName
                            ) | Out-Null
                            Write-Host "  Reopened PR #$($pullRequest.number)."
                        }
                    }
                }
                else {
                    $pullRequest = $null
                    if ($PSCmdlet.ShouldProcess($fullRepositoryName, 'Create whole-base synchronization pull request')) {
                        Invoke-NativeCommand -FilePath 'gh' -Arguments @(
                            'pr', 'create', '--repo', $fullRepositoryName,
                            '--base', 'main', '--head', $syncBranch,
                            '--title', $pullRequestTitle,
                            '--body-file', $pullRequestBodyFile
                        ) | Out-Null

                        $createdPullRequests = @((Invoke-GhJson -Arguments @(
                            'pr', 'list', '--repo', $fullRepositoryName,
                            '--state', 'open', '--head', $syncBranch,
                            '--json', 'number,state,url,headRefName', '--limit', '1'
                        )).Value)
                        if ($createdPullRequests.Count -ne 1) {
                            throw 'Synchronization PR was created, but its number could not be determined.'
                        }
                        $pullRequest = $createdPullRequests[0]
                        Write-Host "  Created PR #$($pullRequest.number)."
                    }
                }
            }

            if (($null -ne $pullRequest) -and $PSCmdlet.ShouldProcess($fullRepositoryName, "Merge synchronization PR #$($pullRequest.number)")) {
                $mergeHeadSha = Get-RemoteBranchSha -RepositoryUrl $studentUrl -Branch $syncBranch
                if ($null -eq $mergeHeadSha) {
                    throw "Synchronization branch '$syncBranch' disappeared before PR #$($pullRequest.number) could be merged."
                }

                $studentSyncRef = "refs/heads/student-sync/$username"
                Invoke-NativeCommand -FilePath 'git' -Arguments @(
                    '--git-dir', $bareRepository, 'fetch', '--force', '--no-tags', $studentUrl,
                    "refs/heads/$syncBranch`:$studentSyncRef"
                ) | Out-Null
                if (-not (Test-GitCommitAncestor -GitDirectory $bareRepository -Ancestor $baseHead -Descendant $studentSyncRef)) {
                    throw "Synchronization branch '$syncBranch' no longer contains the expected base commit $baseHead."
                }

                $mergeResult = Invoke-NativeCommand -FilePath 'gh' -Arguments @(
                    'pr', 'merge', ([string]$pullRequest.number), '--repo', $fullRepositoryName,
                    '--merge', '--match-head-commit', $mergeHeadSha
                ) -AllowFailure
                if ($mergeResult.ExitCode -ne 0) {
                    Write-Verbose "gh pr merge output for $fullRepositoryName PR #$($pullRequest.number):`n$($mergeResult.Output)"
                    $pullRequestStateResult = Invoke-GhJson -Arguments @(
                        'pr', 'view', ([string]$pullRequest.number), '--repo', $fullRepositoryName,
                        '--json', 'number,url,mergeable,mergeStateStatus,headRefOid'
                    ) -AllowFailure
                    $pullRequestState = $pullRequestStateResult.Value
                    $pullRequestUrl = [string]$pullRequest.url
                    if (($null -ne $pullRequestState) -and (-not [string]::IsNullOrWhiteSpace([string]$pullRequestState.url))) {
                        $pullRequestUrl = [string]$pullRequestState.url
                    }
                    if ([string]::IsNullOrWhiteSpace($pullRequestUrl)) {
                        $pullRequestUrl = "https://github.com/$fullRepositoryName/pull/$($pullRequest.number)"
                    }

                    $isConflict = (($null -ne $pullRequestState) -and
                        (([string]$pullRequestState.mergeable -eq 'CONFLICTING') -or
                         ([string]$pullRequestState.mergeStateStatus -eq 'DIRTY'))) -or
                        ($mergeResult.Output -match 'cannot be cleanly created|merge conflict')

                    if ($isConflict) {
                        Write-Host '  Status: CONFLICT' -ForegroundColor Yellow
                        Write-Host "  Pull request: $pullRequestUrl"
                        Write-Host '  Action: Student or teacher must resolve and merge this pull request.'
                        $results += [pscustomobject]@{
                            StudentName    = $studentName
                            GitHubUsername = $username
                            Repository     = $fullRepositoryName
                            Status         = 'Needs attention'
                            PullRequest    = $pullRequestUrl
                            Message        = 'Resolve and merge the synchronization pull request.'
                        }
                        continue
                    }

                    throw "PR #$($pullRequest.number) could not be merged. Inspect $pullRequestUrl and rerun with -Verbose for GitHub CLI details."
                }

                Invoke-NativeCommand -FilePath 'git' -Arguments @(
                    '--git-dir', $bareRepository, 'fetch', '--force', '--no-tags', $studentUrl,
                    "refs/heads/main:$studentMainRef"
                ) | Out-Null
                if (-not (Test-GitCommitAncestor -GitDirectory $bareRepository -Ancestor $baseHead -Descendant $studentMainRef)) {
                    throw 'GitHub reported a successful merge, but the synchronized base commit is not present on student main.'
                }
                Write-Host "  Synchronized main through PR #$($pullRequest.number)."
            }

            $resultStatus = if ($WhatIfPreference) { 'Would update' } else { 'Synchronized' }
            $resultPullRequest = if ($null -ne $pullRequest) { [string]$pullRequest.url } else { '' }
            $results += [pscustomobject]@{
                StudentName    = $studentName
                GitHubUsername = $username
                Repository     = $fullRepositoryName
                Status         = $resultStatus
                PullRequest    = $resultPullRequest
                Message        = ''
            }
        }
        catch {
            Write-Verbose "Synchronization failure details for $fullRepositoryName`:`n$($_ | Out-String)"
            $failureLines = @(([string]$_.Exception.Message) -split '\r?\n')
            $failureSummary = $failureLines[0]
            Write-Host '  Status: FAILED' -ForegroundColor Red
            Write-Host "  Reason: $failureSummary" -ForegroundColor Red
            $results += [pscustomobject]@{
                StudentName    = $studentName
                GitHubUsername = $username
                Repository     = $fullRepositoryName
                Status         = 'Failed'
                PullRequest    = ''
                Message        = $failureSummary
            }
        }
    }

    $synchronizedCount = @($results | Where-Object Status -eq 'Synchronized').Count
    $wouldUpdateCount = @($results | Where-Object Status -eq 'Would update').Count
    $alreadyCurrentCount = @($results | Where-Object Status -eq 'Already current').Count
    $attentionCount = @($results | Where-Object Status -eq 'Needs attention').Count
    $failureCount = @($results | Where-Object Status -eq 'Failed').Count

    Write-Host "`nSynchronization summary:"
    if ($WhatIfPreference) {
        Write-Host "  Would update:     $wouldUpdateCount"
    }
    else {
        Write-Host "  Updated:          $synchronizedCount"
    }
    Write-Host "  Already current:  $alreadyCurrentCount"
    Write-Host "  Needs attention:  $attentionCount"
    Write-Host "  Failed:           $failureCount"

    if ($attentionCount -gt 0) {
        Write-Warning "$attentionCount synchronization pull request(s) require conflict resolution. Resolve and merge them before releasing a newer base commit."
    }
    if ($failureCount -gt 0) {
        Write-Warning "$failureCount repository synchronization(s) failed. Review the red messages above; use -Verbose for detailed diagnostics."
    }
    if ((-not $WhatIfPreference) -and ($synchronizedCount -gt 0)) {
        Write-Host 'Students only need to Fetch/Pull their own repositories.'
    }
}
finally {
    Remove-ClassroomTemporaryDirectory -Path $temporaryDirectory
}
