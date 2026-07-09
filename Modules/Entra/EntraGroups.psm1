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

Export-ModuleMember -Function Get-HIREntraGroups
