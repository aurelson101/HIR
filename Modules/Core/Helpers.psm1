Set-StrictMode -Version Latest

function Enable-HIRTls12 {
    [CmdletBinding()]
    param()

    try {
        $tls12 = [Net.SecurityProtocolType]::Tls12
        if (([Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }

        Write-Output 'TLS 1.2 enabled for this PowerShell session.'
        return $true
    }
    catch {
        throw "Failed to enable TLS 1.2 for this PowerShell session: $($_.Exception.Message)"
    }
}

function Assert-HIRModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        throw "Required PowerShell module '$Name' is not installed."
    }
}

function Test-HIRModuleInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    [bool](Get-Module -ListAvailable -Name $Name)
}

function Get-HIRObjectPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Default = $null
    )

    if ($null -eq $InputObject) {
        return $Default
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Install-HIRPowerShellGalleryModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (Test-HIRModuleInstalled -Name $Name) {
        Write-Output "Module '$Name' is already installed."
        return $true
    }

    $previousPolicy = $null
    $previousProgressPreference = $global:ProgressPreference
    $previousConfirmPreference = $global:ConfirmPreference
    try {
        $global:ProgressPreference = 'SilentlyContinue'
        $global:ConfirmPreference = 'None'

        Enable-HIRTls12 | Out-Null
        Write-Output 'Checking NuGet package provider...'
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-Output 'Installing NuGet package provider for current user...'
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop | Out-Null
        }

        Write-Output 'Checking PSGallery repository policy...'
        $repository = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $repository) {
            Write-Output 'Registering default PSGallery repository...'
            Register-PSRepository -Default -ErrorAction Stop
            $repository = Get-PSRepository -Name PSGallery -ErrorAction Stop
        }

        $previousPolicy = $repository.InstallationPolicy
        if ($repository.InstallationPolicy -ne 'Trusted') {
            Write-Output 'Temporarily trusting PSGallery to avoid hidden installation prompts...'
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        }

        Write-Output "Installing module '$Name' from PSGallery..."
        $installParams = @{
            Name        = $Name
            Scope       = 'CurrentUser'
            Repository  = 'PSGallery'
            Force       = $true
            AllowClobber = $true
            Confirm     = $false
            ErrorAction = 'Stop'
        }
        $installModuleCommand = Get-Command Install-Module -ErrorAction Stop
        if ($installModuleCommand.Parameters.ContainsKey('AcceptLicense')) {
            $installParams.AcceptLicense = $true
        }
        if ($installModuleCommand.Parameters.ContainsKey('SkipPublisherCheck')) {
            $installParams.SkipPublisherCheck = $true
        }

        Install-Module @installParams
        Write-Output "Importing module '$Name'..."
        Import-Module $Name -ErrorAction Stop
        Write-Output "Module '$Name' installed and imported successfully."
        return $true
    }
    catch {
        throw "Failed to install PowerShell module '$Name': $($_.Exception.Message)"
    }
    finally {
        if ($previousPolicy -and $previousPolicy -ne 'Trusted') {
            try {
                Write-Output 'Restoring previous PSGallery repository policy...'
                Set-PSRepository -Name PSGallery -InstallationPolicy $previousPolicy -ErrorAction Stop
            }
            catch {
                Write-Output "WARNING: failed to restore PSGallery policy: $($_.Exception.Message)"
            }
        }

        $global:ProgressPreference = $previousProgressPreference
        $global:ConfirmPreference = $previousConfirmPreference
    }
}

function Install-HIRActiveDirectoryTools {
    [CmdletBinding()]
    param()

    if (Test-HIRModuleInstalled -Name ActiveDirectory) {
        return $true
    }

    try {
        Enable-HIRTls12 | Out-Null
        if (Get-Command -Name Install-WindowsFeature -ErrorAction SilentlyContinue) {
            Write-Output 'Installing RSAT Active Directory PowerShell tools with Install-WindowsFeature...'
            Import-Module ServerManager -ErrorAction SilentlyContinue
            Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeManagementTools -ErrorAction Stop | Out-Null
            Import-Module ActiveDirectory -ErrorAction Stop
            Write-Output 'RSAT Active Directory PowerShell tools installed successfully.'
            return $true
        }

        Write-Output 'Checking RSAT Active Directory Windows capability...'
        $capability = Get-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools*' -ErrorAction Stop | Select-Object -First 1
        if (-not $capability) {
            throw 'RSAT Active Directory capability was not found on this Windows edition.'
        }

        if ($capability.State -ne 'Installed') {
            Write-Output "Installing Windows capability '$($capability.Name)'..."
            Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop | Out-Null
        }

        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Output 'RSAT Active Directory PowerShell tools installed successfully.'
        return $true
    }
    catch {
        throw "Failed to install RSAT Active Directory tools: $($_.Exception.Message)"
    }
}

function New-HIRSafeFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = $Name.ToCharArray() | ForEach-Object {
        if ($invalid -contains $_) { '_' } else { $_ }
    }

    -join $safe
}

function Copy-HIRExistingReportsToArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string]$SafeReportName,

        [Parameter(Mandatory)]
        [string]$Extension
    )

    $reportDirectory = Join-Path $RootPath 'Reports'
    $archiveDirectory = Join-Path $RootPath 'Archive'
    if (-not (Test-Path -LiteralPath $archiveDirectory)) {
        New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
    }

    $pattern = '{0}-*.{1}' -f $SafeReportName, $Extension.TrimStart('.')
    Get-ChildItem -LiteralPath $reportDirectory -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
        $archiveName = '{0}.archived-{1}{2}' -f [System.IO.Path]::GetFileNameWithoutExtension($_.Name), (Get-Date -Format 'yyyyMMdd-HHmmss'), $_.Extension
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $archiveDirectory $archiveName) -Force
    }
}

Export-ModuleMember -Function Enable-HIRTls12, Assert-HIRModule, Test-HIRModuleInstalled, Get-HIRObjectPropertyValue, Install-HIRPowerShellGalleryModule, Install-HIRActiveDirectoryTools, New-HIRSafeFileName, Copy-HIRExistingReportsToArchive
