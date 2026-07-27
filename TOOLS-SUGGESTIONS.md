# Suggestions d'amélioration et d'outillage

Ce document liste les améliorations recommandées pour industrialiser **Hybrid Identity Reporter**.

## Priorité 1 - Fiabilité du script

| Sujet | Recommandation | Bénéfice |
| --- | --- | --- |
| Tests PowerShell | Implémenté : tests Pester pour `Core`, `Export`, l'historique, les permissions et le mapping `Config/reports.json`. | Détecte les régressions avant livraison. |
| Validation projet | Utiliser `Tools\Test-HIRProject.ps1` hors GUI avant livraison. | Permet une vérification rapide en console ou CI. |
| Validation configuration | Implémenté partiellement : Health Check et `Tools\Test-HIRProject.ps1` valident `connections.json`, `appsettings.json`, `reports.json` et `planned-reports.json`. | Évite les erreurs silencieuses après modification de la configuration. |
| Logs | Implémenté : purge automatique selon `Logging.RetainDays`. | Évite l'accumulation de logs sur le serveur. |
| Exports | Ajouter une option d'ouverture automatique du fichier exporté après génération. | Améliore l'expérience opérateur. |

## Priorité 2 - Exploitation

| Sujet | Recommandation | Bénéfice |
| --- | --- | --- |
| Signature | Workflow prêt : `Tools\Sign-HIRScripts.ps1` utilise un certificat interne fourni par empreinte. | Compatible avec `AllSigned` et améliore la traçabilité. |
| Packaging | Implémenté : `Tools\Build-HIRPackage.ps1` génère une archive versionnée et un manifeste SHA-256. | Facilite le déploiement sur un serveur d'administration ou un poste d'audit. |
| Versioning | Afficher la version dans le README, l'interface et les exports. | Simplifie le support et les comparaisons de résultats. |
| Raccourci | Implémenté : `launch.bat` lance `Start-Hybrid-Identity-Reporter.ps1` en STA depuis le dossier courant. | Réduit les erreurs de lancement. |
| Dossier dédié | Exécuter depuis la racine du projet ou un chemin standard validé. | Stabilise les chemins d'exploitation. |
| Mode console | Implémenté : `Start-Hybrid-Identity-Reporter.ps1 -Console` affiche un résumé du projet et le health check sans ouvrir la GUI. | Permet une validation rapide en terminal ou en CI. |

## Priorité 3 - Sécurité

| Sujet | Recommandation | Bénéfice |
| --- | --- | --- |
| Permissions | Implémenté : configuration et affichage par rapport, avec `REPORT-PERMISSIONS.md`. | Réduit le besoin de comptes trop privilégiés. |
| Comptes admin | Privilégier un compte d'audit avec droits lecture seule. | Respect du moindre privilège. |
| Scopes Graph | Garder les scopes Graph limités aux rapports utilisés. | Limite l'exposition en cas de compromission. |
| Exports | Protéger le dossier `Reports` par ACL si les rapports contiennent des données sensibles. | Réduit le risque de fuite d'information. |
| Logs | Éviter d'écrire des secrets ou tokens dans les logs. | Bonne pratique sécurité. |

## Priorité 4 - Interface

| Sujet | Recommandation | Bénéfice |
| --- | --- | --- |
| Recherche rapport | Implémenté : zone de recherche dans la liste des rapports. | Accès plus rapide quand le catalogue grossit. |
| Filtre statut/risque | Implémenté : filtres `Implemented / Planned` et `Critical / High / Medium / Low`. | Sépare mieux les rapports exploitables, la roadmap et les risques. |
| Configuration planned | Implémenté : `Config\planned-reports.json` pilote la visibilité et les métadonnées des rapports prévus. | Permet d'adapter la roadmap sans modifier le catalogue principal. |
| Détails rapport | Implémenté dans la vue d'ensemble : source, permissions, prérequis, durée et finalité. | Aide l'utilisateur avant exécution. |
| Export rapide | Implémenté : bouton `Open Last Export`. | Accès direct au dernier fichier généré. |
| Health check visuel | Implémenté : synthèse dédiée et coloration des statuts dans le résultat du health check. | Fait ressortir plus vite les erreurs et avertissements. |
| Indicateur de charge | Implémenté : bandeau de chargement et barre de progression pendant les actions longues. | Rend l'interface plus lisible pendant les opérations lourdes. |
| Thème | Conserver un thème clair/sobre adapté aux outils d'administration. | Lisibilité en exploitation. |

## Priorité 5 - CI/CD et qualité

| Sujet | Recommandation | Bénéfice |
| --- | --- | --- |
| PSScriptAnalyzer | Implémenté dans la CI Windows. | Repère les erreurs de style et de robustesse. |
| Pester | Implémenté dans la CI Windows. | Sécurise les modules critiques. |
| Build local | Implémenté avec `Tools\Build-HIRPackage.ps1`. | Génère une archive propre avec uniquement les fichiers nécessaires. |
| Changelog | Maintenir `CHANGELOG.md`. | Traçabilité des versions. |
| Documentation | Garder `REPORTS-PAR-MENU.md` synchronisé avec `Config/reports.json`. | Évite la dérive documentaire. |

## Commandes de validation conseillées

```powershell
# Vérifier la syntaxe PowerShell
$files = Get-ChildItem -Recurse -Include *.ps1,*.psm1 -File
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw "Erreur PowerShell dans $($file.FullName): $($errors[0].Message)"
    }
}

# Vérifier les fichiers JSON
Get-Content .\Config\appsettings.json -Raw | ConvertFrom-Json | Out-Null
Get-Content .\Config\connections.json -Raw | ConvertFrom-Json | Out-Null
Get-Content .\Config\reports.json -Raw | ConvertFrom-Json | Out-Null

# Vérifier le chargement XAML
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
[xml]$xaml = Get-Content .\GUI\MainWindow.xaml -Raw
$reader = New-Object System.Xml.XmlNodeReader $xaml
[Windows.Markup.XamlReader]::Load($reader) | Out-Null

# Ou lancer la validation complète du projet
.\Tools\Test-HIRProject.ps1
```

## Améliorations futures de rapports

| Rapport | Menu cible | Priorité |
| --- | --- | --- |
| Utilisateurs sans MFA | Security / IAM | Haute |
| Permissions Full Access | Exchange Online | Haute, planifié dans le catalogue |
| Permissions Send As | Exchange Online | Haute, planifié dans le catalogue |
| Doublons UPN | Hybrid Reports | Moyenne, planifié dans le catalogue |
| Doublons proxyAddresses | Hybrid Reports | Moyenne, planifié dans le catalogue |
| Comptes AD expirés | Active Directory | Moyenne |
| Groupes sans owner | Entra ID | Moyenne |
| Licences inutilisées | Entra ID | Moyenne |
