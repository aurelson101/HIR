Set-StrictMode -Version Latest

function Connect-HIRAD {
    [CmdletBinding()]
    param(
        [string]$Server
    )

    Assert-HIRModule -Name ActiveDirectory
    Import-Module ActiveDirectory -ErrorAction Stop

    $params = @{}
    if ($Server) { $params.Server = $Server }

    Get-ADDomain @params -ErrorAction Stop | Out-Null
    Write-HIRLog -Module AD -Action Connect -Level INFO -Message 'Active Directory connection validated.'
    $true
}

function Test-HIRADConnection {
    [CmdletBinding()]
    param(
        [string]$Server
    )

    try {
        Connect-HIRAD -Server $Server | Out-Null
        $true
    }
    catch {
        Write-HIRLog -Module AD -Action TestConnection -Level ERROR -Message $_.Exception.Message
        $false
    }
}

Export-ModuleMember -Function Connect-HIRAD, Test-HIRADConnection
