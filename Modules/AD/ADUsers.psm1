Set-StrictMode -Version Latest

function Get-HIRADDisabledUsers {
    [CmdletBinding()]
    param(
        [string]$SearchBase,
        [string]$Server
    )

    Invoke-HIRSafeCommand -Module AD -Action 'Disabled users report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop

        $params = @{
            Filter      = 'Enabled -eq $false'
            Properties  = @('mail', 'mailNickname', 'proxyAddresses', 'msExchHideFromAddressLists', 'userPrincipalName', 'lastLogonTimestamp', 'whenChanged')
            ErrorAction = 'Stop'
        }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }

        Get-ADUser @params | Select-Object `
            SamAccountName,
            DisplayName,
            UserPrincipalName,
            Mail,
            Enabled,
            MailNickname,
            @{Name = 'HasProxyAddresses'; Expression = { [bool]$_.proxyAddresses }},
            @{Name = 'ProxyAddresses'; Expression = { ($_.proxyAddresses -join ';') }},
            @{Name = 'ADHiddenFromAddressLists'; Expression = { [bool]$_.msExchHideFromAddressLists }},
            WhenChanged
    }
}

function Get-HIRADLockedUsers {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Locked users report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Search-ADAccount -LockedOut @params | Select-Object SamAccountName, Name, UserPrincipalName, Enabled, LockedOut
    }
}

function Get-HIRADInactiveUsers {
    [CmdletBinding()]
    param([int]$Days = 90, [string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Inactive users report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ UsersOnly = $true; AccountInactive = $true; TimeSpan = (New-TimeSpan -Days $Days); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Search-ADAccount @params | Select-Object SamAccountName, Name, UserPrincipalName, Enabled, LastLogonDate
    }
}

function Get-HIRADPasswordNeverExpiresUsers {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Password never expires report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ Filter = 'PasswordNeverExpires -eq $true -and Enabled -eq $true'; Properties = @('PasswordNeverExpires', 'mail'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object SamAccountName, DisplayName, UserPrincipalName, Mail, Enabled, PasswordNeverExpires
    }
}

function Get-HIRADAdminCountUsers {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'AdminCount users report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ LDAPFilter = '(adminCount=1)'; Properties = @('adminCount', 'mail'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object SamAccountName, DisplayName, UserPrincipalName, Mail, Enabled, AdminCount
    }
}

function Get-HIRADUsersWithoutEmail {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Users without email report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ LDAPFilter = '(!(mail=*))'; Properties = @('mail'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object SamAccountName, DisplayName, UserPrincipalName, Mail, Enabled
    }
}

function Get-HIRADUsersWithoutManager {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Users without manager report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ LDAPFilter = '(!(manager=*))'; Properties = @('manager', 'mail'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object SamAccountName, DisplayName, UserPrincipalName, Mail, Enabled, Manager
    }
}

Export-ModuleMember -Function Get-HIRADDisabledUsers, Get-HIRADLockedUsers, Get-HIRADInactiveUsers, Get-HIRADPasswordNeverExpiresUsers, Get-HIRADAdminCountUsers, Get-HIRADUsersWithoutEmail, Get-HIRADUsersWithoutManager
