#Requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Continue"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Normalize-Text([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    return ($Text -replace "\s+", " ").Trim()
}

function Get-UninstallEntries {
    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            $name = Normalize-Text $props.DisplayName
            if ($name -match "Revit") {
                [pscustomobject]@{
                    DisplayName = $name
                    DisplayVersion = Normalize-Text $props.DisplayVersion
                    RegistryPath = $_.PSPath
                }
            }
        }
    }
}

function Get-DetectedVersions {
    $versions = New-Object System.Collections.Generic.HashSet[string]

    Get-UninstallEntries | ForEach-Object {
        $text = "$($_.DisplayName) $($_.DisplayVersion)"
        [regex]::Matches($text, "\b20\d{2}\b") | ForEach-Object { [void]$versions.Add($_.Value) }
    }

    $patterns = @(
        "C:\Program Files\Autodesk\Revit *",
        "C:\Program Files\Autodesk\Autodesk Revit *",
        "C:\ProgramData\Autodesk\RVT *",
        "$env:APPDATA\Autodesk\Revit\Autodesk Revit *",
        "$env:LOCALAPPDATA\Autodesk\Revit\Autodesk Revit *"
    )

    foreach ($pattern in $patterns) {
        Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            [regex]::Matches($_.FullName, "\b20\d{2}\b") | ForEach-Object { [void]$versions.Add($_.Value) }
        }
    }

    return $versions | Sort-Object
}

function Resolve-UserPaths([string]$Version) {
    $paths = New-Object System.Collections.Generic.List[string]

    @(
        "C:\Program Files\Autodesk\Revit $Version",
        "C:\Program Files\Autodesk\Autodesk Revit $Version",
        "C:\ProgramData\Autodesk\RVT $Version",
        "C:\ProgramData\Autodesk\Revit\Addins\$Version",
        "C:\ProgramData\Autodesk\Revit\Extensions\$Version",
        "C:\ProgramData\Autodesk\Revit\Steel Connections $Version",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Autodesk\Revit $Version",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Autodesk\Autodesk Revit $Version"
    ) | ForEach-Object { $paths.Add($_) }

    Get-ChildItem -LiteralPath "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @("All Users", "Default", "Default User", "Public") } |
        ForEach-Object {
            $profile = $_.FullName
            @(
                "$profile\AppData\Roaming\Autodesk\Revit\Autodesk Revit $Version",
                "$profile\AppData\Roaming\Autodesk\Revit\Addins\$Version",
                "$profile\AppData\Roaming\Autodesk\Revit\Extensions\$Version",
                "$profile\AppData\Local\Autodesk\Revit\Autodesk Revit $Version",
                "$profile\AppData\Local\Autodesk\Revit\Addins\$Version",
                "$profile\AppData\Local\Autodesk\Revit\Journals\$Version",
                "$profile\AppData\Local\Autodesk\Web Services\Revit $Version"
            ) | ForEach-Object { $paths.Add($_) }
        }

    return $paths | Sort-Object -Unique
}

function Resolve-RegistryPaths([string]$Version) {
    $paths = New-Object System.Collections.Generic.List[string]

    @(
        "HKLM:\SOFTWARE\Autodesk\Revit\$Version",
        "HKLM:\SOFTWARE\Autodesk\Revit\Autodesk Revit $Version",
        "HKLM:\SOFTWARE\Autodesk\RVT $Version",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\Revit\$Version",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\Revit\Autodesk Revit $Version",
        "HKCU:\SOFTWARE\Autodesk\Revit\$Version",
        "HKCU:\SOFTWARE\Autodesk\Revit\Autodesk Revit $Version"
    ) | ForEach-Object {
        if (Test-Path -LiteralPath $_) { $paths.Add($_) }
    }

    Get-UninstallEntries |
        Where-Object { "$($_.DisplayName) $($_.DisplayVersion)" -match [regex]::Escape($Version) } |
        ForEach-Object { $paths.Add($_.RegistryPath) }

    return $paths | Sort-Object -Unique
}

function Test-RevitVersionText([string]$Text, [string]$Version) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match "Revit" -and $Text -match [regex]::Escape($Version))
}

function Add-UniqueExistingPath($List, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if ((Test-Path -LiteralPath $Path) -and (-not $List.Contains($Path))) {
        [void]$List.Add($Path)
    }
}

