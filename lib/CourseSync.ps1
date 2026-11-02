# Решения установщика для Windows PowerShell 5.1. Правила те же, что в course_sync.sh.

function Get-PlanAction([string]$Current, [string]$Expected, [string]$Previous) {
    if ([string]::IsNullOrEmpty($Current)) { return "COPY" }
    if ($Current -eq $Expected) { return "UNCHANGED" }
    if (-not [string]::IsNullOrEmpty($Previous) -and $Current -eq $Previous) { return "UPDATE" }
    return "KEEP"
}

function Get-SetupStatus($OsOk, $SpaceOk, $PackOk, $Writable, $MaterialsOk, $WorkAi, [string]$Mode, $GitOk, $PythonOk) {
    if (-not ($OsOk -and $SpaceOk -and $PackOk -and $Writable -and $MaterialsOk)) {
        return "ТРЕБУЕТСЯ ПОМОЩЬ"
    }
    $advancedOk = ($Mode -ne "ADVANCED") -or ($GitOk -and $PythonOk)
    if ($WorkAi -and $advancedOk) { return "ГОТОВО" }
    return "ЧАСТИЧНО"
}

function Redact-Text([string]$Text) {
    $text = [regex]::Replace($Text, '(?i)(authorization)(\s*[:=]\s*)(\S+)', '$1$2[скрыто]')
    $text = [regex]::Replace($text, '(?i)(bearer)(\s+)(\S+)', '$1$2[скрыто]')
    return [regex]::Replace($text, '(?i)(token|password|secret|api[_-]?key)(\s*[:=]\s*)(\S+)', '$1$2[скрыто]')
}

function Get-Sha256File([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Read-Utf8Lines([string]$Path) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    return [System.IO.File]::ReadAllLines($Path, $utf8)
}

function Write-Utf8File([string]$Path, [string]$Text) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"), $utf8)
}

function Read-SumRows([string]$Path) {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in (Read-Utf8Lines $Path)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
        $rows.Add(@{ Hash = $line.Substring(0, 64).ToLowerInvariant(); Rel = $line.Substring(66) }) | Out-Null
    }
    return ,@($rows.ToArray())
}

function Read-StateMap([string]$Path) {
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in (Read-Utf8Lines $Path)) {
        $tab = $line.IndexOf("`t")
        if ($tab -lt 1) { continue }
        $map[$line.Substring(0, $tab)] = $line.Substring($tab + 1)
    }
    return $map
}

function Test-SumTree([string]$Source, [string]$SumsPath) {
    $sumRows = Read-SumRows $SumsPath
    foreach ($row in $sumRows) {
        $full = Join-Path $Source ($row.Rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full)) { return $false }
        if ((Get-Sha256File $full) -ne $row.Hash) { return $false }
    }
    return $true
}

function Sync-CourseTree([string]$Source, [string]$Dest, [string]$SumsPath, [string]$StatePath) {
    $previous = Read-StateMap $StatePath
    $header = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $StatePath) {
        foreach ($line in (Read-Utf8Lines $StatePath)) {
            if ($line.IndexOf("`t") -lt 0) { $header.Add($line) | Out-Null }
        }
    }
    $body = New-Object System.Collections.Generic.List[string]
    $copy = 0
    $update = 0
    $keep = 0
    $same = 0
    $sumRows = Read-SumRows $SumsPath
    foreach ($row in $sumRows) {
        $full = Join-Path $Dest ($row.Rel -replace '/', '\')
        $current = ""
        if (Test-Path -LiteralPath $full) { $current = Get-Sha256File $full }
        $prev = ""
        if ($previous.ContainsKey($row.Rel)) { $prev = [string]$previous[$row.Rel] }
        $action = Get-PlanAction $current $row.Hash $prev
        if ($action -eq "COPY" -or $action -eq "UPDATE") {
            $parent = Split-Path -Parent $full
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -LiteralPath (Join-Path $Source ($row.Rel -replace '/', '\')) -Destination $full -Force
            $body.Add("$($row.Rel)`t$($row.Hash)") | Out-Null
            if ($action -eq "COPY") { $copy += 1 } else { $update += 1 }
        } elseif ($action -eq "UNCHANGED") {
            $body.Add("$($row.Rel)`t$($row.Hash)") | Out-Null
            $same += 1
        } else {
            if (-not [string]::IsNullOrEmpty($prev)) { $body.Add("$($row.Rel)`t$prev") | Out-Null }
            $keep += 1
        }
    }
    $lines = @($header.ToArray()) + @($body.ToArray())
    Write-Utf8File $StatePath (($lines -join "`n") + "`n")
    return @{ Copy = $copy; Update = $update; Keep = $keep; Unchanged = $same }
}

function Invoke-CourseSelfCheck {
    $script:CourseCheckFail = $false
    function Assert-Same($Got, $Want, $Name) {
        if ($Got -ne $Want) {
            Write-Host "FAIL ${Name} : [$Got] != [$Want]"
            $script:CourseCheckFail = $true
        }
    }
    Assert-Same (Get-PlanAction "" "abc" "") "COPY" "missing"
    Assert-Same (Get-PlanAction "abc" "abc" "abc") "UNCHANGED" "same"
    Assert-Same (Get-PlanAction "old" "new" "old") "UPDATE" "previous"
    Assert-Same (Get-PlanAction "user" "new" "old") "KEEP" "user edit"
    Assert-Same (Get-PlanAction "user" "new" "") "KEEP" "foreign"
    Assert-Same (Get-SetupStatus $true $true $true $true $true $true "BASIC" $false $false) "ГОТОВО" "basic"
    Assert-Same (Get-SetupStatus $true $true $true $true $true $false "BASIC" $false $false) "ЧАСТИЧНО" "no workai"
    Assert-Same (Get-SetupStatus $true $true $true $true $true $true "ADVANCED" $false $true) "ЧАСТИЧНО" "no git"
    Assert-Same (Get-SetupStatus $true $false $true $true $true $true "BASIC" $true $true) "ТРЕБУЕТСЯ ПОМОЩЬ" "space"
    Assert-Same (Get-SetupStatus $true $true $false $true $true $true "BASIC" $true $true) "ТРЕБУЕТСЯ ПОМОЩЬ" "pack"
    Assert-Same (Get-SetupStatus $true $true $true $true $true $true "ADVANCED" $true $true) "ГОТОВО" "advanced"
    $hidden = Redact-Text "url?token=supersecret value"
    if ($hidden -like "*supersecret*") { Assert-Same "leaked" "hidden" "redact" }
    if ($hidden -notlike "*[скрыто]*") { Assert-Same "no-mark" "mark" "redact mark" }
    Assert-Same (Redact-Text "Обычная строка про токены без значения") "Обычная строка про токены без значения" "prose"
    if ($script:CourseCheckFail) { exit 1 }
    Write-Host "self-check ok"
}
