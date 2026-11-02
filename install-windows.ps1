# Установка курса «ИИ для руководителей v2» на Windows 10/11.
# Не отключает UAC, SmartScreen и не повышает права само.

param(
    [string]$Mode = "",
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$SelfCheck
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
try { chcp 65001 > $null } catch {}
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

$Root = $PSScriptRoot
. (Join-Path $Root "lib\CourseSync.ps1")

if ($SelfCheck) {
    Invoke-CourseSelfCheck
    exit 0
}

$script:LogFile = Join-Path $env:TEMP "ai-managers-v2-setup.log"
Set-Content -LiteralPath $script:LogFile -Value "" -Encoding UTF8

function Write-Log([string]$Message) {
    $line = Redact-Text $Message
    Write-Host $line
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
}

function Read-Sources {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $raw = [System.IO.File]::ReadAllText((Join-Path $Root "config\sources.json"), $utf8)
    return ($raw | ConvertFrom-Json)
}

function Get-HttpCode([string]$Url) {
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 5 -TimeoutSec 15 -UseBasicParsing
        return [int]$resp.StatusCode
    } catch {
        $code = 0
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $code = [int]$_.Exception.Response.StatusCode
        }
        if ($code -eq 0 -or $code -eq 405) {
            try {
                $resp = Invoke-WebRequest -Uri $Url -Method Get -MaximumRedirection 5 -TimeoutSec 20 -UseBasicParsing
                return [int]$resp.StatusCode
            } catch {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    return [int]$_.Exception.Response.StatusCode
                }
            }
        }
        return $code
    }
}

function Open-Url([string]$Url) {
    Write-Log "Страница: $Url"
    if ($DryRun -or $env:COURSE_SETUP_TEST -eq "1") { return }
    Start-Process $Url
}

function Stop-WithStatus([string]$Status) {
    Write-Log "================================"
    Write-Log "ИТОГ: $Status"
    Write-Log "Журнал: $($script:LogFile)"
    Write-Log "================================"
    if ($Status -eq "ГОТОВО") { exit 0 }
    if ($Status -eq "ЧАСТИЧНО") { exit 2 }
    exit 3
}

function Test-PythonReady {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py -and $py.Source -notlike "*\WindowsApps\*") {
        & py -3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 2)"
        if ($LASTEXITCODE -eq 0) { return "ok" }
        if ($LASTEXITCODE -eq 2) { return "old" }
    }
    foreach ($name in @("python", "python3")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        if ($cmd.Source -like "*\WindowsApps\*") { continue }
        & $cmd.Source -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 2)"
        if ($LASTEXITCODE -eq 0) { return "ok" }
        if ($LASTEXITCODE -eq 2) { return "old" }
    }
    return "missing"
}

function Find-VerifiedZip([string]$ExpectedHash) {
    $dirs = @(
        (Join-Path $Root "offline"),
        (Join-Path $Root "course-pack"),
        (Join-Path $Root "docs\files")
    )
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $files = Get-ChildItem -LiteralPath $dir -Filter *.zip -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            if ((Get-Sha256File $file.FullName) -eq $ExpectedHash) { return $file.FullName }
            Write-Log "Архив не совпал с контрольной суммой и пропущен: $($file.Name)"
        }
    }
    return ""
}

$sources = Read-Sources
$testMode = $env:COURSE_SETUP_TEST -eq "1"
if ($testMode) {
    if (-not $env:COURSE_HOME -or $env:COURSE_HOME -eq "\" -or $env:COURSE_HOME -eq $env:USERPROFILE) {
        Write-Host "COURSE_HOME для теста задан небезопасно"
        exit 1
    }
    $Dest = $env:COURSE_HOME
} else {
    $docs = [Environment]::GetFolderPath("MyDocuments")
    $Dest = Join-Path $docs $sources.course_dir_name
}

