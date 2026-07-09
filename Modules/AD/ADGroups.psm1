Set-StrictMode -Version Latest

function Get-HIRADDomainAdminsMembers {
    [CmdletBinding()]
    param([string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Domain admins members report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ Identity = 'Domain Admins'; Recursive = $true; ErrorAction = 'Stop' }
        if ($Server) { $params.Server = $Server }
        Get-ADGroupMember @params | Select-Object Name, SamAccountName, ObjectClass, DistinguishedName
    }
}

function Get-HIRDEmptyGroups {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Empty groups report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ Filter = '*'; Properties = @('member'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADGroup @params | Where-Object { -not $_.member } | Select-Object Name, SamAccountName, GroupCategory, GroupScope, DistinguishedName
    }
}

Export-ModuleMember -Function Get-HIRADDomainAdminsMembers, Get-HIRDEmptyGroups
