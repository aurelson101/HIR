# Changelog

## Unreleased

### Added

- Menu Active Directory : sous-groupes Users Review, Privileged Users Review et Groups & Computers Review (champ ReviewGroup du catalogue).
- Rapports Expired or Never Logged On AD Users et Old PasswordLastSet Users (365 jours).
- Rapports Extended Privileged AD Groups Members (groupes résolus par SID) et AD Groups Without managedBy.

### Fixed

- DisplayName toujours vide dans six rapports AD utilisateurs.
- Locked Users limité aux utilisateurs ; Inactive, Without Email et Without Manager limités aux comptes activés.
- Exports CSV/JSON/HTML/Excel et historique : les résultats vides ne provoquent plus d'erreur.
- Neutralisation des formules (=, +, -, @) dans les exports CSV et Excel.
- Remove-HIRExpiredFiles exige RetainDays (risque de purge totale si omis).
- Rapports Exchange Full Access / Send As : le filtre NT AUTHORITY\SELF ne fonctionnait pas ; un échec sur une boîte n'interrompt plus le rapport.
- DisplayName ajouté aux rapports hybrides ; comparaison d'exécutions en O(n).
- Empty AD Groups n'inclut plus les groupes dont les membres passent par primaryGroupID (ex. Domain Users).
- ACL de Reports : SYSTEM et Administrateurs conservent l'accès.
- Exchange Full Access / Send As : progression affichée, identifiant objet utilisé, Send As via Get-EXORecipientPermission (REST, plus rapide que PowerShell distant).

### Notes

- Send As nécessite ExchangeOnlineManagement 3.x (Get-EXORecipientPermission) ; non testé sur un tenant réel.

## 0.3.0 - 2026-07-27

### Added

- Persisted run history, snapshot comparison, explainable risk scores and executive HTML summaries.
- MFA registration, Entra group ownership, privileged password and Exchange delegation reports.
- JSON export, CSV metadata sidecars, report permission details and cancellable asynchronous execution.
- Pester tests, Windows CI, versioned packaging and internal Authenticode signing workflow.

### Changed

- Existing exports are moved to the archive instead of repeatedly copied.
- CSV exports are now conventional single-table files for Power BI, SIEM and automation.
- Export and archive retention/security settings are configurable.

## 0.2.0 - 2026-07-10

### Added

- Responsive WPF interface improvements with dashboard pie chart, report search, status filter, risk filter and `Show planned` toggle.
- `launch.bat` portable launcher for STA WPF startup.
- `Config/planned-reports.json` to control planned report visibility and metadata.
- Project validation script checks for JSON validity, XAML loading, module imports, catalog duplicates and planned report configuration IDs.
- `REPORTS-PAR-MENU.md` report catalog documentation.

### Changed

- Application name standardized to `Hybrid Identity Reporter`.
- Built-in AD privileged group lookup now supports localized domains by resolving Domain Admins with domain SID + RID 512.
- AD and hybrid report projections now tolerate missing properties returned by heterogeneous AD objects.
- Message boxes use typed WPF enums to avoid localized PowerShell argument conversion errors.
- Planned reports remain visible as an audit roadmap but are not executable by default.

### Fixed

- Startup `ShowDialog()` crash caused by WPF argument type conversion issues.
- `Domain Admins Members` failing on non-English Active Directory group names.
- Report catalog duplicate detection and missing function mapping validation.
- AD report errors when `UserPrincipalName` or other optional attributes are absent.
- Planned reports being selected as the default runnable report.

## 0.1.0 - Initial

- Initial read-only hybrid identity reporting GUI.
- Active Directory, Entra ID, Exchange Online, hybrid and export modules.
