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
            foreach ($key in @(
                Get-HIRObjectPropertyValue -InputObject $recipient -Name 'WindowsLiveID'
                Get-HIRObjectPropertyValue -InputObject $recipient -Name 'PrimarySmtpAddress'
                Get-HIRObjectPropertyValue -InputObject $recipient -Name 'UserPrincipalName'
            )) {
                if ($key) {
                    $normalized = $key.ToString().ToLowerInvariant()
                    if (-not $recipientIndex.ContainsKey($normalized)) {
                        $recipientIndex[$normalized] = $recipient
                    }
                }
            }
        }

        foreach ($user in $disabledUsers) {
            $lookupKeys = @(
                Get-HIRObjectPropertyValue -InputObject $user -Name 'UserPrincipalName'
                Get-HIRObjectPropertyValue -InputObject $user -Name 'Mail'
            ) | Where-Object { $_ }
            $recipient = $null
            foreach ($key in $lookupKeys) {
                $normalized = $key.ToString().ToLowerInvariant()
                if ($recipientIndex.ContainsKey($normalized)) {
                    $recipient = $recipientIndex[$normalized]
                    break
                }
            }

            $adHidden = [bool](Get-HIRObjectPropertyValue -InputObject $user -Name 'msExchHideFromAddressLists')
            $exchangeHidden = if ($recipient) { [bool](Get-HIRObjectPropertyValue -InputObject $recipient -Name 'HiddenFromAddressListsEnabled') } else { $null }
            $issue = if ($recipient -and (-not $adHidden -or $exchangeHidden -eq $false)) { 'Disabled AD user visible or potentially visible in GAL' } else { '' }
            $action = if ($issue) { 'Review mailbox lifecycle. If appropriate, hide from address lists from on-prem AD attribute msExchHideFromAddressLists.' } else { 'No action detected by this report.' }

            [pscustomobject]@{
                SamAccountName                 = Get-HIRObjectPropertyValue -InputObject $user -Name 'SamAccountName'
                DisplayName                    = Get-HIRObjectPropertyValue -InputObject $user -Name 'DisplayName'
                UserPrincipalName              = Get-HIRObjectPropertyValue -InputObject $user -Name 'UserPrincipalName'
                Mail                           = Get-HIRObjectPropertyValue -InputObject $user -Name 'Mail'
                EnabledAD                      = Get-HIRObjectPropertyValue -InputObject $user -Name 'Enabled'
                MailNickname                   = Get-HIRObjectPropertyValue -InputObject $user -Name 'mailNickname'
                HasProxyAddresses              = [bool](Get-HIRObjectPropertyValue -InputObject $user -Name 'proxyAddresses')
                ADHiddenFromAddressLists       = $adHidden
                ExchangeRecipientType          = if ($recipient) { Get-HIRObjectPropertyValue -InputObject $recipient -Name 'RecipientTypeDetails' } else { $null }
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
        $params = @{ LDAPFilter = '(&(mail=*)(!(mailNickname=*)))'; Properties = @('mail', 'mailNickname', 'userPrincipalName'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object `
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'DisplayName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DisplayName' }},
            @{Name = 'UserPrincipalName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName' }},
            @{Name = 'Mail'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Mail' }},
            @{Name = 'MailNickname'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'MailNickname' }}
    }
}

function Get-HIRHybridADUsersMissingProxyAddresses {
    [CmdletBinding()]
    param([string]$SearchBase, [string]$Server)

    Invoke-HIRSafeCommand -Module Hybrid -Action 'AD users missing proxyAddresses' -ScriptBlock {
        Assert-HIRModule -Name ActiveDirectory
        Import-Module ActiveDirectory -ErrorAction Stop
        $params = @{ LDAPFilter = '(&(mail=*)(!(proxyAddresses=*)))'; Properties = @('mail', 'proxyAddresses', 'userPrincipalName'); ErrorAction = 'Stop' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }
        if ($Server) { $params.Server = $Server }
        Get-ADUser @params | Select-Object `
            @{Name = 'SamAccountName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'SamAccountName' }},
            @{Name = 'DisplayName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'DisplayName' }},
            @{Name = 'UserPrincipalName'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName' }},
            @{Name = 'Mail'; Expression = { Get-HIRObjectPropertyValue -InputObject $_ -Name 'Mail' }},
            @{Name = 'HasProxyAddresses'; Expression = { [bool](Get-HIRObjectPropertyValue -InputObject $_ -Name 'proxyAddresses') }}
    }
}

Export-ModuleMember -Function Get-HIRHybridDisabledADUsersVisibleInGAL, Get-HIRHybridADUsersMissingMailNickname, Get-HIRHybridADUsersMissingProxyAddresses
