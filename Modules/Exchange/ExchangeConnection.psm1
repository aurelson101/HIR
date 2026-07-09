Set-StrictMode -Version Latest

function Connect-HIRExchangeOnline {
    [CmdletBinding()]
    param(
        [string]$UserPrincipalName,
        [bool]$ShowBanner = $false
    )

    Assert-HIRModule -Name ExchangeOnlineManagement
    Import-Module ExchangeOnlineManagement -ErrorAction Stop

    $params = @{ ShowBanner = $ShowBanner; ErrorAction = 'Stop' }
    if ($UserPrincipalName) { $params.UserPrincipalName = $UserPrincipalName }

    Connect-ExchangeOnline @params
    Write-HIRLog -Module Exchange -Action Connect -Level INFO -Message 'Exchange Online connection established.'
    $true
}

function Test-HIRExchangeConnection {
    [CmdletBinding()]
    param()

    try {
        [bool](Get-ConnectionInformation -ErrorAction Stop | Where-Object { $_.State -eq 'Connected' } | Select-Object -First 1)
    }
    catch {
        Write-HIRLog -Module Exchange -Action TestConnection -Level ERROR -Message $_.Exception.Message
        $false
    }
}

Export-ModuleMember -Function Connect-HIRExchangeOnline, Test-HIRExchangeConnection
