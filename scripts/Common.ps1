#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter()]
        [string[]]$Arguments = @(),

        [Parameter()]
        [switch]$AllowFailure
    )

    Write-Verbose ("Running: {0} {1}" -f $FilePath, ($Arguments -join ' '))
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 converts native stderr output into ErrorRecord
        # objects. Git writes normal progress to stderr, so Stop would terminate
        # before its exit code can be evaluated.
        $ErrorActionPreference = 'Continue'
        $commandOutput = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $outputText = ($commandOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Command failed with exit code $exitCode`: $FilePath $($Arguments -join ' ')`n$outputText"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $outputText
    }
}

function Invoke-GhJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter()]
        [switch]$AllowFailure
    )

    $result = Invoke-NativeCommand -FilePath 'gh' -Arguments $Arguments -AllowFailure:$AllowFailure
    if (($result.ExitCode -ne 0) -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return [pscustomobject]@{
            ExitCode = $result.ExitCode
            Output   = $result.Output
            Value    = $null
        }
    }

    try {
        $value = $result.Output | ConvertFrom-Json
    }
    catch {
        throw "GitHub CLI returned invalid JSON.`n$($result.Output)"
    }

    return [pscustomobject]@{
        ExitCode = $result.ExitCode
        Output   = $result.Output
        Value    = $value
    }
}

function Assert-ClassroomTooling {
    [CmdletBinding()]
    param()

    if (-not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
        throw "Required command 'git' was not found in PATH. Install it with 'winget install --id Git.Git', reopen PowerShell, and see README.md."
    }
    if (-not (Get-Command 'gh' -ErrorAction SilentlyContinue)) {
        throw "Required command 'gh' was not found in PATH. Install it with 'winget install --id GitHub.cli', reopen PowerShell, and see README.md."
    }

    $authResult = Invoke-NativeCommand -FilePath 'gh' -Arguments @('auth', 'status') -AllowFailure
    if ($authResult.ExitCode -ne 0) {
        throw "GitHub CLI is not authenticated. Run 'gh auth login' and 'gh auth setup-git'.`n$($authResult.Output)"
    }
}