function Test-FolderHasRevitVersionMarker([string]$Path, [string]$Version) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if (Test-RevitVersionText $Path $Version) { return $true }

    $markerFiles = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 5MB -and $_.Extension -match "\.(xml|json|txt|ini|log|html|htm|js|config)$" } |
        Select-Object -First 30

    foreach ($file in $markerFiles) {
        try {
            $hitRevit = Select-String -LiteralPath $file.FullName -Pattern "Revit" -SimpleMatch -Quiet -ErrorAction SilentlyContinue
            if (-not $hitRevit) { continue }
            $hitVersion = Select-String -LiteralPath $file.FullName -Pattern $Version -SimpleMatch -Quiet -ErrorAction SilentlyContinue
            if ($hitVersion) { return $true }
        } catch {
        }
    }

    return $false
}

function Resolve-DeepFilePaths([string]$Version) {
    $paths = New-Object System.Collections.Generic.List[string]

    $direct = @(
        "C:\Autodesk\Revit $Version",
        "C:\Autodesk\Autodesk Revit $Version",
        "C:\Autodesk\RVT $Version",
        "C:\ProgramData\Autodesk\ODIS\logs\Revit $Version",
        "C:\ProgramData\Autodesk\ODIS\downloads\Revit $Version",
        "C:\ProgramData\Autodesk\ODIS\cache\Revit $Version",
        "C:\ProgramData\Autodesk\Uninstallers\Autodesk Revit $Version",
        "C:\ProgramData\Autodesk\Uninstallers\Revit $Version"
    )

    foreach ($path in $direct) { Add-UniqueExistingPath $paths $path }

    $scanRoots = @(
        "C:\Autodesk",
        "C:\ProgramData\Autodesk\ODIS\metadata",
        "C:\ProgramData\Autodesk\ODIS\manifest",
        "C:\ProgramData\Autodesk\ODIS\downloads",
        "C:\ProgramData\Autodesk\UPI2",
        "C:\ProgramData\Autodesk\Uninstallers"
    )

    foreach ($root in $scanRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-FolderHasRevitVersionMarker $_.FullName $Version) {
                Add-UniqueExistingPath $paths $_.FullName
            }
        }
    }

    Get-ChildItem -LiteralPath "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @("All Users", "Default", "Default User", "Public") } |
        ForEach-Object {
            $profile = $_.FullName
            @(
                "$profile\AppData\Local\Temp\Autodesk Revit $Version",
                "$profile\AppData\Local\Temp\Revit $Version",
                "$profile\AppData\Local\Autodesk\ODIS\Revit $Version",
                "$profile\AppData\Local\Autodesk\Webdeploy\production\Revit $Version"
            ) | ForEach-Object { Add-UniqueExistingPath $paths $_ }
        }

    return $paths | Sort-Object -Unique
}

function Get-RegistryPropertyText($Props) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($property in $Props.PSObject.Properties) {
        if ($property.Name -match "^PS") { continue }
        if ($null -ne $property.Value) { [void]$parts.Add([string]$property.Value) }
    }
    return ($parts -join " ")
}

function Resolve-DeepRegistryPaths([string]$Version) {
    $paths = New-Object System.Collections.Generic.List[string]

    $roots = @(
        "HKLM:\SOFTWARE\Autodesk\UPI2",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\UPI2",
        "HKLM:\SOFTWARE\Autodesk\ODIS",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\ODIS",
        "HKLM:\SOFTWARE\Autodesk\MC3",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\MC3"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            $text = "$($_.Name) $(Get-RegistryPropertyText $props)"
            if (Test-RevitVersionText $text $Version) {
                Add-UniqueExistingPath $paths $_.PSPath
            }
        }
    }

    $installerProducts = New-Object System.Collections.Generic.List[string]
    [void]$installerProducts.Add("HKLM:\SOFTWARE\Classes\Installer\Products")
    $userDataRoot = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData"
    if (Test-Path -LiteralPath $userDataRoot) {
        Get-ChildItem -LiteralPath $userDataRoot -ErrorAction SilentlyContinue | ForEach-Object {
            $productsPath = Join-Path $_.PSPath "Products"
            if (Test-Path -LiteralPath $productsPath) {
                [void]$installerProducts.Add($productsPath)
            }
        }
    }

    foreach ($root in $installerProducts) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $productKey = $_
            $props = Get-ItemProperty -LiteralPath $productKey.PSPath -ErrorAction SilentlyContinue
            $text = "$($productKey.Name) $(Get-RegistryPropertyText $props)"

            $installPropsPath = Join-Path $productKey.PSPath "InstallProperties"
            if (Test-Path -LiteralPath $installPropsPath) {
                $installProps = Get-ItemProperty -LiteralPath $installPropsPath -ErrorAction SilentlyContinue
                $text = "$text $(Get-RegistryPropertyText $installProps)"
            }

            if (Test-RevitVersionText $text $Version) {
                Add-UniqueExistingPath $paths $productKey.PSPath
            }
        }
    }

    return $paths | Sort-Object -Unique
}

