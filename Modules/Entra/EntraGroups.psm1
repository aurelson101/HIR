Set-StrictMode -Version Latest

function Get-HIREntraGroups {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Entra -Action 'Groups inventory report' -ScriptBlock {
        Import-Module Microsoft.Graph.Groups -ErrorAction Stop
        Get-MgGroup -All -Property 'displayName,mail,mailEnabled,securityEnabled,groupTypes' -ErrorAction Stop |
            Select-Object DisplayName, Mail, MailEnabled, SecurityEnabled, @{Name = 'GroupTypes'; Expression = { $_.GroupTypes -join ';' }}
    }
}

function Get-HIREntraGroupsWithoutOwners {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Entra -Action 'Groups without owners report' -ScriptBlock {
        Import-Module Microsoft.Graph.Groups -ErrorAction Stop
        foreach ($group in Get-MgGroup -All -Property 'id,displayName,mail,mailEnabled,securityEnabled,groupTypes' -ErrorAction Stop) {
            $owners = @(Get-MgGroupOwner -GroupId $group.Id -All -ErrorAction Stop)
            if ($owners.Count -eq 0) {
                [pscustomobject]@{
                    Id = $group.Id
                    DisplayName = $group.DisplayName
                    Mail = $group.Mail
                    MailEnabled = $group.MailEnabled
                    SecurityEnabled = $group.SecurityEnabled
                    GroupTypes = @($group.GroupTypes) -join ';'
                    OwnerCount = 0
                    RecommendedAction = 'Assign at least two accountable owners and review them periodically.'
                }
            }
        }
    }
}

Export-ModuleMember -Function Get-HIREntraGroups, Get-HIREntraGroupsWithoutOwners
