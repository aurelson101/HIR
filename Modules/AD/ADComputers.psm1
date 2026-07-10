Set-StrictMode -Version Latest

function Get-HIRADInactiveComputers {
    [CmdletBinding()]
    param([int]$Days = 90, [string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module AD -Action 'Inactive computers report' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ ComputersOnly = $true; AccountInactive = $true; TimeSpan = (New-TimeSpan -Days $Days); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Search-ADAccount @params | Select-Object `
            @{Name = 'Name'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Name' }},
            @{Name = 'Enabled'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Enabled' }},
            @{Name = 'LastLogonDate'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'LastLogonDate' }},
            @{Name = 'DistinguishedName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DistinguishedName' }}
    }
}

Export-ModuleMember -Function Get-HIRADInactiveComputers
