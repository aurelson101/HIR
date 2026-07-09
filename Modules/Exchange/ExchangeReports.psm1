Set-StrictMode -Version Latest

function Get-HIRExchangeUserMailboxes {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Exchange -Action 'User mailboxes report' -ScriptBlock {
        Get-EXOMailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited -Properties ForwardingSmtpAddress,ForwardingAddress,DeliverToMailboxAndForward,HiddenFromAddressListsEnabled -ErrorAction Stop |
            Select-Object DisplayName, UserPrincipalName, PrimarySmtpAddress, RecipientTypeDetails, HiddenFromAddressListsEnabled
    }
}

function Get-HIRExchangeSharedMailboxes {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Exchange -Action 'Shared mailboxes report' -ScriptBlock {
        Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -Properties HiddenFromAddressListsEnabled -ErrorAction Stop |
            Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails, HiddenFromAddressListsEnabled
    }
}

function Get-HIRExchangeMailboxesWithForwarding {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Exchange -Action 'Forwarding mailboxes report' -ScriptBlock {
        Get-EXOMailbox -ResultSize Unlimited -Properties ForwardingSmtpAddress,ForwardingAddress,DeliverToMailboxAndForward,RecipientTypeDetails -ErrorAction Stop |
            Where-Object { $_.ForwardingSmtpAddress -or $_.ForwardingAddress } |
            Select-Object DisplayName, UserPrincipalName, PrimarySmtpAddress, RecipientTypeDetails, ForwardingSmtpAddress, ForwardingAddress, DeliverToMailboxAndForward,
                @{Name = 'IssueDetected'; Expression = { 'Mailbox forwarding enabled' }},
                @{Name = 'RecommendedAction'; Expression = { 'Review business justification and external forwarding policy.' }}
    }
}

function Get-HIRExchangeHiddenFromGAL {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Exchange -Action 'Hidden from GAL report' -ScriptBlock {
        Get-EXORecipient -ResultSize Unlimited -Properties HiddenFromAddressListsEnabled -ErrorAction Stop |
            Where-Object { $_.HiddenFromAddressListsEnabled -eq $true } |
            Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails, HiddenFromAddressListsEnabled
    }
}

Export-ModuleMember -Function Get-HIRExchangeUserMailboxes, Get-HIRExchangeSharedMailboxes, Get-HIRExchangeMailboxesWithForwarding, Get-HIRExchangeHiddenFromGAL
