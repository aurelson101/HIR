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
        $params = @{ Filter = '*'; Properties = @('member', 'SID'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        $userParams = @{ ErrorAction = 'Stop'; ResultSetSize = 1 }
        if ($Server) { $userParams.Server = $Server }
        # A group with no 'member' values can still hold users through primaryGroupID (e.g. Domain Users).
        Get-ADGroup @params | Where-Object {
            if (Get-HIRObjectPropertyValue -InputObject $_ -Name 'member') { return $false }
            $sid = Get-HIRObjectPropertyValue -InputObject $_ -Name 'SID'
            if (-not $sid) { return $true }
            $rid = ([string]$sid.Value).Split('-')[-1]
            -not (Get-ADObject -LDAPFilter "(primaryGroupID=$rid)" @userParams)
        } | Select-Object `
            @{Name = 'Name'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Name' }},
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'GroupCategory'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'GroupCategory' }},
            @{Name = 'GroupScope'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'GroupScope' }},
            @{Name = 'DistinguishedName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DistinguishedName' }}
    }
}

function Get-HIRADExtendedPrivilegedGroupsMembers {
    [CmdletBinding()]
    param([string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Extended privileged groups members report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop

        $baseParams = @{ ErrorAction = 'Stop' }
        if ($Server) { $baseParams.Server = $Server }
        $domainSid = [string](Get-ADDomain @baseParams).DomainSID.Value
        # Enterprise Admins and Schema Admins live in the forest root domain.
        $forestRoot = (Get-ADForest @baseParams).RootDomain
        $rootParams = @{ Identity = $forestRoot; ErrorAction = 'Stop' }
        $rootSid = [string](Get-ADDomain @rootParams).DomainSID.Value

        # Groups are resolved by SID/RID so localized domains work. Domain Admins has its own report.
        $targets = @(
            @{ Sid = "$rootSid-519"; Label = 'Enterprise Admins' }
            @{ Sid = "$rootSid-518"; Label = 'Schema Admins' }
            @{ Sid = "$domainSid-517"; Label = 'Cert Publishers' }
            @{ Sid = "$domainSid-520"; Label = 'Group Policy Creator Owners' }
            @{ Sid = 'S-1-5-32-544'; Label = 'Administrators' }
            @{ Sid = 'S-1-5-32-548'; Label = 'Account Operators' }
            @{ Sid = 'S-1-5-32-549'; Label = 'Server Operators' }
            @{ Sid = 'S-1-5-32-550'; Label = 'Print Operators' }
            @{ Sid = 'S-1-5-32-551'; Label = 'Backup Operators' }
            @{ Sid = 'S-1-5-32-552'; Label = 'Replicators' }
        )

        foreach ($target in $targets) {
            try {
                $groupParams = $baseParams.Clone()
                $groupParams.Identity = [System.Security.Principal.SecurityIdentifier]::new($target.Sid)
                $group = Get-ADGroup @groupParams
                $memberParams = $baseParams.Clone()
                $memberParams.Identity = $group.DistinguishedName
                $memberParams.Recursive = $true
                $members = @(Get-ADGroupMember @memberParams)
            }
            catch {
                Write-HIRLog -Module AD -Action 'Extended privileged groups members report' -Level WARNING -Message ('Skipped {0} ({1}): {2}' -f $target.Label, $target.Sid, $_.Exception.Message)
                continue
            }

            foreach ($member in $members) {
                [pscustomobject][ordered]@{
                    SourceGroup       = Get-HIRObjectPropertyValue -InputObject $group -Name 'Name'
                    SourceGroupSid    = $target.Sid
                    Name              = Get-HIRObjectPropertyValue -InputObject $member -Name 'Name'
                    SamAccountName    = Get-HIRObjectPropertyValue -InputObject $member -Name 'SamAccountName'
                    ObjectClass       = Get-HIRObjectPropertyValue -InputObject $member -Name 'ObjectClass'
                    DistinguishedName = Get-HIRObjectPropertyValue -InputObject $member -Name 'DistinguishedName'
                }
            }
        }
    }
}

function Get-HIRADGroupsWithoutManagedBy {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Groups without managedBy report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ LDAPFilter = '(&(objectCategory=group)(!(managedBy=*)))'; Properties = @('description', 'whenCreated'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADGroup @params |
            Where-Object { (Get-HIRObjectPropertyValue -InputObject $_ -Name 'DistinguishedName') -notlike '*,CN=Builtin,*' } |
            Select-Object `
                @{Name = 'Name'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Name' }},
                @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
                @{Name = 'GroupCategory'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'GroupCategory' }},
                @{Name = 'GroupScope'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'GroupScope' }},
                @{Name = 'Description'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Description' }},
                @{Name = 'WhenCreated'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'WhenCreated' }},
                @{Name = 'DistinguishedName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DistinguishedName' }}
    }
}
Export-ModuleMember -Function Get-HIRADDomainAdminsMembers, Get-HIRADEmptyGroups, Get-HIRADExtendedPrivilegedGroupsMembers, Get-HIRADGroupsWithoutManagedBy
