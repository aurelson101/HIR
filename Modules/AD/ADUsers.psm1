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
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'DisplayName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DisplayName' }},
            @{Name = 'UserPrincipalName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName' }},
            @{Name = 'Mail'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Mail' }},
            @{Name = 'Enabled'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Enabled' }},
            @{Name = 'MailNickname'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'MailNickname' }},
            @{Name = 'HasProxyAddresses'; Expression = { [bool](Get-HIRObjectPropertyValue -InputObject $_ -Name 'proxyAddresses') }},
            @{Name = 'ProxyAddresses'; Expression = { @((Get-HIRObjectPropertyValue -InputObject $_ -Name 'proxyAddresses' -Default @())) -join ';' }},
            @{Name = 'ADHiddenFromAddressLists'; Expression = { [bool](Get-HIRObjectPropertyValue -InputObject $_ -Name 'msExchHideFromAddressLists') }},
            @{Name = 'WhenChanged'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'WhenChanged' }}
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
        Search-ADAccount -LockedOut @params | Select-Object `
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'Name'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Name' }},
            @{Name = 'UserPrincipalName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName' }},
            @{Name = 'Enabled'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Enabled' }},
            @{Name = 'LockedOut'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'LockedOut' }}
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
        Search-ADAccount @params | Select-Object `
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'Name'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Name' }},
            @{Name = 'UserPrincipalName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName' }},
            @{Name = 'Enabled'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Enabled' }},
            @{Name = 'LastLogonDate'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'LastLogonDate' }}
    }
}

function Get-HIRADPasswordNeverExpiresUsers {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Password never expires report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ Filter = 'PasswordNeverExpires -eq $true -and Enabled -eq $true'; Properties = @('PasswordNeverExpires', 'mail', 'userPrincipalName'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object `
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'DisplayName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DisplayName' }},
            @{Name = 'UserPrincipalName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName' }},
            @{Name = 'Mail'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Mail' }},
            @{Name = 'Enabled'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Enabled' }},
            @{Name = 'PasswordNeverExpires'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'PasswordNeverExpires' }}
    }
}

function Get-HIRADAdminCountUsers {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'AdminCount users report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ LDAPFilter = '(adminCount=1)'; Properties = @('adminCount', 'mail', 'userPrincipalName'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object `
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'DisplayName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DisplayName' }},
            @{Name = 'UserPrincipalName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName' }},
            @{Name = 'Mail'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Mail' }},
            @{Name = 'Enabled'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Enabled' }},
            @{Name = 'AdminCount'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'AdminCount' }}
    }
}

function Get-HIRADUsersWithoutEmail {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Users without email report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ LDAPFilter = '(!(mail=*))'; Properties = @('mail', 'userPrincipalName'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object `
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'DisplayName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DisplayName' }},
            @{Name = 'UserPrincipalName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName' }},
            @{Name = 'Mail'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Mail' }},
            @{Name = 'Enabled'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Enabled' }}
    }
}

function Get-HIRADUsersWithoutManager {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Users without manager report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ LDAPFilter = '(!(manager=*))'; Properties = @('manager', 'mail', 'userPrincipalName'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object `
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'DisplayName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DisplayName' }},
            @{Name = 'UserPrincipalName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName' }},
            @{Name = 'Mail'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Mail' }},
            @{Name = 'Enabled'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Enabled' }},
            @{Name = 'Manager'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Manager' }}
    }
}

function Get-HIRADAdminPasswordNeverExpiresUsers {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Privileged accounts with non-expiring passwords' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{
            LDAPFilter = '(&(adminCount=1)(userAccountControl:1.2.840.113556.1.4.803:=65536)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))'
            Properties = @('adminCount', 'PasswordNeverExpires', 'mail', 'userPrincipalName', 'memberOf')
            ErrorAction = 'Stop'
        }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object SamAccountName, DisplayName, UserPrincipalName, Mail, Enabled, PasswordNeverExpires,
            @{Name = 'PrivilegedSignal'; Expression = { 'adminCount=1' }},
            @{Name = 'MemberOf'; Expression = { @($_.MemberOf) -join ';' }}
    }
}

Export-ModuleMember -Function Get-HIRADDisabledUsers, Get-HIRADLockedUsers, Get-HIRADInactiveUsers, Get-HIRADPasswordNeverExpiresUsers, Get-HIRADAdminCountUsers, Get-HIRADUsersWithoutEmail, Get-HIRADUsersWithoutManager, Get-HIRADAdminPasswordNeverExpiresUsers
