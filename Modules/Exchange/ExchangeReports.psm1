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

function Get-HIRExchangeFullAccessMailboxPermissions {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Exchange -Action 'Full Access mailbox permissions report' -ScriptBlock {
        foreach ($mailbox in Get-EXOMailbox -ResultSize Unlimited -Properties PrimarySmtpAddress -ErrorAction Stop) {
            Get-EXOMailboxPermission -Identity $mailbox.UserPrincipalName -ErrorAction Stop |
                Where-Object { -not $_.IsInherited -and $_.User -notlike 'NT AUTHORITY\\SELF' -and $_.AccessRights -contains 'FullAccess' } |
                Select-Object @{Name = 'Mailbox'; Expression = { $mailbox.PrimarySmtpAddress }}, User, AccessRights, IsInherited, Deny
        }
    }
}

function Get-HIRExchangeSendAsPermissions {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Exchange -Action 'Send As permissions report' -ScriptBlock {
        Get-EXORecipient -ResultSize Unlimited -ErrorAction Stop | ForEach-Object {
            $recipient = $_
            Get-RecipientPermission -Identity $recipient.Identity -ErrorAction Stop |
                Where-Object { -not $_.IsInherited -and $_.Trustee -notlike 'NT AUTHORITY\\SELF' -and $_.AccessRights -contains 'SendAs' } |
                Select-Object @{Name = 'Recipient'; Expression = { $recipient.PrimarySmtpAddress }}, Trustee, AccessRights, IsInherited
        }
    }
}

function Get-HIRExchangeSendOnBehalfPermissions {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Exchange -Action 'Send on Behalf permissions report' -ScriptBlock {
        Get-EXOMailbox -ResultSize Unlimited -Properties GrantSendOnBehalfTo -ErrorAction Stop |
            Where-Object { @($_.GrantSendOnBehalfTo).Count -gt 0 } |
            ForEach-Object {
                $mailbox = $_
                foreach ($delegate in @($mailbox.GrantSendOnBehalfTo)) {
                    [pscustomobject]@{ Mailbox = $mailbox.PrimarySmtpAddress; Delegate = [string]$delegate; Permission = 'SendOnBehalf' }
                }
            }
    }
}

Export-ModuleMember -Function Get-HIRExchangeUserMailboxes, Get-HIRExchangeSharedMailboxes, Get-HIRExchangeMailboxesWithForwarding, Get-HIRExchangeHiddenFromGAL, Get-HIRExchangeFullAccessMailboxPermissions, Get-HIRExchangeSendAsPermissions, Get-HIRExchangeSendOnBehalfPermissions
