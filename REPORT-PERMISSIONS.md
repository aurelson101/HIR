# Report permissions and prerequisites

HIR remains read-only. It does not require remediation permissions.

| Report family | Minimum access | Local or module prerequisite |
| --- | --- | --- |
| Active Directory | Authenticated directory read access | RSAT ActiveDirectory and domain controller connectivity |
| Entra users | `User.Read.All` | Microsoft.Graph.Users |
| Entra groups | `Group.Read.All`; owner resolution also uses `User.Read.All` | Microsoft.Graph.Groups |
| Entra admin roles | `RoleManagement.Read.Directory`, `Directory.Read.All` | Microsoft.Graph.Identity.DirectoryManagement |
| MFA registration | `Reports.Read.All` | Microsoft.Graph.Reports |
| Exchange inventories | View-Only Recipients or equivalent | ExchangeOnlineManagement |
| Exchange delegations | View-Only Recipients plus permission-entry read access | ExchangeOnlineManagement |
| Executive reports | Local read access to `Reports/History` | At least one prior HIR run; comparison requires two runs of one report |
| Exports | Local write access to `Reports` and `Archive` | ImportExcel only for `.xlsx` |

The application resolves these requirements for every catalog entry through `Config/report-permissions.json` and displays them when a report is selected. Overrides are defined for reports whose scopes differ from their category default.

Use dedicated read-only audit identities. Protect exported identity data using filesystem ACLs, access-controlled storage and an appropriate retention period. `Exports.ProtectReportsWithUserAcl` can restrict `Reports` to the current Windows user; enable it only after validating the intended operational account.
