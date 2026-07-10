# Suggestions d'amélioration et d'outillage

Ce document liste les améliorations recommandées pour industrialiser **Hybrid Identity Reporter**.

## Priorité 1 - Fiabilité du script

| Sujet | Recommandation | Bénéfice |
| --- | --- | --- |
| Tests PowerShell | Ajouter des tests Pester pour les modules `Core`, `Export` et le mapping `Config/reports.json`. | Détecte les régressions avant livraison. |
| Validation du catalogue | Créer une commande `Test-HIRCatalog` réutilisable hors GUI. | Permet une vérification rapide en console ou CI. |
| Validation configuration | Ajouter un schéma JSON ou une validation stricte des clés attendues. | Évite les erreurs silencieuses après modification de `connections.json` ou `appsettings.json`. |
| Logs | Ajouter une rotation automatique selon `Logging.RetainDays`. | Évite l'accumulation de logs sur le serveur. |
| Exports | Ajouter une option d'ouverture automatique du fichier exporté après génération. | Améliore l'expérience opérateur. |

## Priorité 2 - Exploitation

| Sujet | Recommandation | Bénéfice |
| --- | --- | --- |
| Signature | Signer les scripts PowerShell avec un certificat interne. | Compatible avec `AllSigned` et améliore la traçabilité. |
| Packaging | Fournir une archive versionnée `Hybrid-Identity-Reporter-x.y.z.zip`. | Facilite le déploiement sur `DC05` ou autre serveur d'administration. |
| Versioning | Afficher la version dans le README, l'interface et les exports. | Simplifie le support et les comparaisons de résultats. |
| Raccourci | Créer un raccourci `.lnk` ou un lanceur `.cmd` vers `Start-Hybrid-Identity-Reporter.ps1`. | Réduit les erreurs de lancement. |
| Dossier dédié | Exécuter depuis `C:\dev\repportAD` ou un chemin standard validé. | Stabilise les chemins d'exploitation. |

## Priorité 3 - Sécurité

| Sujet | Recommandation | Bénéfice |
| --- | --- | --- |
| Permissions | Documenter les droits minimaux AD, Graph et Exchange requis. | Réduit le besoin de comptes trop privilégiés. |
| Comptes admin | Privilégier un compte d'audit avec droits lecture seule. | Respect du moindre privilège. |
| Scopes Graph | Garder les scopes Graph limités aux rapports utilisés. | Limite l'exposition en cas de compromission. |
| Exports | Protéger le dossier `Reports` par ACL si les rapports contiennent des données sensibles. | Réduit le risque de fuite d'information. |
| Logs | Éviter d'écrire des secrets ou tokens dans les logs. | Bonne pratique sécurité. |

## Priorité 4 - Interface

| Sujet | Recommandation | Bénéfice |
| --- | --- | --- |
| Recherche rapport | Ajouter une zone de recherche dans la liste des rapports. | Accès plus rapide quand le catalogue grossit. |
| Filtre statut | Ajouter un filtre `Disponible / Prévu`. | Sépare mieux les rapports exploitables et la roadmap. |
| Détails rapport | Ajouter un panneau de détail avec prérequis et description du rapport sélectionné. | Aide l'utilisateur avant exécution. |
| Export rapide | Ajouter un bouton `Open last export`. | Accès direct au dernier fichier généré. |
| Thème | Conserver un thème clair/sobre adapté aux outils d'administration. | Lisibilité en exploitation. |

## Priorité 5 - CI/CD et qualité

| Sujet | Recommandation | Bénéfice |
| --- | --- | --- |
| PSScriptAnalyzer | Exécuter `Invoke-ScriptAnalyzer` sur les `.ps1` et `.psm1`. | Repère les erreurs de style et de robustesse. |
| Pester | Exécuter les tests unitaires à chaque modification. | Sécurise les modules critiques. |
| Build local | Ajouter un script `Build-HIRPackage.ps1`. | Génère une archive propre avec uniquement les fichiers nécessaires. |
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
```

## Améliorations futures de rapports

| Rapport | Menu cible | Priorité |
| --- | --- | --- |
| Utilisateurs sans MFA | Security / IAM | Haute |
| Permissions Full Access | Exchange Online | Haute |
| Permissions Send As | Exchange Online | Haute |
| Doublons UPN | Hybrid Reports | Moyenne |
| Doublons proxyAddresses | Hybrid Reports | Moyenne |
| Comptes AD expirés | Active Directory | Moyenne |
| Groupes sans owner | Entra ID | Moyenne |
| Licences inutilisées | Entra ID | Moyenne |
