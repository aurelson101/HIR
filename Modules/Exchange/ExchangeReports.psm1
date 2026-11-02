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
        $mailboxes = @(Get-EXOMailbox -ResultSize Unlimited -Properties PrimarySmtpAddress -ErrorAction Stop)
        $index = 0
        foreach ($mailbox in $mailboxes) {
            $index++
            if ($index % 25 -eq 1 -or $index -eq $mailboxes.Count) {
                Write-Progress -Activity 'Full Access permissions' -Status ('{0}/{1} mailboxes' -f $index, $mailboxes.Count) -PercentComplete ([int](100 * $index / [Math]::Max(1, $mailboxes.Count)))
            }
            & { try { Get-EXOMailboxPermission -Identity $mailbox.ExternalDirectoryObjectId -ErrorAction Stop } catch { Write-HIRLog -Module Exchange -Action 'Full Access mailbox permissions report' -Level WARNING -Message ('Skipped {0}: {1}' -f $mailbox.UserPrincipalName, $_.Exception.Message); return } } |
                Where-Object { -not $_.IsInherited -and $_.User -notlike 'NT AUTHORITY\SELF' -and $_.AccessRights -contains 'FullAccess' } |
                Select-Object @{Name = 'Mailbox'; Expression = { $mailbox.PrimarySmtpAddress }}, User, AccessRights, IsInherited, Deny
        }
        Write-Progress -Activity 'Full Access permissions' -Completed
    }
}

function Get-HIRExchangeSendAsPermissions {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Exchange -Action 'Send As permissions report' -ScriptBlock {
        $recipients = @(Get-EXORecipient -ResultSize Unlimited -Properties ExternalDirectoryObjectId, PrimarySmtpAddress -ErrorAction Stop)
        $index = 0
        foreach ($recipient in $recipients) {
            $index++
            if ($index % 25 -eq 1 -or $index -eq $recipients.Count) {
                Write-Progress -Activity 'Send As permissions' -Status ('{0}/{1} recipients' -f $index, $recipients.Count) -PercentComplete ([int](100 * $index / [Math]::Max(1, $recipients.Count)))
            }
            & { try { Get-EXORecipientPermission -Identity $recipient.ExternalDirectoryObjectId -ErrorAction Stop } catch { Write-HIRLog -Module Exchange -Action 'Send As permissions report' -Level WARNING -Message ('Skipped {0}: {1}' -f $recipient.PrimarySmtpAddress, $_.Exception.Message); return } } |
                Where-Object { -not $_.IsInherited -and $_.Trustee -notlike 'NT AUTHORITY\SELF' -and $_.AccessRights -contains 'SendAs' } |
                Select-Object @{Name = 'Recipient'; Expression = { $recipient.PrimarySmtpAddress }}, Trustee, AccessRights, IsInherited
        }
        Write-Progress -Activity 'Send As permissions' -Completed
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
