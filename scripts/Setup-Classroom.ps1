#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\classroom.psd1'),

    [Parameter()]
    [string[]]$GitHubUsername = @()
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$configuration = Import-ClassroomConfiguration -Path $ConfigPath
$students = @(Get-ClassroomStudents -Configuration $configuration -GitHubUsername $GitHubUsername)
Assert-ClassroomTooling

Write-Host 'Student repository mapping:'
$students | Select-Object StudentName, GitHubUsername, RepositoryName | Format-Table -AutoSize

$baseRepository = Get-GitHubRepository -FullName $configuration.BaseRepository
if (-not [bool]$baseRepository.private) {
    throw "Base repository '$($configuration.BaseRepository)' must be private."
}
if ([string]$baseRepository.default_branch -ne 'main') {
    throw "Base repository default branch must be 'main', but it is '$($baseRepository.default_branch)'."
}

$teamCheck = Invoke-NativeCommand -FilePath 'gh' -Arguments @(
    'api', "orgs/$($configuration.Organization)/teams/$($configuration.TeacherTeamSlug)", '--silent'
) -AllowFailure
if ($teamCheck.ExitCode -ne 0) {
    throw "Teacher team '$($configuration.TeacherTeamSlug)' was not found in organization '$($configuration.Organization)'."
}

$temporaryDirectory = New-ClassroomTemporaryDirectory
$bareRepository = Join-Path $temporaryDirectory 'base.git'
$baseUrl = "https://github.com/$($configuration.BaseRepository).git"
$failures = @()

