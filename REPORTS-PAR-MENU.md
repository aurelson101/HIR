# Rapports par menu - Hybrid Identity Reporter

Ce document liste les rapports disponibles dans chaque menu de l'application, avec une note courte pour comprendre leur usage.

## Statuts

| Statut | Description |
| --- | --- |
| Disponible | Rapport implémenté et exécutable depuis l'interface. |
| Prévu | Rapport visible dans le catalogue, mais pas encore exécutable. |
| Vue | Élément d'interface ou d'aide, pas un rapport technique. |

## Dashboard

| Élément | Statut | Note |
| --- | --- | --- |
| Camembert racine des menus | Vue | Vue d'accueil. Chaque tranche permet d'ouvrir directement un menu : Active Directory, Entra ID, Exchange Online, Hybrid Reports, Security / IAM, Exports, Settings ou Debug / Health. |
| Suggestions de navigation | Vue | Affiche les actions recommandées selon les menus disponibles. |

## Hybrid Reports

| Rapport | Statut | Note |
| --- | --- | --- |
| Disabled AD users still visible in GAL | Disponible | Identifie les utilisateurs AD désactivés qui peuvent encore être visibles dans les listes d'adresses Exchange. |
| AD users missing mailNickname | Disponible | Détecte les utilisateurs AD avec une adresse mail mais sans attribut `mailNickname`. |
| AD users missing proxyAddresses | Disponible | Détecte les utilisateurs AD avec une adresse mail mais sans attribut `proxyAddresses`. |
| Duplicate UPN | Prévu | Détection prévue des UPN en doublon dans l'environnement hybride. |
| Duplicate proxyAddresses | Prévu | Détection prévue des adresses proxy en doublon. |

## Active Directory

| Rapport | Statut | Note |
| --- | --- | --- |
| Disabled AD Users | Disponible | Liste les utilisateurs AD désactivés avec les attributs utiles pour le nettoyage. |
| Locked AD Users | Disponible | Liste les comptes AD verrouillés. |
| Inactive AD Users over 90 days | Disponible | Identifie les comptes utilisateurs inactifs selon le seuil configuré. |
| Users Without Email | Disponible | Identifie les utilisateurs sans attribut `mail`. |
| Users Without Manager | Disponible | Identifie les utilisateurs sans manager renseigné. |
| Inactive Computers over 90 days | Disponible | Identifie les objets ordinateurs inactifs. |
| Empty AD Groups | Disponible | Liste les groupes AD sans membre. |

## Entra ID

| Rapport | Statut | Note |
| --- | --- | --- |
| Cloud-only Entra users | Disponible | Liste les utilisateurs cloud-only non synchronisés depuis l'AD local. |
| Guest Entra users | Disponible | Liste les comptes invités B2B. |
| Synced Users | Disponible | Liste les utilisateurs synchronisés depuis l'AD local. |
| Disabled Entra Users | Disponible | Liste les utilisateurs désactivés dans Entra ID. |
| Licensed Users | Disponible | Liste les utilisateurs avec licences assignées. |
| Users Without License | Disponible | Liste les utilisateurs sans licence assignée. |
| Entra Groups | Disponible | Liste les groupes Entra avec les indicateurs mail, sécurité et type de groupe. |

## Exchange Online

| Rapport | Statut | Note |
| --- | --- | --- |
| Mailboxes with forwarding enabled | Disponible | Identifie les boîtes aux lettres avec une redirection configurée. |
| User Mailboxes | Disponible | Inventorie les boîtes aux lettres utilisateurs. |
| Shared Mailboxes | Disponible | Inventorie les boîtes aux lettres partagées. |
| Hidden From GAL | Disponible | Liste les destinataires masqués des listes d'adresses. |
| Full Access Mailbox Permissions | Prévu | Rapport prévu pour analyser les délégations Full Access. |
| Send As Permissions | Prévu | Rapport prévu pour analyser les permissions Send As. |

## Security / IAM

| Rapport | Statut | Note |
| --- | --- | --- |
| Password Never Expires | Disponible | Liste les comptes AD actifs dont le mot de passe n'expire jamais. |
| Domain Admins Members | Disponible | Liste les membres récursifs du groupe Domain Admins. |
| AdminCount = 1 Users | Disponible | Identifie les comptes AD avec `adminCount=1`. |
| Entra Admin Role Members | Disponible | Liste les membres des rôles administratifs Entra ID. |
| Users Without MFA Methods | Prévu | Rapport prévu pour identifier les utilisateurs sans méthode MFA enregistrée. |

## Exports

| Action | Statut | Note |
| --- | --- | --- |
| Export CSV | Disponible | Exporte les résultats courants au format CSV dans le dossier `Reports`. |
| Export Excel | Disponible | Exporte les résultats courants au format Excel. Nécessite le module `ImportExcel`. |
| Export HTML | Disponible | Exporte les résultats au format HTML via le modèle `Templates/report-template.html`. |
| Archivage des anciens rapports | Disponible | Archive les exports existants avant de générer un nouveau fichier du même type. |

## Settings

| Élément | Statut | Note |
| --- | --- | --- |
| Application settings | Vue | Paramètres runtime, logs et exports dans `Config/appsettings.json`. |
| Connection settings | Vue | Paramètres AD, Microsoft Graph et Exchange dans `Config/connections.json`. |
| Report catalog | Vue | Catalogue des rapports dans `Config/reports.json`. |

## Debug / Health

| Contrôle | Statut | Note |
| --- | --- | --- |
| PowerShell runtime | Disponible | Vérifie la version PowerShell et le mode STA requis par WPF. |
| TLS | Disponible | Vérifie l'activation de TLS 1.2. |
| Module presence | Disponible | Vérifie les modules ActiveDirectory, Microsoft Graph, ExchangeOnlineManagement et ImportExcel. |
| Project folders | Disponible | Vérifie les dossiers nécessaires au fonctionnement de l'outil. |
| JSON validation | Disponible | Valide les fichiers JSON de configuration. |
| Catalog function mapping | Disponible | Vérifie que les rapports disponibles pointent vers des fonctions PowerShell existantes. |
| Operational suggestions | Disponible | Affiche les suggestions de connexion et de diagnostic selon l'état courant. |