function Import-ClassroomConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $configDirectory = Split-Path -Parent $resolvedPath
    $data = Import-PowerShellDataFile -LiteralPath $resolvedPath

    foreach ($requiredName in @('Organization', 'BaseRepository', 'RepositoryPrefix', 'TeacherTeamSlug')) {
        if ((-not $data.ContainsKey($requiredName)) -or [string]::IsNullOrWhiteSpace([string]$data[$requiredName])) {
            throw "Configuration value '$requiredName' is required in $resolvedPath."
        }
    }

    $baseRepository = ([string]$data.BaseRepository).Trim()
    if ($baseRepository.IndexOf('/') -lt 0) {
        $baseRepository = "$($data.Organization)/$baseRepository"
    }
    $baseParts = $baseRepository.Split('/', 2)
    if (($baseParts.Count -ne 2) -or
        (-not $baseParts[0].Equals([string]$data.Organization, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw 'BaseRepository must belong to the configured school organization.'
    }

    $prefix = ([string]$data.RepositoryPrefix).Trim()
    if ($prefix -notmatch '^[A-Za-z0-9._-]+$') {
        throw "RepositoryPrefix '$prefix' contains unsupported characters."
    }

    return [pscustomobject]@{
        ConfigurationPath      = $resolvedPath
        ConfigurationDirectory = $configDirectory
        StudentsPath           = [System.IO.Path]::GetFullPath((Join-Path $configDirectory 'students.csv'))
        Organization           = ([string]$data.Organization).Trim()
        BaseRepository         = $baseRepository
        BaseRepositoryName     = $baseParts[1]
        RepositoryPrefix       = $prefix
        TeacherTeamSlug        = ([string]$data.TeacherTeamSlug).Trim()
        DefaultBranch          = 'main'
    }
}

function Get-ClassroomStudents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Configuration,

        [Parameter()]
        [string[]]$GitHubUsername = @()
    )

    if (-not (Test-Path -LiteralPath $Configuration.StudentsPath -PathType Leaf)) {
        throw "Student configuration was not found: $($Configuration.StudentsPath)"
    }

    $expectedHeader = 'StudentName,GitHubUsername,RepositorySuffix'
    $actualHeader = Get-Content -LiteralPath $Configuration.StudentsPath -Encoding UTF8 -TotalCount 1
    if ([string]$actualHeader -cne $expectedHeader) {
        throw "The first line of students.csv must be exactly: $expectedHeader"
    }

    $csvRows = @(Import-Csv -LiteralPath $Configuration.StudentsPath -Encoding UTF8)
    if ($csvRows.Count -eq 0) {
        throw "Student configuration is empty: $($Configuration.StudentsPath)"
    }

    $students = @()
    foreach ($row in $csvRows) {
        $studentName = [string]$row.StudentName
        $username = [string]$row.GitHubUsername
        $repositorySuffix = [string]$row.RepositorySuffix

        if ([string]::IsNullOrWhiteSpace($studentName)) {
            throw 'StudentName is required for every row in students.csv.'
        }
        if ([string]::IsNullOrWhiteSpace($username)) {
            throw "GitHubUsername is required for student '$($studentName.Trim())'."
        }
        if ([string]::IsNullOrWhiteSpace($repositorySuffix)) {
            throw "RepositorySuffix is required for student '$($studentName.Trim())'."
        }
        if (($studentName -cne $studentName.Trim()) -or
            ($username -cne $username.Trim()) -or
            ($repositorySuffix -cne $repositorySuffix.Trim())) {
            throw "Leading or trailing whitespace is not allowed in students.csv (student '$($studentName.Trim())')."
        }
        if (($username.Length -gt 39) -or ($username -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$')) {
            throw "Invalid GitHub username format for '$studentName': '$username'."
        }
        if ($repositorySuffix -cnotmatch '^[a-z0-9._-]+$') {
            throw "RepositorySuffix for '$studentName' must use only lowercase letters, digits, '.', '_', and '-': '$repositorySuffix'."
        }

        $repositoryName = "$($Configuration.RepositoryPrefix)$repositorySuffix"
        if ($repositoryName.Length -gt 100) {
            throw "Generated repository name for '$studentName' is longer than 100 characters: '$repositoryName'."
        }
        if ($repositoryName.Equals($Configuration.BaseRepositoryName, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Generated repository name for '$studentName' collides with the base repository: '$repositoryName'."
        }

        $students += [pscustomobject]@{
            StudentName      = $studentName
            GitHubUsername   = $username.ToLowerInvariant()
            RepositorySuffix = $repositorySuffix
            RepositoryName   = $repositoryName
        }
    }

    $duplicateUsernames = @($students | Group-Object { $_.GitHubUsername.ToLowerInvariant() } | Where-Object Count -gt 1)
    if ($duplicateUsernames.Count -gt 0) {
        throw "students.csv contains duplicate GitHubUsername values: $($duplicateUsernames.Name -join ', ')"
    }
    $duplicateSuffixes = @($students | Group-Object { $_.RepositorySuffix.ToLowerInvariant() } | Where-Object Count -gt 1)
    if ($duplicateSuffixes.Count -gt 0) {
        throw "students.csv contains duplicate RepositorySuffix values: $($duplicateSuffixes.Name -join ', ')"
    }
    $duplicateRepositoryNames = @($students | Group-Object { $_.RepositoryName.ToLowerInvariant() } | Where-Object Count -gt 1)
    if ($duplicateRepositoryNames.Count -gt 0) {
        throw "students.csv generates duplicate repository names: $($duplicateRepositoryNames.Name -join ', ')"
    }

    if ($GitHubUsername.Count -gt 0) {
        $requestedUsernames = @($GitHubUsername | ForEach-Object { $_.Trim().ToLowerInvariant() })
        $unknownUsernames = @($requestedUsernames | Where-Object { @($students.GitHubUsername) -notcontains $_ })
        if ($unknownUsernames.Count -gt 0) {
            throw "Requested GitHub username(s) are not present in students.csv: $($unknownUsernames -join ', ')"
        }
        return @($students | Where-Object { $requestedUsernames -contains $_.GitHubUsername })
    }

    return $students
}

function Test-GitHubRepositoryExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullName
    )

    $result = Invoke-NativeCommand -FilePath 'gh' -Arguments @('api', "repos/$FullName", '--silent') -AllowFailure
    return ($result.ExitCode -eq 0)
}

function Get-GitHubRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullName
    )

    return (Invoke-GhJson -Arguments @('api', "repos/$FullName")).Value
}

function Grant-TeacherTeamAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryName
    )

    Invoke-NativeCommand -FilePath 'gh' -Arguments @(
        'api', '--method', 'PUT',
        "orgs/$($Configuration.Organization)/teams/$($Configuration.TeacherTeamSlug)/repos/$($Configuration.Organization)/$RepositoryName",
        '-f', 'permission=admin', '--silent'
    ) | Out-Null
}

function Grant-StudentWriteAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryName,

        [Parameter(Mandatory = $true)]
        [string]$GitHubUsername
    )

    Invoke-NativeCommand -FilePath 'gh' -Arguments @(
        'api', '--method', 'PUT',
        "repos/$($Configuration.Organization)/$RepositoryName/collaborators/$GitHubUsername",
        '-f', 'permission=push', '--silent'
    ) | Out-Null
}