$os = [Environment]::OSVersion.Version
$osOk = $os.Major -ge 10
if ($osOk) {
    Write-Log "Windows $($os.Major).$($os.Minor), архитектура $env:PROCESSOR_ARCHITECTURE"
} else {
    Write-Log "Нужна Windows 10 или 11. Сейчас: $($os.Major).$($os.Minor)"
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Log $(if ($isAdmin) { "Запущено с правами администратора. Они не обязательны для учебной папки." } else { "Без прав администратора. Учебная папка ставится в «Документы»." })

$spaceTarget = $Dest
if (-not $testMode) { $spaceTarget = [Environment]::GetFolderPath("MyDocuments") }
$driveRoot = [System.IO.Path]::GetPathRoot($spaceTarget)
$driveName = $driveRoot.TrimEnd("\").TrimEnd(":")
$freeMb = [math]::Floor((Get-PSDrive -Name $driveName).Free / 1MB)
$minMb = [int]$sources.min_free_mb
$spaceOk = $freeMb -ge $minMb
if ($spaceOk) { Write-Log "Свободно около $freeMb МБ." } else { Write-Log "Свободно $freeMb МБ, нужно не меньше $minMb МБ." }

$parent = Split-Path -Parent $Dest
$writable = $true
if (Test-Path -LiteralPath $parent) {
    $info = New-Object System.IO.DirectoryInfo $parent
    if (-not $info.PSIsContainer) { $writable = $false }
    elseif ($info.Attributes -band [System.IO.FileAttributes]::ReadOnly) { $writable = $false }
} elseif (-not (Test-Path -LiteralPath (Split-Path -Parent $parent))) {
    $writable = $false
}
if (-not $writable) { Write-Log "Нет права записи в $parent" } else { Write-Log "Папка курса: $Dest" }

$sums = Join-Path $Root "course-pack\SHA256SUMS"
$filesDir = Join-Path $Root "course-pack\files"
$packOk = $false
$packDir = ""
$work = Join-Path $env:TEMP ("ai-managers-pack-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $work -Force | Out-Null

if ((Test-Path -LiteralPath $filesDir) -and (Test-Path -LiteralPath $sums) -and (Test-SumTree $filesDir $sums)) {
    $packDir = $filesDir
    $packOk = $true
    Write-Log "Локальный пакет совпал с SHA-256."
} else {
    $zipLine = (Read-Utf8Lines (Join-Path $Root "course-pack\ZIP.SHA256"))[0]
    $zipHash = $zipLine.Substring(0, 64).ToLowerInvariant()
    $foundZip = Find-VerifiedZip $zipHash
    if (-not $foundZip) {
        $urlFile = Join-Path $Root "course-pack\download.url"
        if (Test-Path -LiteralPath $urlFile) {
            $packUrl = (Read-Utf8Lines $urlFile)[0].Trim()
            Write-Log "Пробую скачать пакет по адресу из course-pack/download.url"
            $downloaded = Join-Path $work "pack.zip"
            try {
                Invoke-WebRequest -Uri $packUrl -OutFile $downloaded -UseBasicParsing -TimeoutSec 180
                if ((Get-Sha256File $downloaded) -eq $zipHash) { $foundZip = $downloaded }
                else {
                    Write-Log "Скачанный пакет не совпал с SHA-256. Он не будет распакован."
                    Remove-Item -LiteralPath $downloaded -Force
                }
            } catch {
                Write-Log "Скачать пакет не удалось. Берём запасной вариант, если он есть."
            }
        }
    }
    if ($foundZip) {
        $tar = Get-Command tar -ErrorAction SilentlyContinue
        if (-not $tar) {
            Write-Log "В системе нет tar, распаковать запасной архив нельзя."
        } else {
            & $tar.Source -xf $foundZip -C $work
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Не удалось распаковать архив."
            } elseif (Test-SumTree $work $sums) {
                $packDir = $work
                $packOk = $true
                Write-Log "Пакет взят из архива и прошёл SHA-256."
            } else {
                Write-Log "Архив распаковался, но файлы не совпали с SHA256SUMS."
            }
        }
    }
}
if (-not $packOk) { Write-Log "Учебный пакет недоступен или повреждён." }

$manifest = Get-Content -LiteralPath (Join-Path $Root "course-pack\manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.version -ne $sources.pack_version) {
    $packOk = $false
    Write-Log "Версия пакета $($manifest.version) не совпадает с config/sources.json ($($sources.pack_version))."
}

$workAi = $false
$uninstallRoots = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($regRoot in $uninstallRoots) {
    try {
        $apps = Get-ItemProperty $regRoot -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "WorkAI*" }
        if ($apps) { $workAi = $true }
    } catch {}
}
if (-not $workAi -and (Get-Command workai -ErrorAction SilentlyContinue)) { $workAi = $true }
if ($workAi) { Write-Log "WorkAI найден. Заново ставить его не будем." } else { Write-Log "WorkAI в списке установленных программ не найден." }

$localInstaller = ""
$workAiDir = Join-Path $Root "offline\workai"
if (Test-Path -LiteralPath $workAiDir) {
    $exe = Get-ChildItem -LiteralPath $workAiDir -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) { $localInstaller = $exe.FullName }
}

