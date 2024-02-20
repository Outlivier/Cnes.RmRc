#requires -version 7.4
<#
.SYNOPSIS
	Charge ou lance la console développeur.
.DESCRIPTION
	Les opérations effectuées sont les suivantes :

	- VERIFICATION VERSION ET X64

	La version est vérifiée par #requires, et x64 par la version vu que PowerShell Core en 32bits doit être installé spécifiquement.
	Dans le pire des cas le chargement du module de dev échouera (à cause de ProcessorArchitecture = 'Amd64' dans le psd1).

	- RELANCE LA CONSOLE en mode -NoExit

	Par défaut les scripts en PowerShell (via menu contextuel "Run with PowerShell 7" par exemple) sont lancés sans le commutateur -NoExit.
	(La console se ferme automatiquement à la fin de l'exécution).
	Pour l'ouverture en mode Console (exécution de console.ps1 ou d'un script voulant ouvrir la console développeur et afficher l'aide d'une commande)
	On relance la console PowerShell mode -NoExit avec les mêmes paramètres si :
	(L'environnement n'est pas déjà en -NoExit) et ((console.ps1 a été exécuté directement) ou ($HelpCommand n'est pas vide)).
	A noter que relancer la console via &pwsh n'ouvre pas une seconde fenêtre ce qui est pratique, notamment en cas d'utilisation
	de Windows Terminal, la nouvelle console sera dans le même terminal.

	- TRANSCRIPT

	Démarre un transcript dans "Mes Documents\PowerShell\Transcripts\<foldername>_2023-03-02_16h55m57_jeudi_ovw7lgx2.log".
	On utilise une variable globale `Transcript` pour éviter de démarrer plusieurs fois la transcription dans la même console.
	Les transcripts de plus de 5 jours sont automatiquement effacés.

	- CONFIGURATION DE LA CONSOLE

	Change les éléments suivants :
		- Titre : Ajoute dans le titre de la console le nom du dossier (qui correspond au nom du projet)
		- Couleurs : Passe les sorties Verbose et Debug en gris clair au lieu de jaune (que l'on réserve pour les Warnings).
		- InformationPreference : 'Continue' au lieu de 'SilentlyContinue' pour afficher la sortie de Write-Information.
		- ErrorActionPreference : 'Stop' au lieu de 'Continue' pour que toute erreur arrête l'exécution du script.
	A noter que les variables de préférence seront respectés dans le module de dev.

	- MODULES

		- Ajoute le path $env:PSModulePath_CU à $env:PSModulePath pour l'auto-loading des modules.
		  L'ordre est important, le chemin spécifique devant être prioritaire pour être sûr de la version chargée.
		- Charge les modules ShellCore et de dev.

	- PATH

		- PowerShell Drive dev: et nasdev:
		Pour faciliter la gestion des chemins, le module de dev crée un drive `dev:` sur le répertoire racine du projet, ainsi qu'une variable `$dev`
		pour les cas où les drive PowerShell sont mal supportés (ligne de commande non PowerShell par exemple).
		De même pour `nasdev:` et `$nasdev`.
		Les drives et variables sont dans le scope 'Global' pour pouvoir être utilisés partout.
		- Current location
		Certains programmes comme Visual Studio Code ou XYPlorer avec le menu contextuel 64 bits ne définissent pas
		le répertoire courant, ce qui peut poser problème lors de l'appel à la ligne de commande git.

	- PAUSE

	On enregistre automatiquement une pause pour éviter que la console se ferme sans que l'on puisse lire le résultat.
	Register-Pause gère lui-même si la console est en mode -NoExit (=> ne pas faire de pause) ou non (=> faire une pause)

	- HELP COMMAND

	Affichage de l'aide si paramètre HelpCommand.

.PARAMETER HelpCommand
	Nom de commande dont l'aide sera affichée automatiquement lors du chargement de la console.
.EXAMPLE
	PS> &".\console.ps1"

	Ouvre la console développeur en mode console interactive.
.EXAMPLE
	. "$PSScriptRoot\..\console.ps1"

	Charge la console développeur dans un script.
.EXAMPLE
	&"$PSScriptRoot\..\console.ps1" -HelpCommand ($MyInvocation.MyCommand.Name.Split(".")[0])

	Ouvre la console développeur en mode console interactive et affiche l'aide de la commande dont le script porte le nom.
	Par exemple si le script est nommé `Get-Item.console.ps1`, l'aide de la commande Get-Item sera affiché.
#>
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
param
(
	[string]$HelpCommand
)

#
# RELANCE LA CONSOLE
#
# Lecture du nom et du chemin d'accès du script appelant (null si aucun) et du nom de script
$callingScriptPath = $myinvocation.PSCommandPath
# Exécution dans VSCode ?
$isVSCode = ($host.Name -eq 'Visual Studio Code Host')
$relaunch = $false
if (!$callingScriptPath -or !!$HelpCommand)
{
	$relaunch = ([System.Environment]::GetCommandLineArgs() -NotContains "-NoExit")
}
$relaunch = $relaunch -and !$isVSCode
if ($relaunch)
{
	$prms = @{ Verbose = $Verbose }
	if ($HelpCommand) { $prms.Add("HelpCommand", $HelpCommand) }
	&pwsh.exe -NoExit -NoLogo -File ($myinvocation.PSCommandPath ?? $myinvocation.MyCommand.Definition) @prms
	exit 0
}


#
# TRANSCRIPT
#
if (!$global:Transcript)
{
	$projectName = $((Get-Item $PSScriptRoot).Name)
	$pTranscripts = "$([Environment]::GetFolderPath('MyDocuments'))\PowerShell\Transcripts"
	md $pTranscripts -Force | Out-Null
	# On conserve les fichiers 5 jours
	Get-ChildItem "$pTranscripts\$projectName*.log" | ? { $_.CreationTimeUtc -lt ((Get-Date).AddDays(-5)) } | % { Remove-Item -LiteralPath $_.FullName }
	# Démarre le transcript
	$shortHash =  -join ((48..57) + (97..122) | Get-Random -Count 8 | % {[char]$_})
	$global:Transcript = Join-Path $pTranscripts ("$($projectName)_{0:yyyy-MM-dd_HH\hmm\mss_dddd}_$shortHash.log" -f (Get-Date))
	Start-Transcript -LiteralPath $global:Transcript -IncludeInvocationHeader | Write-Verbose
}


#
# CONFIGURATION DE LA CONSOLE
#
# Titre
$title = " - $((Get-Item $PSScriptRoot).Name)"
if (!$host.UI.RawUI.WindowTitle.EndsWith($title)) { $host.UI.RawUI.WindowTitle += $title }

# Couleurs
$PSStyle.Formatting.Verbose = $PSStyle.Foreground.FromRgb(0x999999)
$PSStyle.Formatting.Debug   = $PSStyle.Foreground.FromRgb(0x999999)

# Préférences
$InformationPreference = 'Continue'
$ErrorActionPreference = 'Stop'


#
# MODULES
#
$pRoot = ($PSScriptRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)

# Ajoute le path "Modules_Isolated" à $env:PSModulePath pour l'auto-loading des modules.
$plib = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules_Isolated\Lab'
if (!(($env:PSModulePath).StartsWith($plib, 'OrdinalIgnoreCase'))) { $env:PSModulePath = $plib + ';' + $env:PSModulePath }

# Décharge les modules dont ont veut forcer le rechargement
@('dev') | % { Remove-Module $_ -Verbose:$false -ErrorAction SilentlyContinue -Force }

# Charge par défaut le module ShellCore et le module de Dev
Import-Module "$pRoot\build\.dev\shellcore\ShellCore.psd1" -Verbose:$false
Import-Module "$pRoot\build\.dev\dev.psd1"                 -Verbose:$false


#
# PATH
#
#
# CurrentLocation
if (-not (Get-Location).Path.ToUpperInvariant().Contains($pRoot.Substring(0, $pRoot.Length -1).ToUpperInvariant()))
{
	Write-Verbose "Le CurrentDirectory `"$((Get-Location).Path)`" n'est pas valide, utilisation de `"$pRoot`"..."
	Set-Location -Path $pRoot
}


#
# PAUSE
#
Register-Pause


#
# HELP COMMAND
#
if ($HelpCommand)
{
	Write-Host $HelpCommand -ForegroundColor DarkYellow
	$commandHelp = Get-Help $HelpCommand
	Write-Host $commandHelp.Synopsis         -ForegroundColor Cyan
	Write-Host $commandHelp.Description.Text -ForegroundColor DarkGray
	$commandHelp.Syntax
}


#
# NETTOYAGE
#
@('pRoot', 'pLib') | % { Remove-Variable -Name $_ -Force -ErrorAction SilentlyContinue }