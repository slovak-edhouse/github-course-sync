#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$commonScript = Join-Path $repositoryRoot 'scripts\Common.ps1'
$failures = New-Object 'System.Collections.Generic.List[string]'
$testCount = 0

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Expected -cne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-ThrowsLike {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notlike $Pattern) {
            throw "Expected an error like '$Pattern', got '$($_.Exception.Message)'."
        }
        return
    }

    throw "Expected an error like '$Pattern', but no error was thrown."
}

function Invoke-Test {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $script:testCount++
    try {
        & $Action
        Write-Host "PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:failures.Add("$Name`: $($_.Exception.Message)")
        Write-Host "FAIL  $Name" -ForegroundColor Red
        Write-Host "      $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function New-TestFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter()][string]$Configuration = @"
@{
    Organization     = 'school-org'
    BaseRepository   = 'school-org/programming-base'
    RepositoryPrefix = 'programming-'
    TeacherTeamSlug  = 'programming-teachers'
}
"@,
        [Parameter()][string]$Students = @"
StudentName,GitHubUsername,RepositorySuffix
"Jan Novák",Example-User,novak-jan
"Petra Svobodová",second-user,svobodova-petra
"@
    )

    $directory = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $directory | Out-Null
    $configurationPath = Join-Path $directory 'classroom.psd1'
    Write-Utf8File -Path $configurationPath -Content $Configuration
    Write-Utf8File -Path (Join-Path $directory 'students.csv') -Content $Students
    return $configurationPath
}

. $commonScript

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "github-course-sync-tests-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
    Invoke-Test 'All PowerShell files parse without errors' {
        $scripts = @(Get-ChildItem -Path $repositoryRoot -Filter '*.ps1' -File -Recurse)
        Assert-True -Condition ($scripts.Count -ge 4) -Message 'Expected at least four PowerShell files.'

        foreach ($script in $scripts) {
            $tokens = $null
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $script.FullName,
                [ref]$tokens,
                [ref]$parseErrors
            )
            if ($parseErrors.Count -gt 0) {
                throw "$($script.FullName): $($parseErrors[0].Message)"
            }
        }
    }

    Invoke-Test 'Valid configuration and UTF-8 students are mapped' {
        $path = New-TestFixture -Root $temporaryRoot -Name 'valid'
        $configuration = Import-ClassroomConfiguration -Path $path
        $students = @(Get-ClassroomStudents -Configuration $configuration)

        Assert-Equal -Expected 'school-org/programming-base' -Actual $configuration.BaseRepository -Message 'Base repository mismatch.'
        Assert-Equal -Expected 2 -Actual $students.Count -Message 'Student count mismatch.'
        Assert-Equal -Expected 'Jan Novák' -Actual $students[0].StudentName -Message 'Student name mismatch.'
        Assert-Equal -Expected 'example-user' -Actual $students[0].GitHubUsername -Message 'Username should be normalized to lowercase.'
        Assert-Equal -Expected 'programming-novak-jan' -Actual $students[0].RepositoryName -Message 'Repository mapping mismatch.'
    }

    Invoke-Test 'Configuration accepts a base repository name without owner' {
        $configurationText = @"
@{
    Organization     = 'school-org'
    BaseRepository   = 'programming-base'
    RepositoryPrefix = 'programming-'
    TeacherTeamSlug  = 'programming-teachers'
}
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'short-base' -Configuration $configurationText
        $configuration = Import-ClassroomConfiguration -Path $path
        Assert-Equal -Expected 'school-org/programming-base' -Actual $configuration.BaseRepository -Message 'Organization should be added to the base name.'
    }

    Invoke-Test 'Student filtering is case-insensitive' {
        $path = New-TestFixture -Root $temporaryRoot -Name 'filter'
        $configuration = Import-ClassroomConfiguration -Path $path
        $students = @(Get-ClassroomStudents -Configuration $configuration -GitHubUsername 'EXAMPLE-USER')
        Assert-Equal -Expected 1 -Actual $students.Count -Message 'Filtered student count mismatch.'
        Assert-Equal -Expected 'Jan Novák' -Actual $students[0].StudentName -Message 'Wrong student was selected.'
    }

    Invoke-Test 'A base repository from another organization is rejected' {
        $configurationText = @"
@{
    Organization     = 'school-org'
    BaseRepository   = 'other-org/programming-base'
    RepositoryPrefix = 'programming-'
    TeacherTeamSlug  = 'programming-teachers'
}
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'wrong-org' -Configuration $configurationText
        Assert-ThrowsLike -Action { Import-ClassroomConfiguration -Path $path } -Pattern '*must belong to the configured school organization*'
    }

    Invoke-Test 'The exact CSV header is required' {
        $studentsText = @"
GitHubUsername,StudentName,RepositorySuffix
example-user,"Jan Novák",novak-jan
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'header' -Students $studentsText
        $configuration = Import-ClassroomConfiguration -Path $path
        Assert-ThrowsLike -Action { Get-ClassroomStudents -Configuration $configuration } -Pattern '*first line of students.csv must be exactly*'
    }

    Invoke-Test 'Duplicate usernames are rejected case-insensitively' {
        $studentsText = @"
StudentName,GitHubUsername,RepositorySuffix
"Student One",Example-User,student-one
"Student Two",example-user,student-two
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'duplicate-user' -Students $studentsText
        $configuration = Import-ClassroomConfiguration -Path $path
        Assert-ThrowsLike -Action { Get-ClassroomStudents -Configuration $configuration } -Pattern '*duplicate GitHubUsername*'
    }

    Invoke-Test 'Duplicate repository suffixes are rejected' {
        $studentsText = @"
StudentName,GitHubUsername,RepositorySuffix
"Student One",student-one,same-suffix
"Student Two",student-two,same-suffix
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'duplicate-suffix' -Students $studentsText
        $configuration = Import-ClassroomConfiguration -Path $path
        Assert-ThrowsLike -Action { Get-ClassroomStudents -Configuration $configuration } -Pattern '*duplicate RepositorySuffix*'
    }

    Invoke-Test 'Uppercase repository suffixes are rejected' {
        $studentsText = @"
StudentName,GitHubUsername,RepositorySuffix
"Student One",student-one,Student-One
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'uppercase-suffix' -Students $studentsText
        $configuration = Import-ClassroomConfiguration -Path $path
        Assert-ThrowsLike -Action { Get-ClassroomStudents -Configuration $configuration } -Pattern '*must use only lowercase letters*'
    }

    Invoke-Test 'A repository name collision with the base is rejected' {
        $studentsText = @"
StudentName,GitHubUsername,RepositorySuffix
"Student One",student-one,base
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'base-collision' -Students $studentsText
        $configuration = Import-ClassroomConfiguration -Path $path
        Assert-ThrowsLike -Action { Get-ClassroomStudents -Configuration $configuration } -Pattern '*collides with the base repository*'
    }

    Invoke-Test 'Native stderr does not fail a successful command' {
        $result = Invoke-NativeCommand -FilePath $env:ComSpec -Arguments @(
            '/d', '/s', '/c', 'echo normal progress 1>&2'
        )
        Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'Native exit code mismatch.'
        Assert-True -Condition ($result.Output -like '*normal progress*') -Message 'Native stderr was not captured.'
    }

    Invoke-Test 'Allowed native failures preserve exit code and output' {
        $result = Invoke-NativeCommand -FilePath $env:ComSpec -Arguments @(
            '/d', '/s', '/c', 'echo expected failure 1>&2 & exit /b 7'
        ) -AllowFailure
        Assert-Equal -Expected 7 -Actual $result.ExitCode -Message 'Allowed failure exit code mismatch.'
        Assert-True -Condition ($result.Output -like '*expected failure*') -Message 'Allowed failure output was not captured.'
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) of $testCount test(s) failed:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "- $failure" -ForegroundColor Red
    }
    throw 'Offline test suite failed.'
}

Write-Host "All $testCount tests passed." -ForegroundColor Green
