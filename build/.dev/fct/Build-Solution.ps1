<#
.SYNOPSIS
	Compile une solution Visual Studio.
.DESCRIPTION
	Compile une solution Visual Studio en utilisant devenv.com en ligne de commande.
	Comme dans Visual Studio, la compilation est incrémentale, les projets ne sont pas recompilés s'ils n'ont pas
	étés modifiés depuis la dernière compilation dans la même configuration. Utiliser le commutateur `Force` pour forcer
	la recompilation.

	* On vérifie dans le .sln que la version inscrite correspond bien à la version de Visual Studio souhaitée,
	une erreur est levée dans le cas contraire.
	* Ou utilise l'outil vswhere.exe pour trouver le chemin d'installation de Visual Studio.
	Cet outil est installé dans `${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe` depuis Visual Studio 2017.
	* On utilise l'outil devenv.com pour la compilation et pas msbuild pour pouvoir faire des compilations incrémetales.
	L'inconvéniant est que la sortie dans la console est moins propre que msbuild, la compilation n'est pas détaillée
	et les warning et les erreurs ne sont pas colorés.
.PARAMETER Path
	Chemin d'accès au fichier .sln à compiler.
.PARAMETER Configuration
	Configuration dans laquelle compiler la solution, "Release", "Debug", etc.
.PARAMETER Version
	Version de Visual Studio à utiliser.
.PARAMETER Force
	Si ce switch est défini, la solution est nettoyée avant d'être compilée, ce qui force la recompilation
	même si aucun projet n'a été modifié depuis la dernière compilation.
.EXAMPLE
	PS> Build-Solution 'D:\dev\solution.sln' 'Release' -v 2022
#>
function Build-Solution
{
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "", Justification="Build est un verbe valide à partir de PowerShell 6.")]
	[CmdletBinding()]
	param
	(
		[Parameter(Position = 0, Mandatory, ValueFromPipeline)]
		[ValidateScript({ Test-Path $_ -PathType Leaf })]
		[string]$Path,

		[Parameter(Position = 1, Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Configuration,

		[Parameter(Mandatory)]
		[ValidateSet('2019', '2022')]
		[Alias('v')]
		[string]$Version,

		[switch]$Force
	)

	BEGIN
	{
		# N° de version Visual Studio à utiliser
		$versionYear = $version
		if ($versionYear -eq '2019') { $versionNum = '16.0'}
		if ($versionYear -eq '2022') { $versionNum = '17.0'}

		# Récupération du path devenv.com
		# Utilisation de vswhere pour retrouver le path
		$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
		if (!(Test-Path $vswhere))
		{
			Write-Error "L'utilitaire vswhere n'a pas été trouvé sur '$vswhere'."
			return
		}
		# Récupération du path Visual Studio correspondant à la version souhaitée
		$devencom = $null
		$versionRange = "[$versionNum,$(([version]$versionNum).Major + 1).0)" # exemple "[15.0,16.0)"
		$vsinstance = &$vswhere -latest -products * -requires Microsoft.Component.MSBuild -version $versionRange -Format json | ConvertFrom-Json
		if ($vsinstance.length -eq 0)
		{
			Write-Error "Version $versionRange de Visual Studio non trouvée, impossible de compiler le projet."
			return
		}
		Write-Result "Visual Studio $($vsinstance.installationVersion)"
		$devencom = join-path $vsinstance.installationPath "Common7\IDE\devenv.com"
	}
	PROCESS
	{
		if (!$devencom) { return }

		# On vérifie que la solution est bien dans le format de la version Visual Studio souhaitée
		$vsversion = ([Regex]'\d+\.\d+').Match((gc $Path | ? { $_ -match '^\s*VisualStudioVersion\s+=' })).Value
		if (([version]$vsversion).Major -ne ([version]$versionNum).Major)
		{
			Write-Error "La solution sur '$path' n'est pas au format Visual Studio $versionYear mais au format $vsversion."
			return
		}

		# Compilation
		if ($Force)
		{
			&$devencom $path /Clean $Configuration
		}
		&$devencom $path /Build $Configuration

		# Erreur
		if ($LASTEXITCODE -ne 0)
		{
			Write-Error "La solution '$path' comporte des erreurs."
		}
	}
}