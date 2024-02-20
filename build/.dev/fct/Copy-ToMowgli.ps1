<#
.SYNOPSIS
	Copie la solution Visual Studio dans MOWGLI ou MOWGLII et compile la DLL.
.DESCRIPTION
	Le chemin de destination doit avoir été saisi lors de l'initialisation du projet (Initialize-Environment.ps1).
.PARAMETER Target
	Projet cible dans lequel copier la solution ('mowgli' ou 'mowglii').
#>
function Copy-ToMowgli
{
	[CmdletBinding()]
	param
	(
        [Parameter(Position = 0, Mandatory)]
        [ValidateSet('mowgli', 'mowglii')]
        [string]$Target
	)

	# Charge et vérifie la configuration
	#- Le fichier existe
	$msg = "Utilisez le script 'Initialize-Environment.ps1' pour configurer les chemins."
	if (!(Test-Path 'dev:\.userconfig'))
	{
		Write-Error "Le fichier de configuration n'existe pas sur '$dev\.userconfig'.`n$msg" -ErrorAction Stop
	}
	#- La clé existe et n'est pas vide ?
	$config = (gc 'dev:\.userconfig' -Raw) | ConvertFrom-Json -AsHashtable
	if ((!($config.ContainsKey('path')) -or !($config.path.ContainsKey($Target))) -or [string]::IsNullOrWhiteSpace($config.path[$Target]))
	{
		Write-Error "Le chemin cible pour '$Target' n'a pas été configuré.`n$msg" -ErrorAction Stop
	}
	#- Le répertoire ne contient pas des données inattendues
	if (((gci $config.path[$Target] -ErrorAction ignore).count -gt 0) -and (!(Test-Path (Join-Path $config.path[$Target] 'Cnes.Rmrc.sln'))))
	{
		$msg = "Le chemin cible pour '$Target' ne contient pas de fichier 'Cnes.Rmrc.sln'." + `
			"`nVérifiez que le chemin '$($config.path[$Target])' est bien celui souhaité." + `
			"`nEffacer le répertoire pour que la copie puisse se faire."
		Write-Error $msg -ErrorAction Stop
	}

	# Robocopy en excluant les binaires
	$xf = @('*.user')
	$xd = @('.vs', '.out')
	Invoke-Robocopy -Source "$dev\src" -Destination $config.path[$Target] -IgnoreFiles $xf -IgnoreDirectories $xd -Mirror

	# Compilation en mode Release
	$targetSolution =  (Join-Path $config.path[$Target] 'Cnes.Rmrc.sln')
	Build-Solution $targetSolution 'Release' -v 2022

	# Fin
	Write-Result "Solution copiée et compilée en mode Release sur '$targetSolution'".
}
