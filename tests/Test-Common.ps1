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

    Invoke-Test 'All duplicate usernames are skipped case-insensitively' {
        $studentsText = @"
StudentName,GitHubUsername,RepositorySuffix
"Student One",Example-User,student-one
"Student Two",example-user,student-two
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'duplicate-user' -Students $studentsText
        $configuration = Import-ClassroomConfiguration -Path $path
        $report = $null
        $students = @(Get-ClassroomStudents -Configuration $configuration -Report ([ref]$report) -WarningAction SilentlyContinue)
        Assert-Equal 0 $students.Count 'Duplicate students must not be selected.'
        Assert-Equal 2 $report.Skipped.Count 'Both conflicting students must be skipped.'
    }

    Invoke-Test 'All duplicate repository suffixes are skipped' {
        $studentsText = @"
StudentName,GitHubUsername,RepositorySuffix
"Student One",student-one,same-suffix
"Student Two",student-two,same-suffix
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'duplicate-suffix' -Students $studentsText
        $configuration = Import-ClassroomConfiguration -Path $path
        $report = $null
        $students = @(Get-ClassroomStudents -Configuration $configuration -Report ([ref]$report) -WarningAction SilentlyContinue)
        Assert-Equal 0 $students.Count 'Conflicting repositories must not be selected.'
        Assert-Equal 2 $report.Skipped.Count 'Both conflicting mappings must be skipped.'
    }

    Invoke-Test 'Uppercase repository suffixes are skipped' {
        $studentsText = @"
StudentName,GitHubUsername,RepositorySuffix
"Student One",student-one,Student-One
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'uppercase-suffix' -Students $studentsText
        $configuration = Import-ClassroomConfiguration -Path $path
        $report = $null
        $students = @(Get-ClassroomStudents -Configuration $configuration -Report ([ref]$report) -WarningAction SilentlyContinue)
        Assert-Equal 0 $students.Count 'Invalid row must not be selected.'
        Assert-Equal 1 $report.Skipped.Count 'Invalid row must be reported.'
        Assert-True ($report.Skipped[0].Reason -like '*must use only lowercase letters*') 'Wrong skip reason.'
    }

    Invoke-Test 'A repository name collision with the base is skipped' {
        $studentsText = @"
StudentName,GitHubUsername,RepositorySuffix
"Student One",student-one,base
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'base-collision' -Students $studentsText
        $configuration = Import-ClassroomConfiguration -Path $path
        $report = $null
        $students = @(Get-ClassroomStudents -Configuration $configuration -Report ([ref]$report) -WarningAction SilentlyContinue)
        Assert-Equal 0 $students.Count 'Invalid row must not be selected.'
        Assert-Equal 1 $report.Skipped.Count 'Invalid row must be reported.'
        Assert-True ($report.Skipped[0].Reason -like '*collides with the base repository*') 'Wrong skip reason.'
    }

    Invoke-Test 'Invalid lines never prevent valid surrounding students from loading' {
        $invalidRows = @(
            @{ Line = '"Example",,example'; Reason = '*GitHubUsername is required*' },
            @{ Line = '"Example",   ,example'; Reason = '*GitHubUsername is required*' },
            @{ Line = '"Example",invalid_user!,example'; Reason = '*Invalid GitHub username*' },
            @{ Line = ('"Example",' + ('a' * 40) + ',example'); Reason = '*Invalid GitHub username*' },
            @{ Line = '"Example",-user,example'; Reason = '*Invalid GitHub username*' },
            @{ Line = '"Example",user-,example'; Reason = '*Invalid GitHub username*' },
            @{ Line = '"Example", user,example'; Reason = '*whitespace*' },
            @{ Line = '"Example",user ,example'; Reason = '*whitespace*' },
            @{ Line = ',user,example'; Reason = '*StudentName is required*' },
            @{ Line = '"Example",user,'; Reason = '*RepositorySuffix is required*' },
            @{ Line = '" Example",user,example'; Reason = '*whitespace*' },
            @{ Line = '"Example",user, example'; Reason = '*whitespace*' },
            @{ Line = '"Example",user,Example'; Reason = '*lowercase letters*' },
            @{ Line = '"Example",user,../example'; Reason = '*lowercase letters*' },
            @{ Line = ('"Example",user,' + ('a' * 100)); Reason = '*longer than 100*' },
            @{ Line = '"Example",user,base'; Reason = '*collides with the base*' },
            @{ Line = '"Example",user'; Reason = '*exactly 3 CSV fields*' },
            @{ Line = '"Example",user,example,extra'; Reason = '*exactly 3 CSV fields*' },
            @{ Line = '"Example,user,example'; Reason = '*Unclosed CSV*' },
            @{ Line = '"Example"oops,user,example'; Reason = '*Malformed CSV*' },
            @{ Line = 'Exam"ple,user,example'; Reason = '*Malformed CSV*' }
        )
        $caseNumber = 0
        foreach ($case in $invalidRows) {
            $caseNumber++
            $csv = "StudentName,GitHubUsername,RepositorySuffix`nBefore,before-user,before`n$($case.Line)`nAfter,after-user,after"
            $path = New-TestFixture -Root $temporaryRoot -Name "invalid-$caseNumber" -Students $csv
            $configuration = Import-ClassroomConfiguration -Path $path
            $report = $null
            $warnings = @()
            $students = @(Get-ClassroomStudents -Configuration $configuration -Report ([ref]$report) -WarningAction SilentlyContinue -WarningVariable warnings)
            Assert-Equal 2 $students.Count "Valid neighbors lost for case $caseNumber."
            Assert-Equal 'before-user' $students[0].GitHubUsername 'Wrong first student.'
            Assert-Equal 'after-user' $students[1].GitHubUsername 'Wrong last student.'
            Assert-Equal 1 $report.Skipped.Count 'Expected one skipped row.'
            Assert-Equal 3 $report.Skipped[0].LineNumber 'Wrong physical line number.'
            Assert-True ($report.Skipped[0].Reason -like $case.Reason) "Wrong reason for case $caseNumber."
            Assert-Equal 1 $warnings.Count 'Expected one warning.'
            Assert-True ([string]$warnings[0] -like '*students.csv:3: Skipping*') 'Warning must locate the row.'
        }
    }

    Invoke-Test 'Quoted commas, escaped quotes, UTF-8 and blank lines are supported' {
        $csv = "StudentName,GitHubUsername,RepositorySuffix`n`n   `n" + '"Novák, ""Jan""",Example-User,novak-jan'
        $path = New-TestFixture -Root $temporaryRoot -Name 'quoted' -Students $csv
        $configuration = Import-ClassroomConfiguration -Path $path
        $report = $null
        $students = @(Get-ClassroomStudents -Configuration $configuration -Report ([ref]$report))
        Assert-Equal 1 $students.Count 'Expected one student.'
        Assert-Equal 'Novák, "Jan"' $students[0].StudentName 'Quoted name was corrupted.'
        Assert-Equal 0 $report.Skipped.Count 'Blank lines are not skipped students.'
    }

    Invoke-Test 'Overlapping duplicates exclude every conflict and preserve unrelated students' {
        $csv = @"
StudentName,GitHubUsername,RepositorySuffix
One,shared-user,one
Two,SHARED-USER,two
Three,third-user,two
Four,fourth-user,four
"@
        $path = New-TestFixture -Root $temporaryRoot -Name 'overlapping' -Students $csv
        $configuration = Import-ClassroomConfiguration -Path $path
        $report = $null
        $students = @(Get-ClassroomStudents -Configuration $configuration -Report ([ref]$report) -WarningAction SilentlyContinue)
        Assert-Equal 1 $students.Count 'Only unrelated student should remain.'
        Assert-Equal 'fourth-user' $students[0].GitHubUsername 'Wrong survivor.'
        Assert-Equal 3 $report.Skipped.Count 'Every conflict must be excluded.'
        $filtered = @(Get-ClassroomStudents -Configuration $configuration -GitHubUsername shared-user -WarningAction SilentlyContinue)
        Assert-Equal 0 $filtered.Count 'Filtering must not bypass duplicates.'
    }

    Invoke-Test 'An invalid readable row still reserves its conflicting repository mapping' {
        $csv = "StudentName,GitHubUsername,RepositorySuffix`nIncomplete,,shared`nOther,other-user,shared`nValid,valid-user,valid"
        $path = New-TestFixture -Root $temporaryRoot -Name 'invalid-conflict' -Students $csv
        $configuration = Import-ClassroomConfiguration -Path $path
        $report = $null
        $students = @(Get-ClassroomStudents -Configuration $configuration -Report ([ref]$report) -WarningAction SilentlyContinue)
        Assert-Equal 1 $students.Count 'Incomplete row must not release its repository to another student.'
        Assert-Equal 'valid-user' $students[0].GitHubUsername 'Wrong survivor.'
        Assert-Equal 2 $report.Skipped.Count 'Both conflicting rows must be skipped.'
    }
    Invoke-Test 'Selection distinguishes skipped students from absent usernames' {
        $csv = "StudentName,GitHubUsername,RepositorySuffix`nSkipped,skipped-user,INVALID`nValid,valid-user,valid"
        $path = New-TestFixture -Root $temporaryRoot -Name 'skipped-selection' -Students $csv
        $configuration = Import-ClassroomConfiguration -Path $path
        $students = @(Get-ClassroomStudents -Configuration $configuration -GitHubUsername SKIPPED-USER,VALID-USER -WarningAction SilentlyContinue)
        Assert-Equal 1 $students.Count 'Valid selected student must remain.'
        Assert-Equal 'valid-user' $students[0].GitHubUsername 'Wrong selected student.'
        Assert-ThrowsLike { Get-ClassroomStudents -Configuration $configuration -GitHubUsername absent-user -WarningAction SilentlyContinue } '*not present in readable rows*'
    }

    Invoke-Test 'Missing and empty CSV files remain fatal' {
        $path = New-TestFixture -Root $temporaryRoot -Name 'missing-csv'
        $configuration = Import-ClassroomConfiguration -Path $path
        [IO.File]::WriteAllText($configuration.StudentsPath, '')
        Assert-ThrowsLike { Get-ClassroomStudents -Configuration $configuration } '*first line*'
        Remove-Item -LiteralPath $configuration.StudentsPath
        Assert-ThrowsLike { Get-ClassroomStudents -Configuration $configuration } '*not found*'
    }

    Invoke-Test 'Both scripts stop before tooling or external operations for zero eligible students' {
        # Copies isolate the scripts from real tools. The first external-operation
        # gateway throws if reached; normal return proves the early no-op path.
        $scriptDirectory = Join-Path $temporaryRoot 'isolated-scripts'
        New-Item -ItemType Directory -Path $scriptDirectory | Out-Null
        $stubCommon = [IO.File]::ReadAllText($commonScript) + "`nfunction Assert-ClassroomTooling { throw 'Unexpected tooling or external operation.' }"
        Write-Utf8File -Path (Join-Path $scriptDirectory 'Common.ps1') -Content $stubCommon
        $rosters = @(
            'StudentName,GitHubUsername,RepositorySuffix',
            "StudentName,GitHubUsername,RepositorySuffix`nExample,,example`nBroken,line"
        )
        $caseNumber = 0
        foreach ($roster in $rosters) {
            $caseNumber++
            $path = New-TestFixture -Root $temporaryRoot -Name "no-op-$caseNumber" -Students $roster
            foreach ($scriptName in @('Setup-Classroom.ps1', 'Sync-Classroom.ps1')) {
                $isolatedScript = Join-Path $scriptDirectory $scriptName
                Copy-Item -LiteralPath (Join-Path $repositoryRoot "scripts/$scriptName") -Destination $isolatedScript -Force
                $output = & $isolatedScript -ConfigPath $path -WarningAction SilentlyContinue 6>&1 | Out-String
                Assert-True ($output -like '*No eligible students selected*') 'Expected a clear no-op message.'
                Assert-True ($output -like '*skipped row(s)*') 'Expected skipped count.'
                $dryRunOutput = & $isolatedScript -ConfigPath $path -WhatIf -WarningAction SilentlyContinue 6>&1 | Out-String
                Assert-True ($dryRunOutput -like '*No eligible students selected*') 'Dry run must also be a no-op.'
            }
        }
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

# GitHub Actions propagates the last native-process exit code after a
# PowerShell step. The suite intentionally tests an allowed exit code of 7, so
# clear that stale value only after every assertion has passed.
$global:LASTEXITCODE = 0
