# Rapports par menu - Hybrid Identity Reporter

Ce document est genere a partir de Config/reports.json et liste les rapports disponibles ou prevus dans chaque menu de l'application.

## Statuts

| Statut | Description |
| --- | --- |
| Disponible | Rapport implemente et executable depuis l'interface. |
| Prevu | Rapport visible dans le catalogue, mais pas encore executable. |
| Vue | Element d'interface ou d'aide, pas un rapport technique. |

## Dashboard

| Element | Statut | Note |
| --- | --- | --- |
| Camembert racine des menus | Vue | Vue d'accueil. Chaque tranche permet d'ouvrir directement un menu. |
| Recherche et filtres | Vue | Filtre les rapports par texte, statut et niveau de risque. |

## Executive Summary

| Rapport | Statut | Risque | Priorite | Note |
| --- | --- | --- | --- | --- |
| Compare Two Exports | Disponible | Low | Low | Compare the two latest completed snapshots for one report. |
| Executive Summary HTML | Disponible | Medium | Low | Explainable high-level summary based on persisted runs. |
| Report Risk Score | Disponible | Medium | Low | Findings multiplied by visible risk weights. |
| Run History | Disponible | Low | Low | Persisted run manifests and snapshots for tracking. |

## Hybrid Reports

| Rapport | Statut | Risque | Priorite | Note |
| --- | --- | --- | --- | --- |
| AD Objects Without Entra Match | Prevu | Medium | Medium | Planned sync gap report for AD objects with no matching Entra object. |
| AD users missing mailNickname | Disponible | Medium | Medium | Find mail-enabled AD users missing mailNickname. |
| AD users missing proxyAddresses | Disponible | Medium | Medium | Find mail-enabled AD users missing proxyAddresses. |
| Disabled AD users still visible in GAL | Disponible | High | High | Detect disabled AD users still visible or potentially visible in Exchange address lists. |
| Duplicate proxyAddresses | Prevu | High | Medium | Planned duplicate proxy address detection. |
| Duplicate UPN | Prevu | High | Medium | Planned duplicate UPN detection across hybrid identity sources. |

## Active Directory

Les rapports sont regroupes en sous-groupes de revue dans le menu (Users Review, Privileged Users Review, Groups & Computers Review). Les rapports privilegies restent aussi disponibles dans Security / IAM.

### Users Review

| Rapport | Statut | Risque | Priorite | Note |
| --- | --- | --- | --- | --- |
| Disabled AD Users | Disponible | High | High | Review disabled AD users and mailbox-related attributes for lifecycle cleanup. |
| Expired or Never Logged On AD Users | Disponible | High | High | Enabled accounts that are expired or have never logged on. |
| Inactive AD Users over 90 days | Disponible | Medium | High | Find stale user accounts based on inactivity threshold. |
| Locked AD Users | Disponible | Medium | Medium | Review locked accounts for helpdesk and security signals. |
| Old PasswordLastSet Users | Disponible | Medium | High | Enabled accounts whose password has not been changed for over 365 days. |
| Users Without Email | Disponible | Low | Low | Improve AD data quality for mail-enabled identity workflows. |
| Users Without Manager | Disponible | Low | Low | Improve directory governance and ownership data. |

### Privileged Users Review

| Rapport | Statut | Risque | Priorite | Note |
| --- | --- | --- | --- | --- |
| Admin Accounts Password Never Expires | Disponible | Critical | High | Find enabled adminCount accounts with non-expiring passwords. |
| AdminCount = 1 Users | Disponible | High | High | Find accounts protected by AdminSDHolder history or privileged membership. |
| Domain Admins Members | Disponible | Critical | High | Review recursive Domain Admins membership. |
| Extended Privileged AD Groups Members | Disponible | Critical | High | Recursive members of Enterprise/Schema Admins, Administrators, Operators and other privileged groups (resolved by SID). |
| Password Never Expires | Disponible | High | High | Identify enabled accounts with passwords that never expire. |

### Groups & Computers Review

| Rapport | Statut | Risque | Priorite | Note |
| --- | --- | --- | --- | --- |
| AD Groups Without managedBy | Disponible | Medium | Medium | AD groups without a managedBy owner, excluding built-in groups. |
| Empty AD Groups | Disponible | Low | Low | Find groups without members for cleanup review. |
| Inactive Computers over 90 days | Disponible | Medium | Medium | Find stale computer objects for inventory cleanup. |

## Entra ID

