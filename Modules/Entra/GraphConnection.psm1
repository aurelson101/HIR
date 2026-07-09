Set-StrictMode -Version Latest

function Connect-HIREntra {
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [string[]]$Scopes = @('User.Read.All', 'Group.Read.All', 'Directory.Read.All', 'RoleManagement.Read.Directory', 'AuditLog.Read.All', 'Reports.Read.All')
    )

    Assert-HIRModule -Name Microsoft.Graph.Authentication
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $params = @{ Scopes = $Scopes; ErrorAction = 'Stop' }
    if ($TenantId) { $params.TenantId = $TenantId }

    Connect-MgGraph @params | Out-Null
    Write-HIRLog -Module Entra -Action Connect -Level INFO -Message 'Microsoft Graph connection established.'
    $true
}

function Test-HIRGraphConnection {
    [CmdletBinding()]
    param()

    try {
        Assert-HIRModule -Name Microsoft.Graph.Authentication
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        $context = Get-MgContext
        [bool]$context
    }
    catch {
        Write-HIRLog -Module Entra -Action TestConnection -Level ERROR -Message $_.Exception.Message
        $false
    }
}

Export-ModuleMember -Function Connect-HIREntra, Test-HIRGraphConnection