function Get-CleanupPlan([string]$Version) {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($path in @(Resolve-UserPaths $Version | Where-Object { Test-Path -LiteralPath $_ })) {
        $items.Add([pscustomobject]@{ Type = "Folder/File"; Path = $path })
    }
    foreach ($path in @(Resolve-DeepFilePaths $Version)) {
        $items.Add([pscustomobject]@{ Type = "Deep File/Cache"; Path = $path })
    }
    foreach ($path in @(Resolve-RegistryPaths $Version)) {
        $items.Add([pscustomobject]@{ Type = "Registry"; Path = $path })
    }
    foreach ($path in @(Resolve-DeepRegistryPaths $Version)) {
        $items.Add([pscustomobject]@{ Type = "Deep Registry"; Path = $path })
    }
    return $items | Sort-Object Type, Path -Unique
}

function Remove-PlanItem($Item) {
    try {
        if ($Item.Type -like "*Registry*") {
            if (Test-Path -LiteralPath $Item.Path) {
                Remove-Item -LiteralPath $Item.Path -Recurse -Force -ErrorAction Stop
            }
        } else {
            if (Test-Path -LiteralPath $Item.Path) {
                Remove-Item -LiteralPath $Item.Path -Recurse -Force -ErrorAction Stop
            }
        }

        if (Test-Path -LiteralPath $Item.Path) {
        return "ОШИБКА: осталось после удаления | $($Item.Type) | $($Item.Path)"
    }
        return "УДАЛЕНО: $($Item.Type) | $($Item.Path)"
    } catch {
        return "ОШИБКА: $($Item.Type) | $($Item.Path) | $($_.Exception.Message)"
    }
}

function Get-AdskLicensingInstallers {
    Get-ChildItem -LiteralPath $PSScriptRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^AdskLicensing-installer .*\.exe$" } |
        Sort-Object {
            if ($_.BaseName -match "(\d+\.\d+\.\d+\.\d+)") {
                [version]$matches[1]
            } else {
                [version]"0.0.0.0"
            }
        } -Descending
}

function Get-AdskLicensingVersionText {
    $candidates = @(
        "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current\AdskLicensingService\AdskLicensingService.exe",
        "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\AdskLicensingService\AdskLicensingService.exe"
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            $info = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
            if ($info -and $info.VersionInfo.FileVersion) { return $info.VersionInfo.FileVersion }
        }
    }

    return "не найдено"
}

function Invoke-ProcessWait([string]$FilePath, [string]$Arguments, [string]$StepText) {
    Write-Report $StepText
    if (-not (Test-Path -LiteralPath $FilePath)) {
        Write-Report "ПРОПУСК: не найдено | $FilePath"
        return $false
    }

    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop
    Write-Report "КОД ВЫХОДА: $($process.ExitCode) | $FilePath"
    return ($process.ExitCode -eq 0)
}