$netWorkAi = Get-HttpCode $sources.workai_download
if ($netWorkAi -ge 200 -and $netWorkAi -lt 400) { Write-Log "Сайт WorkAI отвечает: $netWorkAi" }
else { Write-Log "Сайт WorkAI сейчас не открылся (код $netWorkAi). Установка файлов курса от этого не зависит." }

if ($sources.portal_url) {
    $netPortal = Get-HttpCode $sources.portal_url
    if ($netPortal -ge 200 -and $netPortal -lt 400) { Write-Log "Учебный сайт отвечает: $netPortal" }
    else { Write-Log "Учебный сайт не открылся. Локальная копия: $(Join-Path $Root 'docs\index.html')" }
} else {
    Write-Log "Адрес учебного сайта в настройках пуст. Локально откройте docs\index.html"
}

$gitOk = $false
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    & git --version | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $gitOk = $true
        Write-Log "Git уже есть. Менять установку не будем."
    }
}
if (-not $gitOk) { Write-Log "Git не найден." }

$pythonState = Test-PythonReady
$pythonOk = $pythonState -eq "ok"
if ($pythonState -eq "ok") { Write-Log "Python 3.9 или новее уже есть. Менять установку не будем." }
elseif ($pythonState -eq "old") { Write-Log "Python ниже 3.9. Текущую установку не удаляем. Можно поставить 3.12 рядом." }
else { Write-Log "Python 3 не найден." }

if (-not $Mode) {
    if ($DryRun) {
        $Mode = "BASIC"
        Write-Log "Режим не задан, для dry-run берём BASIC."
    } elseif ($Yes) {
        Write-Log "С ключом -Yes нужен -Mode BASIC или -Mode ADVANCED."
        exit 1
    } else {
        Write-Host "1 — BASIC: учебные файлы и страница WorkAI"
        Write-Host "2 — ADVANCED: то же плюс Git и Python, если их ещё нет"
        $choice = Read-Host "Введите 1 или 2"
        if ($choice -eq "1") { $Mode = "BASIC" }
        elseif ($choice -eq "2") { $Mode = "ADVANCED" }
        else {
            Write-Log "Режим не выбран. Изменения не выполнялись."
            exit 0
        }
    }
}
$Mode = $Mode.ToUpperInvariant()
if ($Mode -ne "BASIC" -and $Mode -ne "ADVANCED") {
    Write-Log "Режим должен быть BASIC или ADVANCED."
    exit 1
}

Write-Log "План, режим ${Mode}:"
Write-Log "1. Скопировать учебные файлы в $Dest. Ваши изменённые файлы не затираются."
if ($workAi) {
    Write-Log "2. WorkAI уже есть, установщик не открываем."
} elseif ($localInstaller) {
    Write-Log "2. Открыть локальный установщик WorkAI обычным мастером: $localInstaller"
    Write-Log "   Тихий режим не используется: официальные параметры тихой установки не опубликованы."
} else {
    Write-Log "2. Открыть официальную страницу загрузки WorkAI. Войти в аккаунт нужно самим."
}
if ($Mode -eq "ADVANCED") {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($gitOk) { Write-Log "3. Git не переустанавливаем." }
    elseif ($winget) { Write-Log "3. Поставить Git через winget, идентификатор $($sources.git_winget_id), область пользователя." }
    else { Write-Log "3. winget нет. Откроем страницу Git. Скрипт не скачивает чужой установщик." }
    if ($pythonOk) { Write-Log "4. Python не переустанавливаем." }
    elseif ($winget) { Write-Log "4. Поставить Python через winget, идентификатор $($sources.python_winget_id), не удаляя другую версию." }
    else { Write-Log "4. Откроем страницу Python." }
}
Write-Log "UAC, SmartScreen и антивирус скрипт не отключает."
Write-Log "Если Windows 11 блокирует установщик WorkAI интеллектуальным управлением приложениями, скрипт эту функцию не выключает: выключение необратимо без переустановки Windows. Позовите ведущего и откройте справку: $($sources.workai_windows_install_help)"

