#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CertificateThumbprint,
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop
if (-not $certificate.HasPrivateKey) { throw 'The selected code-signing certificate has no accessible private key.' }
if ($certificate.NotAfter -le (Get-Date)) { throw 'The selected code-signing certificate is expired.' }
if ($certificate.EnhancedKeyUsageList.ObjectId -notcontains '1.3.6.1.5.5.7.3.3') { throw 'The selected certificate is not valid for code signing.' }

$files = Get-ChildItem -LiteralPath $RootPath -Recurse -File -Include '*.ps1', '*.psm1' |
    Where-Object FullName -NotMatch '[\\/](Dist|Reports|Archive|Logs)[\\/]'
foreach ($file in $files) {
    if ($PSCmdlet.ShouldProcess($file.FullName, 'Authenticode sign')) {
        $signature = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $certificate -TimestampServer $TimestampServer -HashAlgorithm SHA256
        if ($signature.Status -ne 'Valid') { throw "Signing failed for '$($file.FullName)': $($signature.StatusMessage)" }
    }
}
"Signed $($files.Count) PowerShell files."