function Update-AdskLicensing {
    $installers = @(Get-AdskLicensingInstallers)
    if ($installers.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Положите AdskLicensing-installer *.exe рядом с программой.", "Установщик не найден", "OK", "Warning") | Out-Null
        return
    }

    $installer = $installers[0]
    $currentVersion = Get-AdskLicensingVersionText
    $message = "Текущий AdskLicensing: $currentVersion`nБудет установлен: $($installer.Name)`n`nПродолжить?"
    $answer = [System.Windows.Forms.MessageBox]::Show($message, "Обновление AdskLicensing", "YesNo", "Question")
    if ($answer -ne "Yes") { return }

    $deleteButton.Enabled = $false
    $scanButton.Enabled = $false
    $refreshButton.Enabled = $false
    $licenseButton.Enabled = $false

    Write-Report ""
    Write-Report "ОБНОВЛЕНИЕ ADSK LICENSING: СТАРТ"
    Write-Report "ТЕКУЩАЯ ВЕРСИЯ: $currentVersion"
    Write-Report "УСТАНОВЩИК: $($installer.FullName)"

    Set-Progress 10 "Остановка службы Autodesk Licensing..."
    Get-Service -Name "AdskLicensingService" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
    Get-Process -Name "AdskLicensingService","AdskLicensingAgent","AdskLicensingInstHelper" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    Set-Progress 35 "Удаление старого AdskLicensing..."
    $uninstallers = @(
        "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\uninstall.exe",
        "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current\AdskLicensingService\uninstall.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ }

    foreach ($uninstaller in $uninstallers) {
        try {
            [void](Invoke-ProcessWait $uninstaller "--mode unattended" "УДАЛЕНИЕ: $uninstaller")
        } catch {
            Write-Report "ОШИБКА: не удалось удалить | $uninstaller | $($_.Exception.Message)"
        }
    }

    Set-Progress 70 "Установка нового AdskLicensing..."
    try {
        [void](Invoke-ProcessWait $installer.FullName "--mode unattended" "УСТАНОВКА: $($installer.FullName)")
    } catch {
        Write-Report "ОШИБКА: тихая установка не удалась | $($_.Exception.Message)"
        Write-Report "ПОПЫТКА: запуск установщика вручную"
        Start-Process -FilePath $installer.FullName -Wait -ErrorAction SilentlyContinue
    }

    Set-Progress 90 "Запуск службы..."
    Get-Service -Name "AdskLicensingService" -ErrorAction SilentlyContinue | Start-Service -ErrorAction SilentlyContinue
    $newVersion = Get-AdskLicensingVersionText
    Set-Progress 100 "AdskLicensing готов. Версия: $newVersion"

    Write-Report "НОВАЯ ВЕРСИЯ: $newVersion"
    Write-Report "ОБНОВЛЕНИЕ ADSK LICENSING: ГОТОВО"

    $scanButton.Enabled = $true
    $refreshButton.Enabled = $true
    $licenseButton.Enabled = $true
}

if (-not (Test-IsAdmin)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    exit
}

$logDir = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logPath = Join-Path $logDir ("Clean-Revit-GUI-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

$form = New-Object System.Windows.Forms.Form
$form.Text = "Очистка Revit"
$form.Size = New-Object System.Drawing.Size(900, 620)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(860, 540)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Очистка Revit"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(16, 12)
$title.Size = New-Object System.Drawing.Size(760, 32)
$form.Controls.Add($title)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = "Версия:"
$versionLabel.Location = New-Object System.Drawing.Point(18, 60)
$versionLabel.Size = New-Object System.Drawing.Size(70, 28)
$form.Controls.Add($versionLabel)

$versionBox = New-Object System.Windows.Forms.ComboBox
$versionBox.Location = New-Object System.Drawing.Point(90, 57)
$versionBox.Size = New-Object System.Drawing.Size(150, 28)
$versionBox.DropDownStyle = "DropDown"
$form.Controls.Add($versionBox)

$scanButton = New-Object System.Windows.Forms.Button
$scanButton.Text = "Поиск"
$scanButton.Location = New-Object System.Drawing.Point(250, 55)
$scanButton.Size = New-Object System.Drawing.Size(100, 32)
$form.Controls.Add($scanButton)

$deleteButton = New-Object System.Windows.Forms.Button
$deleteButton.Text = "Удалить"
$deleteButton.Location = New-Object System.Drawing.Point(360, 55)
$deleteButton.Size = New-Object System.Drawing.Size(100, 32)
$deleteButton.Enabled = $false
$form.Controls.Add($deleteButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Обновить"
$refreshButton.Location = New-Object System.Drawing.Point(470, 55)
$refreshButton.Size = New-Object System.Drawing.Size(100, 32)
$form.Controls.Add($refreshButton)

$licenseButton = New-Object System.Windows.Forms.Button
$licenseButton.Text = "Обновить лицензию"
$licenseButton.Location = New-Object System.Drawing.Point(580, 55)
$licenseButton.Size = New-Object System.Drawing.Size(130, 32)
$form.Controls.Add($licenseButton)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(18, 100)
$progress.Size = New-Object System.Drawing.Size(760, 24)
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)

$percent = New-Object System.Windows.Forms.Label
$percent.Text = "0%"
$percent.Location = New-Object System.Drawing.Point(790, 98)
$percent.Size = New-Object System.Drawing.Size(80, 28)
$form.Controls.Add($percent)

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(18, 140)
$list.Size = New-Object System.Drawing.Size(850, 235)
$list.Anchor = "Top,Left,Right"
$list.View = "Details"
$list.FullRowSelect = $true
$list.GridLines = $true
[void]$list.Columns.Add("Type", 120)
[void]$list.Columns.Add("Path", 710)
$form.Controls.Add($list)

$report = New-Object System.Windows.Forms.TextBox
$report.Location = New-Object System.Drawing.Point(18, 390)
$report.Size = New-Object System.Drawing.Size(850, 145)
$report.Anchor = "Top,Left,Right,Bottom"
$report.Multiline = $true
$report.ScrollBars = "Vertical"
$report.ReadOnly = $true
$form.Controls.Add($report)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Готово. Лог: $logPath"
$status.Location = New-Object System.Drawing.Point(18, 545)
$status.Size = New-Object System.Drawing.Size(850, 24)
$status.Anchor = "Left,Right,Bottom"
$form.Controls.Add($status)

$script:plan = @()

function Set-Progress([int]$Value, [string]$Text) {
    if ($Value -lt 0) { $Value = 0 }
    if ($Value -gt 100) { $Value = 100 }
    $progress.Value = $Value
    $percent.Text = "$Value%"
    $status.Text = $Text
    [System.Windows.Forms.Application]::DoEvents()
}

function Write-Report([string]$Text) {
    $report.AppendText($Text + [Environment]::NewLine)
    Add-Content -LiteralPath $logPath -Value $Text
}

function Load-Versions {
    $versionBox.Items.Clear()
    foreach ($v in @(Get-DetectedVersions)) {
        [void]$versionBox.Items.Add($v)
    }
    if ($versionBox.Items.Count -gt 0) { $versionBox.SelectedIndex = 0 }
}

function Scan-Version {
    $version = Normalize-Text $versionBox.Text
    if ($version -notmatch "^20\d{2}$") {
        [System.Windows.Forms.MessageBox]::Show("Введите версию, например 2022 или 2024.", "Неверная версия", "OK", "Warning") | Out-Null
        return
    }

    Set-Progress 5 "Поиск следов Revit $version..."
    $list.Items.Clear()
    $report.Clear()
    Write-Report "ПОИСК: Revit $version"

    $script:plan = @(Get-CleanupPlan $version)
    foreach ($item in $script:plan) {
        $row = New-Object System.Windows.Forms.ListViewItem($item.Type)
        [void]$row.SubItems.Add($item.Path)
        [void]$list.Items.Add($row)
    }

    Set-Progress 100 "Поиск готов. Найдено: $($script:plan.Count)."
    Write-Report "НАЙДЕНО: $($script:plan.Count)"
    $deleteButton.Enabled = ($script:plan.Count -gt 0)
}

function Delete-Version {
    $version = Normalize-Text $versionBox.Text
    if ($script:plan.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Ничего не найдено. Сначала нажмите Поиск.", "Нечего удалять", "OK", "Information") | Out-Null
        return
    }

    $msg = "Будут удалены найденные следы Revit $version из списка. Продолжить?"
    $answer = [System.Windows.Forms.MessageBox]::Show($msg, "Подтверждение удаления", "YesNo", "Warning")
    if ($answer -ne "Yes") { return }

    $deleteButton.Enabled = $false
    $scanButton.Enabled = $false
    $refreshButton.Enabled = $false
    $licenseButton.Enabled = $false
    $removed = 0
    $errors = 0

    Write-Report ""
    Write-Report "УДАЛЕНИЕ: СТАРТ Revit $version"

    $i = 0
    $total = [Math]::Max(1, $script:plan.Count)
    foreach ($item in $script:plan) {
        $i++
        $p = [int](($i / $total) * 100)
        Set-Progress $p "Удаление $i / $total..."
        $line = Remove-PlanItem $item
        Write-Report $line
        if ($line.StartsWith("УДАЛЕНО:")) { $removed++ } else { $errors++ }
    }

    Set-Progress 100 "Готово. Удалено: $removed. Ошибок: $errors."
    Write-Report "УДАЛЕНИЕ: ГОТОВО удалено=$removed ошибок=$errors"
    Write-Report "ДАЛЬШЕ: перезагрузите Windows перед установкой Revit."

    $scanButton.Enabled = $true
    $refreshButton.Enabled = $true
    $licenseButton.Enabled = $true
    $deleteButton.Enabled = $false
    Scan-Version
}

$refreshButton.Add_Click({ Load-Versions })
$scanButton.Add_Click({ Scan-Version })
$deleteButton.Add_Click({ Delete-Version })
$licenseButton.Add_Click({ Update-AdskLicensing })

$form.Add_Shown({
    Load-Versions
    Set-Progress 0 "Готово. Выберите версию и нажмите Поиск."
})

[void]$form.ShowDialog()

