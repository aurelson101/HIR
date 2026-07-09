Set-StrictMode -Version Latest

function Get-HIREntraAdminRoleMembers {
    [CmdletBinding()]
    param()

    Invoke-HIRSafeCommand -Module Entra -Action 'Admin role members report' -ScriptBlock {
        Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
        $roles = Get-MgDirectoryRole -All -ErrorAction Stop
        foreach ($role in $roles) {
            Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    RoleDisplayName = $role.DisplayName
                    MemberId        = $_.Id
                    MemberType      = $_.AdditionalProperties.'@odata.type'
                    DisplayName     = $_.AdditionalProperties.displayName
                    UserPrincipalName = $_.AdditionalProperties.userPrincipalName
                }
            }
        }
    }
}

Export-ModuleMember -Function Get-HIREntraAdminRoleMembers