if (-not $osOk -or -not $spaceOk -or -not $packOk -or -not $writable) {
    if ($DryRun) { Write-Log "dry-run: изменения не выполнялись." }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Stop-WithStatus "ТРЕБУЕТСЯ ПОМОЩЬ"
}

if ($DryRun) {
    Write-Log "dry-run: изменения не выполнялись."
    $status = Get-SetupStatus $osOk $spaceOk $packOk $writable $packOk $workAi $Mode $gitOk $pythonOk
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Stop-WithStatus $status
}

if (-not $Yes) {
    $answer = Read-Host "Начать эти действия? Введите да или нет"
    if ($answer -notmatch '(?i)^(да|д|yes|y)$') {
        Write-Log "Изменения не выполнялись."
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        exit 0
    }
}

New-Item -ItemType Directory -Path (Join-Path $Dest "logs") -Force | Out-Null
$state = Join-Path $Dest ".course-setup.state"
Write-Utf8File $state "pack_version=$($manifest.version)`nmode=$Mode`n"
$sync = Sync-CourseTree $packDir $Dest $sums $state
$materialsOk = $true
Write-Log "Учебные файлы — новые, обновлены, сохранены ваши, без изменений: $($sync.Copy) $($sync.Update) $($sync.Keep) $($sync.Unchanged)"

if (-not $workAi) {
    if ($localInstaller) {
        Write-Log "Открываем локальный установщик WorkAI. Дальше нажимайте кнопки мастера сами."
        if (-not $testMode) { Start-Process -FilePath $localInstaller }
    } else {
        Write-Log "Дальше установка WorkAI вручную. Если появится синее окно защиты, нажмите «Подробнее», затем «Выполнить в любом случае». Это не отключение SmartScreen."
        Open-Url $sources.workai_download
    }
}

if ($Mode -eq "ADVANCED" -and -not $testMode) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $gitOk) {
        if ($winget) {
            Write-Log "Ставлю Git через winget."
            & winget install --exact --id $sources.git_winget_id --source winget --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity
            if ($LASTEXITCODE -eq 0) { $gitOk = $true } else {
                Write-Log "winget не поставил Git в профиль пользователя. Права сами не повышаем."
                Open-Url $sources.git_windows_download
            }
        } else { Open-Url $sources.git_windows_download }
    }
    if (-not $pythonOk) {
        if ($winget) {
            Write-Log "Ставлю Python 3.12 через winget. Уже стоящий Python не удаляется."
            & winget install --exact --id $sources.python_winget_id --source winget --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity
            if ($LASTEXITCODE -eq 0) { $pythonOk = $true } else {
                Write-Log "winget не поставил Python в профиль пользователя."
                Open-Url $sources.python_windows_download
            }
        } else { Open-Url $sources.python_windows_download }
    }
}
if ($Mode -eq "ADVANCED" -and $testMode) { Write-Log "Тестовый режим: Git и Python не ставятся." }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$saved = Join-Path $Dest "logs\setup-$stamp.log"
Copy-Item -LiteralPath $script:LogFile -Destination $saved -Force
$script:LogFile = $saved

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
$status = Get-SetupStatus $osOk $spaceOk $packOk $writable $materialsOk $workAi $Mode $gitOk $pythonOk
if ($status -eq "ЧАСТИЧНО") { Write-Log "Осталось сделать вручную то, что перечислено выше. Повторный запуск безопасен." }
if ($status -eq "ГОТОВО") { Write-Log "Можно открывать WorkAI и папку курса. Вход в аккаунт скрипт не выполняет." }
Stop-WithStatus $status
