<#
.SYNOPSIS
	Effectue certaines configurations de l'environnement de développement.
.DESCRIPTION
	* Demande et sauvegarde les paramètres utilisateurs spécifiques à cette machine.
#>
[CmdletBinding()]
param()
. "$PSScriptRoot\..\..\console.ps1"

# Demande et sauvegarde les paramètres utilisateurs spécifiques à cette machine.
# C'est un exemple montrant comment sauvegarder des paramètres non critiques dans un fichier .userconfig.
Write-Step "Settings"
$values = (Test-Path 'dev:\.userconfig') ? (gc 'dev:\.userconfig' -Raw | ConvertFrom-Json -AsHashtable) : @{}
$values['path'] = $values['path'] ?? @{}
# - Chemin MOWGLI
Write-Question "Chemin d'accès du répèrtoire MOWGLI dans lequel publier la solution ?"
Write-Question "Exemple : D:\dev\mowgli\src+\cnes.mowgli"
Write-Question "Taper entrée pour conserver la valeur existante : '$($values.path.mowgli)'"
$values.path['mowgli'] = Read-Host | % { !!$_ ? $_ : $values.path.mowgli }
# - Chemin MOWGLII
Write-Question "Chemin d'accès du répèrtoire MOWGLII dans lequel publier la solution ?"
Write-Question "Exemple : D:\dev\mowglii\sbd-client\src+\cnes.mowglii"
Write-Question "Taper entrée pour conserver la valeur existante : '$($values.path.mowglii)'"
$values.path['mowglii'] = Read-Host | % { !!$_ ? $_ : $values.path.mowglii }
# - Sauvegarde du fichier
$header = "// Paramètres spécifiques à ce PC.`n// Le fichier est gitignoré."
"$header`n$($values | ConvertTo-Json)" | Out-File 'dev:\.userconfig' -Force
Write-Result "Settings sauvegardés sur '$dev\.userconfig'."