| Rapport | Statut | Risque | Priorite | Note |
| --- | --- | --- | --- | --- |
| Cloud-only Entra users | Disponible | Medium | Medium | Review cloud-only member users and identity source of authority. |
| Disabled Entra Users | Disponible | Medium | Medium | Review disabled Entra users for lifecycle and licensing cleanup. |
| Disabled Users With Licenses | Prevu | Medium | Medium | Planned cross-check between Disabled Entra Users and Licensed Users to identify wasted licenses. |
| Entra Groups | Disponible | Medium | Medium | Inventory Entra groups, mail/security flags and group types. |
| Entra Groups Without Owners | Disponible | Medium | Medium | Find groups without an accountable owner. |
| Guest Entra users | Disponible | Medium | Medium | Review external guest accounts and lifecycle state. |
| Licensed Users | Disponible | Low | Low | Inventory licensed users and license count. |
| Synced Users | Disponible | Low | Low | Inventory synchronized Entra users. |
| Users Without License | Disponible | Low | Low | Review users without assigned licenses. |

## Exchange Online

| Rapport | Statut | Risque | Priorite | Note |
| --- | --- | --- | --- | --- |
| External Mail Forwarding | Prevu | High | High | Planned refinement of Mailboxes with forwarding enabled, isolating external forwarding from internal forwarding. |
| Full Access Mailbox Permissions | Disponible | High | High | Review explicit Full Access delegations. |
| Hidden From GAL | Disponible | Medium | Medium | Review recipients hidden from address lists. |
| Hidden From GAL But Active | Prevu | Medium | Medium | Planned refinement of Hidden From GAL, focused on active recipients that may need policy review. |
| Mailboxes with forwarding enabled | Disponible | High | High | Review mailbox forwarding and business justification. |
| Send As Permissions | Disponible | High | High | Review explicit Send As delegations. |
| Send On Behalf Permissions | Disponible | High | High | Review Send on Behalf delegations. |
| Shared Mailboxes | Disponible | Medium | Medium | Inventory shared mailboxes for ownership review. |
| Shared Mailboxes With Enabled Account | Prevu | Medium | Medium | Planned refinement of Shared Mailboxes, checking whether the backing sign-in account is enabled. |
| User Mailboxes | Disponible | Low | Low | Inventory Exchange Online user mailboxes. |

## Security / IAM

| Rapport | Statut | Risque | Priorite | Note |
| --- | --- | --- | --- | --- |
| Admin Accounts Password Never Expires | Disponible | Critical | High | Enabled adminCount accounts with non-expiring passwords. |
| AdminCount = 1 Users | Disponible | High | High | Find accounts protected by AdminSDHolder history or privileged membership. |
| Cloud-only Entra Admins | Prevu | High | Medium | Planned cross-check between Cloud-only Entra users and Entra admin role membership. |
| Domain Admins Members | Disponible | Critical | High | Review recursive Domain Admins membership. |
| Entra Admin Role Members | Disponible | Critical | High | Review privileged Entra role membership. |
| Extended Privileged AD Groups Members | Disponible | Critical | High | Recursive members of Enterprise/Schema Admins, Administrators, Operators and other privileged groups (resolved by SID). |
| Guest Users in Admin Roles | Prevu | Critical | Medium | Planned cross-check between Guest Entra users and Entra admin role membership. |
| Password Never Expires | Disponible | High | High | Identify enabled accounts with passwords that never expire. |
| Privileged Entra role risk view | Prevu | Critical | High | Planned risk view extending Entra Admin Role Members with critical role, guest account and cloud-only admin signals. |
| Users Without MFA Methods | Disponible | Critical | High | Graph authentication registration details without MFA registration. |

## Exports

| Rapport | Statut | Risque | Priorite | Note |
| --- | --- | --- | --- | --- |
| Export JSON | Disponible | Low | Low | Structured JSON export for SIEM or automation integration. |

## Settings

| Element | Statut | Note |
| --- | --- | --- |
| Application settings | Vue | Parametres runtime, logs et exports dans `Config/appsettings.json`. |
| Connection settings | Vue | Parametres AD, Graph et Exchange dans `Config/connections.json`. |
| Report catalog | Vue | Catalogue des rapports dans `Config/reports.json`. |
| Planned reports settings | Vue | Visibilite et metadonnees des rapports planned dans `Config/planned-reports.json`. |

## Debug / Health

| Controle | Statut | Note |
| --- | --- | --- |
| PowerShell runtime | Disponible | Verifie la version PowerShell et le mode STA requis par WPF. |
| TLS 1.2 | Disponible | Verifie activation TLS 1.2 pour PowerShell Gallery. |
| Modules PowerShell | Disponible | Verifie les modules ActiveDirectory, Microsoft Graph, ExchangeOnlineManagement et ImportExcel. |
| Dossiers projet | Disponible | Verifie les dossiers Config, Reports, Logs, Archive et Templates. |
| Validation JSON | Disponible | Valide les fichiers de configuration JSON. |
| Mapping catalogue / fonctions | Disponible | Verifie les doublons, les metadonnees et les fonctions associees aux rapports. |
| Permissions par rapport | Disponible | Valide et affiche les droits minimaux, prerequis et sources. |