function Set-ClassroomRepositorySettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryName
    )

    Invoke-NativeCommand -FilePath 'gh' -Arguments @(
        'api', '--method', 'PATCH',
        "repos/$($Configuration.Organization)/$RepositoryName",
        '-f', 'default_branch=main',
        '-F', 'delete_branch_on_merge=true',
        '--silent'
    ) | Out-Null

    # GitHub only permits repository-level private-fork settings when private
    # forking is enabled for the organization. If the organization already
    # prohibits private forks, PATCH returns HTTP 422 even when setting the
    # value to false. Treat that case as success after verifying the effective
    # repository value.
    $forkingResult = Invoke-NativeCommand -FilePath 'gh' -Arguments @(
        'api', '--method', 'PATCH',
        "repos/$($Configuration.Organization)/$RepositoryName",
        '-F', 'allow_forking=false',
        '--silent'
    ) -AllowFailure

    if ($forkingResult.ExitCode -ne 0) {
        $repository = Get-GitHubRepository -FullName "$($Configuration.Organization)/$RepositoryName"
        $allowForkingProperty = $repository.PSObject.Properties['allow_forking']
        if (($null -eq $allowForkingProperty) -or [bool]$allowForkingProperty.Value) {
            throw "Failed to disable forking for '$($Configuration.Organization)/$RepositoryName'.`n$($forkingResult.Output)"
        }
    }
}

function Set-ClassroomBranchProtection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryName
    )

    $protection = [ordered]@{
        required_status_checks           = $null
        enforce_admins                   = $false
        required_pull_request_reviews    = $null
        restrictions                     = $null
        required_conversation_resolution = $false
        allow_force_pushes                = $false
        allow_deletions                   = $false
        block_creations                   = $false
        lock_branch                       = $false
    }

    $temporaryFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText(
            $temporaryFile,
            ($protection | ConvertTo-Json -Depth 5),
            (New-Object System.Text.UTF8Encoding($false))
        )

        $result = Invoke-NativeCommand -FilePath 'gh' -Arguments @(
            'api', '--method', 'PUT',
            "repos/$($Configuration.Organization)/$RepositoryName/branches/main/protection",
            '--input', $temporaryFile, '--silent'
        ) -AllowFailure

        if ($result.ExitCode -ne 0) {
            Write-Warning "Branch protection could not be enabled for $RepositoryName. The organization plan may not support protected branches in private repositories. $($result.Output)"
        }
    }
    finally {
        Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue -WhatIf:$false
    }
}

function New-ClassroomTemporaryDirectory {
    [CmdletBinding()]
    param()

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("github-course-sync-{0}" -f [guid]::NewGuid().ToString('N'))
    # Read-only validation still needs a real local workspace during -WhatIf.
    New-Item -ItemType Directory -Path $path -WhatIf:$false | Out-Null
    return [System.IO.Path]::GetFullPath($path)
}

function Remove-ClassroomTemporaryDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedTarget = [System.IO.Path]::GetFullPath($Path)
    $temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $requiredPrefix = $temporaryRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $leafName = Split-Path -Leaf $resolvedTarget

    if ((-not $resolvedTarget.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase)) -or
        (-not $leafName.StartsWith('github-course-sync-', [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to remove unexpected temporary path: $resolvedTarget"
    }

    if (Test-Path -LiteralPath $resolvedTarget) {
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force -WhatIf:$false
    }
}

function Get-RemoteBranchSha {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryUrl,

        [Parameter(Mandatory = $true)]
        [string]$Branch
    )

    $result = Invoke-NativeCommand -FilePath 'git' -Arguments @(
        'ls-remote', '--heads', $RepositoryUrl, "refs/heads/$Branch"
    ) -AllowFailure

    if ($result.ExitCode -ne 0) {
        throw "Cannot read branch '$Branch' from $RepositoryUrl.`n$($result.Output)"
    }
    if ([string]::IsNullOrWhiteSpace($result.Output)) {
        return $null
    }

    return ($result.Output -split '\s+')[0]
}

function Test-GitCommitAncestor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GitDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Ancestor,

        [Parameter(Mandatory = $true)]
        [string]$Descendant
    )

    $result = Invoke-NativeCommand -FilePath 'git' -Arguments @(
        '--git-dir', $GitDirectory, 'merge-base', '--is-ancestor', $Ancestor, $Descendant
    ) -AllowFailure

    if ($result.ExitCode -eq 0) {
        return $true
    }
    if ($result.ExitCode -eq 1) {
        return $false
    }
    throw "Cannot compare Git commits '$Ancestor' and '$Descendant'.`n$($result.Output)"
}

function Test-GitCommitsRelated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GitDirectory,

        [Parameter(Mandatory = $true)]
        [string]$FirstCommit,

        [Parameter(Mandatory = $true)]
        [string]$SecondCommit
    )

    $result = Invoke-NativeCommand -FilePath 'git' -Arguments @(
        '--git-dir', $GitDirectory, 'merge-base', $FirstCommit, $SecondCommit
    ) -AllowFailure
    return ($result.ExitCode -eq 0)
}