try {
    Write-Host "Reading initial classroom content from $($configuration.BaseRepository)..."
    Invoke-NativeCommand -FilePath 'git' -Arguments @(
        'clone', '--bare', '--single-branch', '--branch', 'main', $baseUrl, $bareRepository
    ) | Out-Null

    $baseHead = (Invoke-NativeCommand -FilePath 'git' -Arguments @(
        '--git-dir', $bareRepository, 'rev-parse', 'refs/heads/main'
    )).Output.Trim()

    if ($PSCmdlet.ShouldProcess($configuration.BaseRepository, 'Secure base repository and grant teacher team Admin')) {
        Set-ClassroomRepositorySettings -Configuration $configuration -RepositoryName $configuration.BaseRepositoryName
        Grant-TeacherTeamAccess -Configuration $configuration -RepositoryName $configuration.BaseRepositoryName
        Set-ClassroomBranchProtection -Configuration $configuration -RepositoryName $configuration.BaseRepositoryName
    }

    foreach ($student in $students) {
        $studentName = $student.StudentName
        $username = $student.GitHubUsername
        $repositoryName = $student.RepositoryName
        $fullRepositoryName = "$($configuration.Organization)/$repositoryName"
        $studentUrl = "https://github.com/$fullRepositoryName.git"
        Write-Host "`n[$studentName | @$username] $fullRepositoryName"

        try {
            if ($fullRepositoryName.Equals($configuration.BaseRepository, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Generated student repository name collides with the base repository.'
            }

            $userCheck = Invoke-NativeCommand -FilePath 'gh' -Arguments @(
                'api', "users/$username", '--silent'
            ) -AllowFailure
            if ($userCheck.ExitCode -ne 0) {
                throw "GitHub account '$username' was not found for student '$studentName'."
            }

            $repositoryExists = Test-GitHubRepositoryExists -FullName $fullRepositoryName
            if (-not $repositoryExists) {
                $legacyRepositoryName = "$($configuration.RepositoryPrefix)$username"
                $legacyFullRepositoryName = "$($configuration.Organization)/$legacyRepositoryName"
                if ((-not $legacyFullRepositoryName.Equals($fullRepositoryName, [System.StringComparison]::OrdinalIgnoreCase)) -and
                    (Test-GitHubRepositoryExists -FullName $legacyFullRepositoryName)) {
                    throw "Expected repository '$fullRepositoryName' is missing, but possible legacy username-based repository '$legacyFullRepositoryName' exists. Review and rename it manually before continuing."
                }

                if ($PSCmdlet.ShouldProcess($fullRepositoryName, 'Create private student repository')) {
                    Invoke-NativeCommand -FilePath 'gh' -Arguments @(
                        'api', '--method', 'POST',
                        "orgs/$($configuration.Organization)/repos",
                        '-f', "name=$repositoryName",
                        '-f', "description=Private classroom repository for $studentName (@$username)",
                        '-F', 'private=true',
                        '-F', 'has_issues=true',
                        '-F', 'has_projects=false',
                        '-F', 'has_wiki=false',
                        '-F', 'auto_init=false',
                        '--silent'
                    ) | Out-Null
                    $repositoryExists = $true
                    Write-Host '  Created private repository.'
                }
                else {
                    Write-Host '  Would create private repository.'
                }
            }
            else {
                $existingRepository = Get-GitHubRepository -FullName $fullRepositoryName
                if (-not [bool]$existingRepository.private) {
                    throw 'An existing repository with the generated name is not private. It was not modified.'
                }
                Write-Host '  Repository already exists; it will not be recreated.'
            }

            if (-not $repositoryExists) {
                continue
            }

            $studentHead = Get-RemoteBranchSha -RepositoryUrl $studentUrl -Branch 'main'
            if ($null -eq $studentHead) {
                if ($PSCmdlet.ShouldProcess($fullRepositoryName, 'Seed main with complete base repository history')) {
                    Invoke-NativeCommand -FilePath 'git' -Arguments @(
                        '--git-dir', $bareRepository, 'push', $studentUrl,
                        'refs/heads/main:refs/heads/main'
                    ) | Out-Null
                    Write-Host "  Seeded main at $baseHead."
                }
            }
            else {
                $temporaryStudentRef = "refs/heads/setup/$username"
                Invoke-NativeCommand -FilePath 'git' -Arguments @(
                    '--git-dir', $bareRepository, 'fetch', '--force', '--no-tags', $studentUrl,
                    "refs/heads/main:$temporaryStudentRef"
                ) | Out-Null
                if (-not (Test-GitCommitsRelated -GitDirectory $bareRepository -FirstCommit $baseHead -SecondCommit $temporaryStudentRef)) {
                    throw 'Existing main does not share history with the classroom base. It was not modified.'
                }
                Write-Host "  Existing main left unchanged at $studentHead."
            }

            if ($PSCmdlet.ShouldProcess($fullRepositoryName, 'Apply secure settings and permissions')) {
                Set-ClassroomRepositorySettings -Configuration $configuration -RepositoryName $repositoryName
                Grant-TeacherTeamAccess -Configuration $configuration -RepositoryName $repositoryName
                Grant-StudentWriteAccess -Configuration $configuration -RepositoryName $repositoryName -GitHubUsername $username
                Set-ClassroomBranchProtection -Configuration $configuration -RepositoryName $repositoryName

                $pendingInvitations = @((Invoke-GhJson -Arguments @(
                    'api', "repos/$fullRepositoryName/invitations?per_page=100"
                )).Value)
                $studentInvitation = @($pendingInvitations | Where-Object {
                    ([string]$_.invitee.login).Equals($username, [System.StringComparison]::OrdinalIgnoreCase)
                })
                if ($studentInvitation.Count -gt 0) {
                    Write-Host '  Invitation is pending; the student must accept it.' -ForegroundColor Yellow
                }
                else {
                    Write-Host '  Student Write access and teacher Admin access are active.'
                }
            }
        }
        catch {
            $failures += [pscustomobject]@{
                StudentName    = $studentName
                GitHubUsername = $username
                Repository     = $fullRepositoryName
                Error          = $_.Exception.Message
            }
            Write-Error -Message "Setup failed for $fullRepositoryName`: $($_.Exception.Message)" -ErrorAction Continue
        }
    }

    if ($failures.Count -gt 0) {
        Write-Host "`nSetup completed with $($failures.Count) failure(s)."
        $failures | Format-Table StudentName, GitHubUsername, Repository, Error -Wrap
        throw 'Correct the reported problem and run Setup-Classroom.ps1 again.'
    }

    if ($WhatIfPreference) {
        Write-Host "`nSetup dry run completed for $($students.Count) student(s); no GitHub changes were made."
    }
    else {
        Write-Host "`nSetup completed for $($students.Count) student(s)."
    }
}
finally {
    Remove-ClassroomTemporaryDirectory -Path $temporaryDirectory
}
