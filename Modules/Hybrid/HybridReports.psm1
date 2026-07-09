Set-StrictMode -Version Latest

function Get-HIRHybridDisabledADUsersVisibleInGAL {
    [CmdletBinding()]
    param(
        [string]$SearchBase,
        [string]$Server
    )

    Invoke-HIRSafeCommand -Module Hybrid -Action 'Disabled AD users still visible in GAL' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop

        $adParams = @{
            Filter      = 'Enabled -eq $false'
            Properties  = @('mail', 'mailNickname', 'proxyAddresses', 'msExchHideFromAddressLists', 'userPrincipalName')
            ErrorAction = 'Stop'
        }
        if ($SearchBase) { $adParams.SearchBase = $SearchBase }
        if ($Server) { $adParams.Server = $Server }

        $disabledUsers = Get-ADUser @adParams
        $recipients = Get-Recipient -ResultSize Unlimited -ErrorAction Stop | Select-Object DisplayName, WindowsLiveID, PrimarySmtpAddress, UserPrincipalName, RecipientTypeDetails, HiddenFromAddressListsEnabled

        $recipientIndex = @{}
        foreach ($recipient in $recipients) {
            foreach ($key in @($recipient.WindowsLiveID, $recipient.PrimarySmtpAddress, $recipient.UserPrincipalName)) {
                if ($key) {
                    $normalized = $key.ToString().ToLowerInvariant()
                    if (-not $recipientIndex.ContainsKey($normalized)) {
                        $recipientIndex[$normalized] = $recipient
                    }
                }
            }
        }

        foreach ($user in $disabledUsers) {
            $lookupKeys = @($user.UserPrincipalName, $user.Mail) | Where-Object { $_ }
            $recipient = $null
            foreach ($key in $lookupKeys) {
                $normalized = $key.ToString().ToLowerInvariant()
                if ($recipientIndex.ContainsKey($normalized)) {
                    $recipient = $recipientIndex[$normalized]
                    break
                }
            }

            $adHidden = [bool]$user.msExchHideFromAddressLists
            $exchangeHidden = if ($recipient) { [bool]$recipient.HiddenFromAddressListsEnabled } else { $null }
            $issue = if ($recipient -and (-not $adHidden -or $exchangeHidden -eq $false)) { 'Disabled AD user visible or potentially visible in GAL' } else { '' }
            $action = if ($issue) { 'Review mailbox lifecycle. If appropriate, hide from address lists from on-prem AD attribute msExchHideFromAddressLists.' } else { 'No action detected by this report.' }

            [pscustomobject]@{
                SamAccountName                 = $user.SamAccountName
                DisplayName                    = $user.DisplayName
                UserPrincipalName              = $user.UserPrincipalName
                Mail                           = $user.Mail
                EnabledAD                      = $user.Enabled
                MailNickname                   = $user.mailNickname
                HasProxyAddresses              = [bool]$user.proxyAddresses
                ADHiddenFromAddressLists       = $adHidden
                ExchangeRecipientType          = if ($recipient) { $recipient.RecipientTypeDetails } else { $null }
                ExchangeHiddenFromAddressLists = $exchangeHidden
                IssueDetected                  = $issue
                RecommendedAction              = $action
            }
        }
    }
}

function Get-HIRHybridADUsersMissingMailNickname {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module Hybrid -Action 'AD users missing mailNickname' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ LDAPFilter = '(&(mail=*)(!(mailNickname=*)))'; Properties = @('mail', 'mailNickname'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object SamAccountName, DisplayName, UserPrincipalName, Mail, MailNickname
    }
}

function Get-HIRHybridADUsersMissingProxyAddresses {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module Hybrid -Action 'AD users missing proxyAddresses' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ LDAPFilter = '(&(mail=*)(!(proxyAddresses=*)))'; Properties = @('mail', 'proxyAddresses'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object SamAccountName, DisplayName, UserPrincipalName, Mail, @{Name = 'HasProxyAddresses'; Expression = { [bool]$_.proxyAddresses }}
    }
}

Export-ModuleMember -Function Get-HIRHybridDisabledADUsersVisibleInGAL, Get-HIRHybridADUsersMissingMailNickname, Get-HIRHybridADUsersMissingProxyAddresses
