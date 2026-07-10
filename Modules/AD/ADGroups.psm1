Set-StrictMode -Version Latest

function Resolve-HIRADWellKnownDomainGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Rid,

        [string]$Server
    )

    $domainParams = @{ ErrorAction = 'Stop' }
    if ($Server) { $domainParams.Server = $Server }

    $domain = Get-ADDomain @domainParams
    $domainSid = Get-HIRObjectPropertyValue -InputObject $domain -Name 'DomainSID'
    if (-not $domainSid) {
        throw 'Unable to resolve the current AD domain SID.'
    }

    $sidValue = '{0}-{1}' -f $domainSid.Value, $Rid
    $groupParams = @{
        Identity    = [System.Security.Principal.SecurityIdentifier]::new($sidValue)
        Properties  = @('sid', 'samAccountName')
        ErrorAction = 'Stop'
    }
    if ($Server) { $groupParams.Server = $Server }

    Get-ADGroup @groupParams
}

function Get-HIRADDomainAdminsMembers {
    [CmdletBinding()]
    param([string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Domain admins members report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $group = Resolve-HIRADWellKnownDomainGroup -Rid 512 -Server $Server
        $params = @{ Identity = $group.DistinguishedName; Recursive = $true; ErrorAction = 'Stop' }
        if ($Server) { $params.Server = $Server }
        Get-ADGroupMember @params | Select-Object `
            @{Name = 'SourceGroup'; Expression = { Get-HIRObjectPropertyValue -InputObject $group -Name 'Name' }},
            @{Name = 'SourceGroupSid'; Expression = { (Get-HIRObjectPropertyValue -InputObject $group -Name 'SID').Value }},
            @{Name = 'Name'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Name' }},
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'UserPrincipalName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName' }},
            @{Name = 'ObjectClass'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'ObjectClass' }},
            @{Name = 'DistinguishedName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DistinguishedName' }}
    }
}

function Get-HIRADEmptyGroups {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Empty groups report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ Filter = '*'; Properties = @('member'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADGroup @params | Where-Object { -not (Get-HIRObjectPropertyValue -InputObject $_ -Name 'member') } | Select-Object `
            @{Name = 'Name'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Name' }},
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'GroupCategory'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'GroupCategory' }},
            @{Name = 'GroupScope'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'GroupScope' }},
            @{Name = 'DistinguishedName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DistinguishedName' }}
    }
}

Export-ModuleMember -Function Get-HIRADDomainAdminsMembers, Get-HIRADEmptyGroups
