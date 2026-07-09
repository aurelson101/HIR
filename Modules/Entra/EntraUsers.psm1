Set-StrictMode -Version Latest

function Get-HIREntraSyncedUsers {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Entra -Action 'Synced users report' -ScriptBlock {
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        Get-MgUser -All -Property 'id,displayName,userPrincipalName,accountEnabled,userType,onPremisesSyncEnabled,mail,assignedLicenses' -Filter "onPremisesSyncEnabled eq true" -ErrorAction Stop |
            Select-Object DisplayName, UserPrincipalName, Mail, AccountEnabled, UserType, OnPremisesSyncEnabled
    }
}

function Get-HIREntraCloudOnlyUsers {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Entra -Action 'Cloud-only users report' -ScriptBlock {
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        Get-MgUser -All -Property 'id,displayName,userPrincipalName,accountEnabled,userType,onPremisesSyncEnabled,mail,createdDateTime,assignedLicenses' -ErrorAction Stop |
            Where-Object { $_.OnPremisesSyncEnabled -ne $true -and $_.UserType -eq 'Member' } |
            Select-Object DisplayName, UserPrincipalName, Mail, AccountEnabled, UserType, OnPremisesSyncEnabled, CreatedDateTime,
                @{Name = 'LicenseCount'; Expression = { @($_.AssignedLicenses).Count }}
    }
}

function Get-HIREntraGuestUsers {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Entra -Action 'Guest users report' -ScriptBlock {
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        Get-MgUser -All -Property 'id,displayName,userPrincipalName,accountEnabled,userType,mail,externalUserState,createdDateTime' -Filter "userType eq 'Guest'" -ErrorAction Stop |
            Select-Object DisplayName, UserPrincipalName, Mail, AccountEnabled, UserType, ExternalUserState, CreatedDateTime
    }
}

function Get-HIREntraDisabledUsers {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Entra -Action 'Disabled users report' -ScriptBlock {
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        Get-MgUser -All -Property 'displayName,userPrincipalName,accountEnabled,userType,mail,onPremisesSyncEnabled' -Filter 'accountEnabled eq false' -ErrorAction Stop |
            Select-Object DisplayName, UserPrincipalName, Mail, AccountEnabled, UserType, OnPremisesSyncEnabled
    }
}

function Get-HIREntraLicensedUsers {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Entra -Action 'Licensed users report' -ScriptBlock {
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        Get-MgUser -All -Property 'displayName,userPrincipalName,mail,accountEnabled,assignedLicenses' -ErrorAction Stop |
            Where-Object { @($_.AssignedLicenses).Count -gt 0 } |
            Select-Object DisplayName, UserPrincipalName, Mail, AccountEnabled, @{Name = 'LicenseCount'; Expression = { @($_.AssignedLicenses).Count }}
    }
}

function Get-HIREntraUsersWithoutLicense {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Entra -Action 'Users without license report' -ScriptBlock {
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        Get-MgUser -All -Property 'displayName,userPrincipalName,mail,accountEnabled,assignedLicenses' -ErrorAction Stop |
            Where-Object { @($_.AssignedLicenses).Count -eq 0 } |
            Select-Object DisplayName, UserPrincipalName, Mail, AccountEnabled
    }
}

Export-ModuleMember -Function Get-HIREntraSyncedUsers, Get-HIREntraCloudOnlyUsers, Get-HIREntraGuestUsers, Get-HIREntraDisabledUsers, Get-HIREntraLicensedUsers, Get-HIREntraUsersWithoutLicense
