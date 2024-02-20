#------------------------------------------------------------------------------
#region INITIALISATION
#------------------------------------------------------------------------------
# Variables Publiques
#- Database : $dbnull
if (Test-Path "variable:global:dbnull")
{
	if ($dbnull -ne [System.DBNull]::Value)
	{
		Write-Error "Une variable 'dbnull' existe déjà et a une valeur différente de [System.DBNull]::Value." -Category WriteError -ErrorId "DBNullValue"
	}
}
else
{
	# `$dbnull` est plus court et simple à utiliser que [System.DBNull]::Value.
	# On définit la variable en global pour en faire une constante, si on fait une constante que l'on exporte, on ne peut pas
	# décharger le module sans faire `-Force` (cf. wiki).
	New-Variable -Scope Global -Option Constant -Force -Name dbnull -Value ([System.DBNull]::Value)
}

# Variables Privées
#- Couleurs pour la console
$script:ShellCoreStyle = [PSCustomObject]@{
	ResultForegroundColor         = [System.ConsoleColor]::Green
	StepSeparatorCharacter        = '─'
	StepSeparatorWidth            = 80
	StepSeparatorForegroundColor  = [System.ConsoleColor]::DarkCyan
	StepForegroundColor           = [System.ConsoleColor]::DarkCyan
	QuestionForegroundColor       = [System.ConsoleColor]::Cyan
}
#endregion INITIALISATION




#————————————————————————————————————————————————————————————————————————————————————————
#region FCT-DATABASE
#————————————————————————————————————————————————————————————————————————————————————————
<#
.SYNOPSIS
	Détermine si la valeur est égale à DBNull.
.DESCRIPTION
	Détermine si la valeur est égale à [System.DBNull]::Value.
	Est plus court à utiliser que [System.DBNull]::Value.Equals($myVar), et permet d'éviter de faire l'erreur de comparaison
	suivante : $true -eq [System.DBNull]::Value qui renvoie $true.
.OUTPUTS
	$true si la valeur est égale à [System.DBNull]::Value, $false sinon.
.FUNCTIONALITY
	Database
.NOTES
	Voir aussi la variable globale $global:dbnull.
.EXAMPLE
	PS> 1 | isdbnull
	False
#>
filter isdbnull
{
	$dbnull.Equals($_)
}

#endregion FCT-DATABASE

#————————————————————————————————————————————————————————————————————————————————————————
#region FCT-DEPENDENCY
#————————————————————————————————————————————————————————————————————————————————————————
<#
.SYNOPSIS
	Restaure les dépendances listés le fichier des dépendances.
.DESCRIPTION
	La façon de restaurer dépendant du type de dépendance.
	Les dependances à restaurer peuvent être filtrée par identifiant.
.PARAMETER Path
	Chemin d'accès au fichier listant les dépendances. ".\.require.xml" par défaut.
.PARAMETER Id
	Identifiant de la dépendance à restaurer. Si il n'est pas défini, toutes les dépendances seront restaurées.
	La valeur est lue comme une expression régulière.
.EXAMPLE
	PS> Install-Dependency

	Restaure toutes les dépendances.
.EXAMPLE
	PS> Install-Dependency "D:\.req.xml" -Id "ShellCore.*"

	Restaure toutes les dépendances dont l'identifiant commençe par "ShellCore",
	en précisant le chemin d'accès au fichier.
#>
function Install-Dependency
{
	[CmdletBinding()]
	param
	(
		[Parameter()]
		[string]$Path = ".\.require.xml",

		[Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string]$Id = ".*"
	)

	PROCESS
	{
		$Id | Out-Null # Evite un faux positif PSReviewUnusedParameter de l'analyze de code

		# Le fichier de dépendance doit exister
		# On n'utilise pas Resolve-Path car cette cmdlet lève une erreur si le path n'existe pas
		# On utilise un chemin complet pour que l'erreur en cas de fichier non trouvé soit très explicite
		$Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
		if (!(Test-Path $Path))
		{
			throw New-Object System.IO.FileNotFoundException("Le fichier de dépendances n'a pas été trouvé sur '$Path'.")
		}

		# Le root est le dossier contenant le fichier de dépendances
		$rootPath = Split-Path $Path -Parent

		# Pour chaque noeud matchant l'ID, on appelle le gestionnaire correspondant
		foreach ($node in ([xml](Get-Content $path)).items.ChildNodes | ? { $_ -is [System.Xml.XmlElement] } | ? { $_.id -match $Id })
		{
			."Install-$($node.Name)Dependency" -Node $node -RootPath $rootPath
		}
	}
}
<#
.SYNOPSIS
	Fonction privée de téléchargement d'une dépendance de type fichier.
.PARAMETER Node
	Noeud XML de ce fichier de dépendance.
.PARAMETER RootPath
	Chemin d'accès au dossier contenant le fichier de dépendances. Les chemins relatifs le sont par rapport à ce dossier.
#>
function Install-FileDependency
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[object]$Node,

		[Parameter(Mandatory)]
		[string]$RootPath
	)

	Write-Verbose "Fichier '$($Node.id)'..."

	# Fonction de résolution d'un chemin qui peut être relatif ou non au paramètre RootPath
	function ResolvePathIfRelative([string]$Path)
	{
		[System.IO.Path]::IsPathFullyQualified($Path) ? $Path : $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $RootPath $Path))
	}

	# Récupère le chemin d'accès 7-Zip
	# L'installation de 7-Zip est un pré-requis
	# L'erreur est géré plus bas, uniquement si on doit décompresser un fichier 7z
	$p7zip = Get-ItemPropertyValue -Path "Registry::HKCU\SOFTWARE\7-Zip" -Name "Path64" -ErrorAction SilentlyContinue
	if ($p7zip) { $p7zip = Join-Path $p7zip "7z.exe" }
	$supportedArchives = @(".7z", ".zip")

	# Transforme la destination en chemin absolu
	$pDestination = ResolvePathIfRelative -Path $Node.destination

	# Si la destination existe, on considère que c'est OK, sauf si c'est un répertoire vide
	$exists = (Test-Path $pDestination) -and `
	          !(((gi $pDestination) -is [System.IO.DirectoryInfo]) -and !(gci $pDestination -Force | Select -First 1))
	if ($exists)
	{
		Write-Host "Fichier $($Node.id) déjà installé sur '$pDestination'."
	}
	else
	{
		Write-Host "Copie du fichier $($Node.id) sur '$pDestination'..."

		# Est-ce une archive ?
		# Split('?') permet de gérer les querystring dans les URL
		$ext = [System.IO.Path]::GetExtension(($Node.path ?? ($Node.url ?? "").Split('?')[0]))
		$isArchive = $supportedArchives -contains $ext

		# Création du répertoire si nécessaire
		md ($isArchive ? $pDestination : (Split-Path $pDestination -Parent)) -Force | Out-Null

		# Si la source du fichier est une URL, on télécharge d'abord le fichier vers la destination, sinon on copie le fichier
		if ($Node.url)
		{
			Write-Verbose "Téléchargement de $($Node.url)..."
			$pOutFile = !$isArchive ? $pDestination : (Join-Path $pDestination "_$([guid]::NewGuid())$ext") # Génère un nom de fichier random pour l'archive
			Invoke-WebRequest -Uri $Node.url -OutFile $pOutFile
		}
		else
		{
			$pSrc = ResolvePathIfRelative -RootPath $RootPath -Path $Node.path
			Copy-Item -LiteralPath $pSrc -Destination $pDestination -Force
		}

		# Décompresse l'archive
		if ($isArchive)
		{
			$pArchive = (Resolve-Path (Join-Path $pDestination "*$ext")).Path
			switch ($ext)
			{
				".7z"
				{
					if (!$p7zip -or !(Test-Path $p7zip)) { throw New-Object System.IO.FileNotFoundException("7-Zip n'a pas été installé sur cet ordinateur.") }
					Expand-7ZipDependency -Path $pArchive -DestinationPath $pDestination -Exclude ($node.exclude.pattern)
					Remove-Item $pArchive -Force
				}
				".zip"
				{
					Expand-Archive -Path $pArchive -DestinationPath $pDestination -Force
					Remove-Item $pArchive -Force
				}
			}
		}
	}
}
<#
.SYNOPSIS
	Fonction privée de téléchargement d'une dépendance de type module PowerShell.
.PARAMETER Node
	Noeud XML de ce fichier de dépendance.
.PARAMETER RootPath
	Chemin d'accès au dossier contenant le fichier de dépendances. Les chemins relatifs le sont par rapport à ce dossier.
#>
function Install-PwshDependency
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[object]$Node,

		[Parameter(Mandatory)]
		[string]$RootPath
	)

	Write-Verbose "Module PowerShell $($Node.id)..."

	# Fonction de résolution d'un chemin qui peut être relatif ou non au paramètre RootPath
	function ResolveStringPath([string]$Path)
	{
		$Path = $ExecutionContext.InvokeCommand.ExpandString($Path)
		[System.IO.Path]::IsPathFullyQualified($Path) ? $Path : $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $RootPath $Path))
	}

	# Création du sous-dossier si nécessaire
	$pDestination = ResolveStringPath -RootPath $RootPath -Path $Node.Destination
	md $pDestination -Force | Out-Null

	# Si la version exacte existe déjà on ne fait rien,
	# sinon on efface le dossier du module (afin de ne pas laisser trainer d'ancienne versions) et on l'installe
	$currentModule = ""
	$envbackup = $env:PSModulePath
	try
	{
		$currentModule = &{
			$env:PSModulePath = $pDestination; Get-Module $Node.Id -ListAvailable | ? { "$($_.Version)$($_.PrivateData.PSData.Prerelease)" -eq $Node.version }
		}
	}
	finally
	{
		$env:PSModulePath = $envbackup
	}
	if (!$currentModule)
	{
		Write-Host "Installation locale du module PowerShell $($Node.id) v$($Node.version) sur '$pDestination'..."
		# Supression des éventuelles anciennes version
		$currentModuleDirectory = Join-Path $pDestination $Node.id
		if (($Node.uninstall -ne 'false') -and (Test-Path $currentModuleDirectory)) { Remove-Item $currentModuleDirectory -Recurse -Force }
		# Installation. Ici la version est exacte donc on force AllowPrerelease
		Save-Module -Name $Node.Id -RequiredVersion $Node.version -Path $pDestination -AllowPrerelease
	}
	else
	{
		Write-Host "Module PowerShell $($Node.id) v$($Node.version) déjà installé."
	}
}
<#
.SYNOPSIS
	Recherche les mises à jour disponibles.
.DESCRIPTION
	La recherche des mises à jour n'est possible qu'en fonction du type de dépendance.
	La recherche peut être filtrée par identifiant.

	Pour rechercher des nouvelles versions sans les installer, utiliser `-WhatIf` (la commande supporte ShouldProcess).
.PARAMETER Path
	Chemin d'accès au fichier listant les dépendances. ".\.require.xml" par défaut.
.PARAMETER Id
	Identifiant de la dépendance à restaurer. Si il n'est pas défini, toutes les dépendances seront restaurées.
	La valeur est lue comme une expression régulière.
.EXAMPLE
	PS> Update-Dependency

	Recherche toutes les mises à jour et les installe.
.EXAMPLE
	PS> Find-Dependency "D:\.req.xml" -Id "ShellCore.*" -WhatIf

	Recherche les mises à jour de toutes les dépendances dont l'identifiant commençe par "ShellCore",
	en précisant le chemin d'accès au fichier. Si des mises à jour sont trouvées, elles ne seront pas installées.
#>
function Update-Dependency
{
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
	param
	(
		[Parameter()]
		[string]$Path = '.\.require.xml',

		[Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string]$Id = ".*"
	)

	PROCESS
	{
		$Id | Out-Null # Evite un faux positif PSReviewUnusedParameter de l'analyze de code

		# Le fichier de dépendance doit exister
		$Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
		if (!(Test-Path $Path))
		{
			throw New-Object System.IO.FileNotFoundException("Le fichier de dépendances n'a pas été trouvé sur '$Path'.")
		}

		# Le root est le dossier contenant le fichier de dépendances
		$rootPath = Split-Path $Path -Parent

		# Pour chaque noeud matchant l'ID, on appelle le gestionnaire correspondant
		$xml = [xml](Get-Content $Path -Raw)
		$updatedNodes = @()
		foreach ($node in $xml.items.ChildNodes | ? { $_ -is [System.Xml.XmlElement] } | ? { $_.id -match $Id })
		{
			if (."Update-$($node.Name)Dependency" -Node $node -RootPath $rootPath)
			{
				$updatedNodes += $node
			}
		}

		# Sauvegarde du fichier xml
		# On utilise une expression régulière pour ne pas toucher au formatage
		# (PreserveWhiteSpace ne conserve pas l'alignement des attributs).
		# Le résultat pourra tout de même être décalé en fonction du n° de version
		if ($updatedNodes.length -gt 0)
		{
			$content = Get-Content $Path -Raw
			if ($PSCmdlet.ShouldProcess('Dépendances', 'Mise à jour'))
			{
				foreach ($node in $updatedNodes)
				{
					# Obtient la ligne à mettre à jour
					# (?s) : Single line
					$line = $content | Select-String "(?s)<$($node.Name)[^>]+?>" -AllMatches | % Matches | % Value | ? { $_ -match "id\s*=\s*['`"]$([regex]::Escape($node.id))\b['`"]" }
					# Modifie la ligne avec le nouveau n° de version
					$newLine = $line -Replace "(version\s*=\s*['`"])$(([xml]$line)."$($node.Name)".Version)(['`"])", ('${1}' + $node.version + '${2}')
					# Remplace le contenu
					$content = $content.Replace($line, $newLine)
					$content | Out-File $Path -Encoding utf8BOM -Force -NoNewline
					# Lance la restoration
					Install-Dependency -Path $Path -Id $node.id
				}
			}
			else
			{
				$depFilename = Split-Path $Path -Leaf
				foreach ($node in $updatedNodes)
				{
					Write-Host "What if: Mise à jour de $($node.id)  dans le fichier '$depFilename'..."
				}
				Write-Host "What if: Restauration des dépendances..."
			}
		}
		else
		{
			Write-Host 'Aucune mise à jour trouvée.'
		}
	}
}
function Update-FileDependency
{
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSReviewUnusedParameter", "", Justification="Les paramètres ne sont pas utilisés")]
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "", Justification="Pris en charge par l'appelant.")]
	[CmdletBinding()]
	[OutputType([bool])]
	param
	(
		[Parameter(Mandatory)]
		[System.Xml.XmlElement]$Node,

		[Parameter(Mandatory)]
		[string]$RootPath
	)

	Write-Host "Fichier $($Node.id) : La recherche de nouvelle version n'est pas disponible pour les fichiers."
	$false
}
function Update-PwshDependency
{
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "", Justification="Pris en charge par l'appelant.")]
	[CmdletBinding()]
	[OutputType([bool])]
	param
	(
		[Parameter(Mandatory)]
		[object]$Node,

		[Parameter(Mandatory)]
		[string]$RootPath
	)

	$RootPath | Out-Null # Evite PSReviewUnusedParameter sur ce paramètre qui n'est pas utilisé sans désactiver la règle pour le fichier

	Write-Verbose "Module PowerShell $($Node.id)..."
	$output = $false

	$allowPrerelease = $Node.allowPrerelease -eq [bool]::TrueString
	$version = (Find-Module -Name $Node.id -MinimumVersion $Node.Version -AllowPrerelease:$allowPrerelease).Version
	if ($version -ne $Node.version)
	{
		Write-Host "Module PowerShell $($Node.id) : Nouvelle version $version disponible." -ForegroundColor Green
		$Node.version = $version
		$output = $true
	}
	$output
}

#endregion FCT-DEPENDENCY

#————————————————————————————————————————————————————————————————————————————————————————
#region FCT-FILE
#————————————————————————————————————————————————————————————————————————————————————————
<#
.SYNOPSIS
	Crée une nouvelle archive .7z à l'aide de la ligne de commande 7-Zip.
.DESCRIPTION
	7-Zip doit avoir été installé, sinon le chemin d'accès à `7z.exe` doit être passé en argument.

	La méthode de compression utilisée est LZMA2.
.PARAMETER Source
	Chemin d'accès des éléments à compresser.
	Les caractères génériques sont acceptés.
	Attention cependant, sont acceptés les caractères génériques tels que définis par 7-Zip
	(cf. (Command Line Syntax)[https://sevenzip.osdn.jp/chm/cmdline/syntax.htm]).
	L'ensemble de ces caractères et leur signification sont différents de la norme PowerShell
	(cf. (about wildcards)[https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_wildcards]).
.PARAMETER Destination
	Chemin d'accès de l'archive à créer.
	Si l'archive existe déjà, elle sera supprimée.
	L'extension de fichier doit obligatoirement être .7z (c'est une limitation imposée par 7-Zip).
	Si l'arborescence de destination n'existe pas, elle sera créée.
.PARAMETER Level
	Niveau de Compression :
		* Copy     <=> -mx0
		* Fastest  <=> -mx1
		* Fast     <=> -mx3
		* Normal   <=> -mx5 (Valeur par défaut)
		* Maximum  <=> -mx7
		* Ultra    <=> -mx9
.PARAMETER Exclude
	Exclu de la compression la liste des éléments.
	* Le paramètre s'applique indifféremment aux répertoires ou fichiers.
	* La paramètre s'applique de manière récursive, SAUF s'il commence par le caractère de séparation de dossier (\ sur Windows).
	* Les mêmes caractères génériques que pour le paramètre `Source` sont acceptés.
.PARAMETER RemoveSource
	Si défini, la source sera supprimée après la compression.
.PARAMETER Priority
	Permet de changer la priorité du processus du programme de compression.
	Voir la documentation (ProcessPriorityClass Enum)[https://docs.microsoft.com/fr-fr/dotnet/api/system.diagnostics.processpriorityclass]
	pour la liste des valeurs possibles.
	La valeur par défaut est "Normal".
.PARAMETER ThreadingOff
	N'autorise pas le multithreading pour ne s'exécuter que sur un seul cœur.
.PARAMETER Path7Z
	Chemin d'accès au fichier 7z.exe si l'on ne souhaite pas utiliser la version installée, ou que 7-Zip n'est pas installé.
.PARAMETER Force
	Permet d'écraser l'archive de destination si elle n'existe pas.
.PARAMETER PassThru
	Si définit, le cmdlet renverra un objet FileInfo représentant l'archive créée.
.OUTPUTS
	[System.IO.FileInfo] si le commutateur PassThru est défini, et que l'archive a été créée.
	Le fait qu'une archive n'a pas été créée peut être normal en fonction des paramètres d'exclusions passés.
.FUNCTIONALITY
	File
.NOTES
	* Lève une exception de type `ArgumentException` si l'extension de fichier n'est pas 7z.
	* Lève une exception si l'archive de destination existe et que le commutateur `Force`n'est pas défini.
	* Lève une exception si le code de retour de l’exécutable est différent de 0 (et donc il y a eu une erreur lors de la compression).
.EXAMPLE
	PS> Compress-7Zip -Source "D:\Test\*" -Destination "D:\Test.7z" -Level Normal -RemoveSource -PassThru
	Compression de tous les fichiers et dossiers dans "D:\Test", qui seront ensuite supprimés.
	A noter que le répertoire "D:\Test" ne sera pas lui-même supprimé dans ce cas.
.EXAMPLE
	PS> Compress-7Zip -Source "D:\Test\*" -Destination "D:\Test.7z" -Level Normal -Exclude ("*.user","*.temp","\folder1\folder2")
	Compression de tous les fichiers et dossiers dans "D:\Test", en excluant tous les fichiers trouvés ayant l'extension user ou temp,
	et en excluant le dossier folder2 uniquement dans le dossier de D:\Test\folder1.
#>
function Compress-7Zip
{
	[CmdletBinding()]
	[OutputType([System.IO.FileSystemInfo])]
	param
	(
		[Parameter(Mandatory)]
		[string]$Source,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Destination,

		[ValidateSet('Copy', 'Fastest', 'Fast', 'Normal', 'Maximum', 'Ultra')]
		$Level = 'Normal',

		[string[]]$Exclude,

		[switch]$RemoveSource,

		[Parameter(Mandatory=$false)]
		[System.Diagnostics.ProcessPriorityClass]$Priority = 'Normal',

		[switch]$ThreadingOff,

		[string]$Path7Z,

		[switch]$Force,

		[switch]$PassThru
	)

	# Compression Level Switch
	switch ($Level.ToLower())
	{
		"copy"     {$7zLevel=0}
		"fastest"  {$7zLevel=1}
		"fast"     {$7zLevel=3}
		"maximum"  {$7zLevel=7}
		"ultra"    {$7zLevel=9}
		default    {$7zLevel=5} #normal
	}
	$Levelswitch = "-mx$7zLevel"
	$method = "-m0=LZMA2"
	if ($7zLevel -eq 0) { $ZArgs=@($Levelswitch) }
	else                { $ZArgs=@($Levelswitch,$method) }

	$params = @{
		'Source'             = $Source
		'Destination'        = $Destination
		'Extension'          = '7z'
		'ZArgs'              = $ZArgs
		'Exclude'            = $Exclude
		'RemoveSource'       = $RemoveSource
		'Priority'           = $Priority
		'ThreadingOff'       = $ThreadingOff
		'Path7Z'             = $Path7Z
		'Force'              = $Force
		'PassThru'           = $PassThru
	}
	Invoke-7Zip @params
}
<#
.SYNOPSIS
	Crée une nouvelle archive .zip à l'aide de la ligne de commande 7-Zip.
.DESCRIPTION
	7-Zip doit avoir été installé, sinon le chemin d'accès à `7z.exe` doit être passé en argument.

	Même si le cmdlet `Compress-Archive` existe, `Compress-Zip` a plusieurs avantages :
	* Il est facile d'utiliser des patterns d'exclusion.
	* Niveau et méthode de compression configurable.
	* Pas d'erreur lors de la compression si un fichier est ouvert.
.PARAMETER Source
	Chemin d'accès des éléments à compresser.
	Les caractères génériques sont acceptés.
	Attention cependant, sont acceptés les caractères génériques tels que définis par 7-Zip
	(cf. (Command Line Syntax)[https://sevenzip.osdn.jp/chm/cmdline/syntax.htm]).
	L'ensemble de ces caractères et leur signification sont différents de la norme PowerShell
	(cf. (about wildcards)[https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_wildcards]).
.PARAMETER Destination
	Chemin d'accès de l'archive à créer.
	Si l'archive existe déjà, elle sera supprimée.
	L'extension de fichier doit obligatoirement être .7z (c'est une limitation imposée par 7-Zip).
	Si l'arborescence de destination n'existe pas, elle sera créée.
.PARAMETER Level
	Niveau de Compression :
	* Copy     <=> -mx0
	* Fastest  <=> -mx1
	* Fast     <=> -mx3
	* Normal   <=> -mx5 (Valeur par défaut)
	* Maximum  <=> -mx7
	* Ultra    <=> -mx9
	La correspondance du niveau de compression dépend de la méthode utilisée. Consulter l'aide 7-Zip pour plus d'informations.
.PARAMETER Method
	Méthode de compression à utiliser. Deflate par défaut.
	Déflate est recommandé pour la création d'un zip pour sa grande compatibilité sur tous les systèmes.
.PARAMETER Exclude
	Exclu de la compression la liste des éléments.
	* Le paramètre s'applique indifféremment aux répertoires ou fichiers.
	* La paramètre s'applique de manière récursive, SAUF s'il commence par le caractère de séparation de dossier (\ sur Windows).
	* Les mêmes caractères génériques que pour le paramètre `Source` sont acceptés.
.PARAMETER RemoveSource
	Si défini, la source sera supprimée après la compression.
.PARAMETER Priority
	Permet de changer la priorité du processus du programme de compression.
	Voir la documentation (ProcessPriorityClass Enum)[https://docs.microsoft.com/fr-fr/dotnet/api/system.diagnostics.processpriorityclass]
	pour la liste des valeurs possibles.
	La valeur par défaut est "Normal".
.PARAMETER ThreadingOff
	N'autorise pas le multithreading pour ne s'exécuter que sur un seul cœur.
.PARAMETER Path7Z
	Chemin d'accès au fichier 7z.exe si l'on ne souhaite pas utiliser la version installée, ou que 7-Zip n'est pas installé.
.PARAMETER Force
	Permet d'écraser l'archive de destination si elle n'existe pas.
.PARAMETER PassThru
	Si définit, le cmdlet renverra un objet FileInfo représentant l'archive créée.
.OUTPUTS
	[System.IO.FileInfo] si le commutateur PassThru est défini, et que l'archive a été créée.
	Le fait qu'une archive n'a pas été créée peut être normal en fonction des paramètres d'exclusions passés.
.FUNCTIONALITY
	File
.NOTES
	* Lève une exception de type `ArgumentException` si l'extension de fichier n'est pas 7z.
	* Lève une exception si l'archive de destination existe et que le commutateur `Force`n'est pas défini.
	* Lève une exception si le code de retour de l’exécutable est différent de 0 (et donc il y a eu une erreur lors de la compression).
.EXAMPLE
	PS> Compress-Zip -Source "D:\Test\*" -Destination "D:\Test.7z" -Level Normal -RemoveSource -PassThru
	Compression de tous les fichiers et dossiers dans "D:\Test", qui seront ensuite supprimés.
	A noter que le répertoire "D:\Test" ne sera pas lui-même supprimé dans ce cas.
.EXAMPLE
	PS> Compress-Zip -Source "D:\Test\*" -Destination "D:\Test.7z" -Level Normal -Method "Deflate64" -Exclude ("*.user","*.temp","\folder1\folder2")
	Compression de tous les fichiers et dossiers dans "D:\Test", en excluant tous les fichiers trouvés ayant l'extension user ou temp,
	et en excluant le dossier folder2 uniquement dans le dossier de D:\Test\folder1.
#>
function Compress-Zip
{
	[CmdletBinding()]
	[OutputType([System.IO.FileSystemInfo])]
	param
	(
		[Parameter(Mandatory=$true)]
		[string]$Source,

		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$Destination,

		[ValidateSet("Copy","Fastest","Fast","Normal","Maximum","Ultra")]
		$Level="Normal",

		[ValidateSet("Copy", "Deflate", "Deflate64", "BZip2", "LZMA")]
		$Method="Deflate",

		[string[]]$Exclude,

		[switch]$RemoveSource,

		[Parameter(Mandatory=$false)]
		[System.Diagnostics.ProcessPriorityClass]$Priority="Normal",

		[switch]$ThreadingOff,

		[string]$Path7Z,

		[switch]$Force,

		[switch]$PassThru
	)

	# Compression Level Switch
	switch ($Level.ToLower())
	{
		"copy"     {$7zLevel=0}
		"fastest"  {$7zLevel=1}
		"fast"     {$7zLevel=3}
		"maximum"  {$7zLevel=7}
		"ultra"    {$7zLevel=9}
		default    {$7zLevel=5} #normal
	}
	$Levelswitch = "-mx$7zLevel"
	$mm = "-mm=$Method"
	if ($7zLevel -eq 0) { $ZArgs=@($Levelswitch) }
	else                { $ZArgs=@($Levelswitch,$mm) }

	# Invoke-7Zip
	$params = @{
		"Source"             = $Source
		"Destination"        = $Destination
		"Extension"          = "zip"
		"ZArgs"              = $ZArgs
		"Exclude"            = $Exclude
		"RemoveSource"       = $RemoveSource
		"Priority"           = $Priority
		"ThreadingOff"       = $ThreadingOff
		"Path7Z"             = $Path7Z
		"Force"              = $Force
		"PassThru"           = $PassThru
	}
	Invoke-7Zip @params
}
<#
.SYNOPSIS
	Décompression de fichiers à l'aide de 7-Zip.
.DESCRIPTION
	7-Zip doit avoir été installé, sinon le chemin d'accès à `7z.exe` doit être passé en argument.
.PARAMETER Path
	Chemin d'accès à l'archive à décompresser.
	L'archive peut être de n'importe quel format supporté par 7-Zip (zip,7z, etc.).
.PARAMETER DestinationPath
	Répertoire de destination. Si il n'existe pas, on essaiera de le créer.
.PARAMETER Exclude
	Exclu de la décompression la liste des éléments.
	* Le paramètre s'applique indifféremment aux répertoires ou fichiers.
	* La paramètre s'applique de manière récursive, SAUF s'il commence par le caractère de séparation de dossier (\ sur Windows).
	* Les caractères génériques sont acceptés.
	Attention cependant, sont acceptés les caractères génériques tels que définis par 7Zip
	(cf. (Command Line Syntax)[https://sevenzip.osdn.jp/chm/cmdline/syntax.htm]).
	L'ensemble de ces caractères et leur signification sont différents de la norme PowerShell
	(cf. (about wildcards)[https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_wildcards]).
.PARAMETER OverwriteMode
	Correspond aux paramètres 7-Zip suivants :
	* `Overwrite`        ⇔ `-aoa` : Overwrite All existing files without prompt.
	* `Skip`             ⇔ `-aos` : Skip extracting of existing files.
	* `RenameExtracting` ⇔ `-aou` : Auto rename extracting file (for example, name.txt will be renamed to name_1.txt).
	* `RenameExisting`   ⇔ `-aot` : Auto rename existing file (for example, name.txt will be renamed to name_1.txt).
	La valeur par défaut est `Skip`.
	Il n'existe pas de mode avec 7-Zip pour générer une erreur si la destination existe.
	Ne peut pas être utilisé en même temps que `Force`.
.PARAMETER Force
	Equivalent de `-OverwriteMode 'Overwrite'`.
	Ne peut donc pas être utilisé en même temps que `OverwriteMode`.
.PARAMETER Priority
	Permet de changer la priorité du processus du programme de compression.
	Voir la documentation (ProcessPriorityClass Enum)[https://docs.microsoft.com/fr-fr/dotnet/api/system.diagnostics.processpriorityclass]
	pour la liste des valeurs possibles.
	La valeur par défaut est "Normal".
.PARAMETER RedirectStandardOutput
	Empêche 7-Zip d'afficher du texte dans la console.
.PARAMETER Path7Z
	Chemin d'accès au fichier 7z.exe si l'on ne souhaite pas utiliser la version installée, ou que 7-Zip n'est pas installé.
.FUNCTIONALITY
	File
.NOTES
	* Lève une exception [System.ArgumentException] si le commutateur `Force` est défini en conjonction avec le paramètre `OverwriteMode`,
	  et si ce dernier à une valeur différente de `Overwrite`.
	* Lève une exception si le code de retour de l’exécutable est différent de 0 (et donc il y a eu une erreur lors de la compression).
	* Une version simplifiée est fournie avec Get-Simple.
.EXAMPLE
	PS> Expand-7Zip -Path "D:\Test\archive.zip" -DestinationPath "D:\Test\Out" -Force -Priority High
	Décompresse l'archive "archive.zip" dans le répertoire "Out", si les fichiers existent déjà, ils seront écrasés.
	La priorité du processus 7zip sera haute.
.EXAMPLE
	PS> Expand-7Zip -Path "D:\Test\archive.zip" -DestinationPath "D:\Test\Out" -exclude @("*.config","\src\Project\*.resx")
	Décompresse l'archive, tous les fichiers .config ne seront pas extraits, et tous les fichiers resx uniquement dans le
	dossier src\Project ne seront pas extraits.
#>
function Expand-7Zip
{
	[CmdletBinding(DefaultParametersetname="OverwriteMode")]
	param
	(
		[Parameter(Position = 0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string]$Path,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$DestinationPath,

		[string[]]$Exclude,

		[Parameter(ParameterSetName = 'OverwriteMode')]
		[ValidateSet('Overwrite', 'Skip', 'RenameExtracting', 'RenameExisting')]
		[string]$OverwriteMode = 'Skip',

		[Parameter(ParameterSetName = 'Force')]
		[switch]$Force,

		[System.Diagnostics.ProcessPriorityClass]$Priority = 'Normal',

		[switch]$RedirectStandardOutput,

		[string]$Path7Z
	)

	BEGIN
	{
		# Récupération du Path 7z
		$Path7Z = Get-7ZipPath -Path7Z:$Path7Z

		# L'archive doit exister
		if (!(Test-Path $Path -PathType Leaf)) { Throw [IO.FileNotFoundException]::new("Impossible de trouver l'archive' sur ""$Path"", car elle n'existe pas.", "$Path") }

		# Tente de créer la destination si elle n'existe pas
		if (!(Test-Path $DestinationPath -PathType Container)) { New-Item -Path $DestinationPath -ItemType directory | Out-Null }

		# Argument Exclude
		$ExcludePattern = [string]""
		if ($Exclude)
		{
			$ExcludePattern = (($Exclude | % { if ($_.StartsWith([System.IO.Path]::DirectorySeparatorChar)) { "`-x!`"$($_.Substring(1))`"" } else { "`-xr!`"$_`"" } }) -join " ").Trim()
		}

		# Argument Overwrite Mode
		if ($Force)
		{
			$OverwriteMode = "Overwrite"
		}
		switch ($OverwriteMode)
		{
			{$_ -ieq 'Overwrite'}        { $overwrite = "-aoa" }
			{$_ -ieq 'RenameExtracting'} { $overwrite = "-aou" }
			{$_ -ieq 'RenameExisting'}   { $overwrite = "-aot" }
			Default                      { $overwrite = "-aos"}
		}
	}
	PROCESS
	{
		# Création des arguments
		$argList =  @("x", $overwrite, "`"$Path`"", "-o`"$DestinationPath`"",$ExcludePattern)

		# Décompression
		$pinfo = New-Object System.Diagnostics.ProcessStartInfo
		$pinfo.FileName = $Path7Z
		$pinfo.RedirectStandardError = $true
		$pinfo.RedirectStandardOutput = $RedirectStandardOutput
		$pinfo.UseShellExecute = $false
		$pinfo.Arguments = $argList
		$process = New-Object System.Diagnostics.Process
		$process.StartInfo = $pinfo
		$process.Start() | Out-Null

		# Attend la fin de la décompression
		if (!$process.HasExited)
		{
			$process.PriorityClass = $Priority # On ne peut changer la priorité qu'après avoir démarrer le process
			$process.WaitForExit()
		}
		$procExitCode = $process.ExitCode # Ne marche pas pour une raison inconnue, peut être parce que l'on ne fait pas -wait sur start-process ?

		# Traitement du code de retour
		if ($procExitCode -ne 0)
		{
			$stderr = $process.StandardError.ReadToEnd()
			$msg = "L'archive n'a pas pu être décompressée, 7-Zip s'est terminé avec le code de retour $procExitCode"
			if ($stderr) { $msg += " et le message :`n$stderr" }
			else { $msg += "." }
			throw $msg
		}
	}
}
<#
.SYNOPSIS
	Obtiens le chemin d'accès à l'exécutable 7Z.exe.
.DESCRIPTION
	Si l'argument Path7Z est passé, c'est ce chemin qui est utilisé. Une erreur est levé si il n'existe pas.

	Sinon, 7-Zip doit être installé, le chemin est trouvé via la clé dans la base de registre `HKCU\SOFTWARE\7-Zip\Path64`. Une
	erreur est levée si la clé est non trouvée ou le chemin d'accès est non trouvé.
.PARAMETER Path7Z
	Chemin d'accès au fichier 7z.exe si l'on ne souhaite pas utiliser la version installée, ou que 7-Zip n'est pas installé.
	Une chaîne vide ou nulle est accepté et sera ignorée pour faciliter le passage des paramètres par le cmdlet appelant.
.OUTPUTS
    [string] Chemin d'accès au fichier `7z.exe`.
.FUNCTIONALITY
    File
.LINK
	Compress-7Zip
.LINK
	Expand-7Zip
.EXAMPLE
    PS> Get-7ZipPath

	Retourne 'C:\Program Files\7-Zip\7z.exe'.
.EXAMPLE
	PS> Get-7ZipPath -Path7Z '.\lib\7z.exe'

	Retourne par exemple 'D:\current-location\.lib\7z.exe'.
#>
function Get-7ZipPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param
	(
        [string]$Path7Z
	)

	# Récupère le chemin d'installation de 7-Zip
	if ([string]::IsNullOrWhiteSpace($Path7Z))
	{
		$Path7Z = Get-ItemPropertyValue -Path 'Registry::HKCU\SOFTWARE\7-Zip' -Name 'Path64' -ErrorAction SilentlyContinue
		if (!$Path7Z)
		{
			Write-Error "7-Zip ne peut pas être utilisé car il n'a pas été installé." -Category NotInstalled -ErrorId '7ZipNotFound'
			return
		}
		else
		{
			$Path7Z = Join-Path $Path7Z '7z.exe'
		}
	}

	# Teste l'existence du chemin
	if (!(Test-Path $Path7Z -PathType Leaf))
	{
		Write-Error -Exception ([System.IO.FileNotFoundException]::new("L'éxécutable 7-Zip n'existe pas sur '$Path7Z'."))
		return
	}

	# Fin
	$Path7Z
}
<#
.SYNOPSIS
	Appelle 7z.exe en ligne de commande.
.DESCRIPTION
	Méthode interne destinée à être utilisée par les méthodes `Compress-7zip` et `Compress-Zip`.
	(Seul les formats Zip et 7Z sont supportés).
.PARAMETER Source
	Chemin d'accès des éléments à compresser.
	Les caractères génériques sont acceptés.
	Attention cependant, sont acceptés les caractères génériques tels que définis par 7Zip
	(cf. (Command Line Syntax)[https://sevenzip.osdn.jp/chm/cmdline/syntax.htm]).
	L'ensemble de ces caractères et leur signification sont différents de la norme PowerShell
	(cf. (about wildcards)[https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_wildcards]).
.PARAMETER Destination
	Chemin d'accès de l'archive à créer.
	Si l'archive existe déjà, elle sera supprimée.
	L'extension de fichier doit obligatoirement correspondre à la méthode de compression utilisée.
	Si l'arborescence de destination n'existe pas, elle sera créée.
.PARAMETER Extension
	Extension de l'archive à créer (7z ou zip).
.PARAMETER ZArgs
	Arguments supplémentaires qui dépendent de la méthode de compilation utilisée.
.PARAMETER Exclude
	Exclu de la compression la liste des éléments.
	* Le paramètre s'applique indifféremment aux répertoires ou fichiers.
	* La paramètre s'applique de manière récursive, SAUF s'il commence par le caractère de séparation de dossier (\ sur Windows).
	* Les mêmes caractères génériques que pour le paramètre `Source` sont acceptés.
.PARAMETER RemoveSource
	Si défini, la source sera supprimée après la compression.
.PARAMETER Priority
	Permet de changer la priorité du processus du programme de compression.
	Voir la documentation (ProcessPriorityClass Enum)[https://docs.microsoft.com/fr-fr/dotnet/api/system.diagnostics.processpriorityclass]
	pour la liste des valeurs possibles.
	La valeur par défaut est "Normal".
.PARAMETER ThreadingOff
	N'autorise pas le multithreading pour ne s'exécuter que sur un seul cœur.
.PARAMETER Path7Z
	Chemin d'accès au fichier 7z.exe si l'on ne souhaite pas utiliser la version installée, ou que 7-Zip n'est pas installé.
.PARAMETER Force
	Permet d'écraser l'archive de destination si elle n'existe pas.
.PARAMETER PassThru
	Si définit, le cmdlet renverra un objet FileInfo représentant l'archive créée.
.PARAMETER RedirectStandardOutput
	Réservé pour les tests. Permet de n'afficher aucune sortie de 7-Zip.
.OUTPUTS
	[System.IO.FileInfo] si le commutateur PassThru est défini, et que l'archive a été créée.
	Le fait qu'une archive n'a pas été créée peut être normal en fonction des paramètres d'exclusions passés.
.FUNCTIONALITY
	File
.NOTES
	* Lève une exception de type `ArgumentException` si l'extension de fichier de l'archive ne correspond pas
	  à la valeur du paramètre `Extension`.
	* Lève une exception de type `IOException` si l'archive de destination existe et que le commutateur `Force`n'est pas défini.
	* Lève une exception si le code de retour de l’exécutable est différent de 0 (et donc il y a eu une erreur lors de la compression).
	* Lève une exception `FileNotFoundException` si l'archive de destination n'existe pas après la compression.
	  Ce cas ne devrait théoriquement pas se produire.
.EXAMPLE
	PS> Invoke-7Zip -Source "D:\test\*" -Destination "D:\test.7z" -Extension "7z" -ZArgs @("-m0=LZMA2","-mx9") -Exclude "*.toexclude" -RemoveSource:$RemoveSource -Priority "AboveNormal" -ThreadingOff:$ThreadingOff -Force:$Force -PassThru:$PassThru
#>
function Invoke-7Zip
{
	[CmdletBinding()]
	[OutputType([System.IO.FileSystemInfo])]
	param
	(
		[Parameter(Mandatory)]
		[string]$Source,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Destination,

		[Parameter(Mandatory)]
		[ValidateSet('7z', 'zip')]
		[string]$Extension,

		[Parameter(Mandatory)]
		[string[]]$ZArgs,

		[string[]]$Exclude,

		[switch]$RemoveSource,

		[System.Diagnostics.ProcessPriorityClass]$Priority = 'Normal',

		[switch]$ThreadingOff,

		[string]$Path7Z,

		[switch]$Force,

		[switch]$PassThru,

		[switch]$RedirectStandardOutput
	)

	# Récupération du Path 7z
	$Path7Z = Get-7ZipPath -Path7Z:$Path7Z

	# Exception si l'extension n'est pas celle souhaitée
	if ([System.IO.Path]::GetExtension($Destination) -ne ".$Extension")
	{
		throw New-Object System.ArgumentException("L'extension de fichier de l'archive doit être `".$Extension`".","Destination")
	}

	# Multithreading
	$threading=""
	if ($ThreadingOff) { $threading="-mmt=off" }

	# Supprime l'archive Destination si elle existe
	if (Test-Path $Destination)
	{
		if ($Force) { Remove-ItemIfExists $Destination }
		else { throw New-Object System.IO.IOException("L'archive de destination existe déjà sur `"$Destination`". Utiliser le commutateur Force pour effacer l'archive de destination avant la compression.") }
	}

	# Compression
	$ExcludePattern = [string]""
	if ($Exclude)        { $ExcludePattern = ($Exclude | % { if ($_.StartsWith([System.IO.Path]::DirectorySeparatorChar)) { "`-x!`"$($_.Substring(1))`"" } else { "`-xr!`"$_`"" } }) -join " " }
	if ($ExcludePattern) { $ExcludePattern = $ExcludePattern.Trim() }
	# Supprime les champs nulls éventuels (comme ExcludePattern)
	$argList =  @("a", $threading, $ExcludePattern,"`"$Destination`"", "`"$Source`"") + $ZArgs | % { if ($_) { $_ } }
	#   a    : Adds files to archive.
	#   -mx  : Specifies the compression method. (x=7zip)
	#   -xr  : Specifies which filenames or wildcarded names must be excluded from the operation.
	#        : r pour récursif, ! pour wildchards.
	#   -r   : Specifies the method of treating wildcards and filenames on the command line.
	#
	# Lancement de la compression
	# On n'utilise pas Start-Process car il est impossible de récupérer le ExitCode
	$pinfo = New-Object -TypeName "System.Diagnostics.ProcessStartInfo"
	$pinfo.FileName = $Path7Z
	$pinfo.RedirectStandardError = $true
	$pinfo.RedirectStandardOutput = $RedirectStandardOutput
	$pinfo.UseShellExecute = $false
	$pinfo.Arguments = $argList
	$process = New-Object -TypeName "System.Diagnostics.Process"
	$process.StartInfo = $pinfo
	$process.Start() | Out-Null

	# Attend la fin de la compression
	if (!$process.HasExited)
	{
		$process.PriorityClass = $Priority # On ne peut changer la priorité qu'après avoir démarrer le process
		$process.WaitForExit()
	}
	$procExitCode = $process.ExitCode # Ne marche pas pour une raison inconnue, peut être parceque l'on ne fait pas -wait sur start-process ?

	# Traitement du code de retour
	if ($procExitCode -ne 0)
	{
		$stderr = $process.StandardError.ReadToEnd()
		$msg = "L'archive n'a pas pu être créée, 7-Zip s'est terminé avec le code de retour $procExitCode"
		if ($stderr) { $msg += " et le message :`n$stderr" }
		else { $msg += "." }
		throw $msg
	}

	# Suppression de la source si nécessaire
	if ($RemoveSource) { Remove-ItemIfExists $Source }

	# Attention l'archive peut ne pas exister, et cela peut être normal en fonction des paramètres d'exclusion
	if (!(Test-Path $Destination)) { throw New-Object System.IO.FileNotFoundException("L'archive sur `"$Destination`" n'existe pas après la compression.", $Destination) }
	if ($PassThru) { Get-Item $Destination }
}
<#
.SYNOPSIS
	Permet d'appeler simplement Robocopy.
.DESCRIPTION
	Permet d'appeler simplement Robocopy en définissant certaines options par défaut, et en ajoutant d'autres options.

	Les paramètres Robocopy suivants sont initialisés par défaut :
	* /LEV:20 : Force un niveau maximum de profondeur pour éviter les erreurs de copie récursive si source = destination.

	Dans le cas de la copie de fichier, on prend le nom du fichier source pour le définir dans le répertoire de destination.
	(L'avantage d'utiliser Robocopy plutôt que Copy-Item est que l'arborescence des dossiers est créée si elle n'existe pas).

	Le code de retour de Robocopy est une erreur si >= 8, dans ce case une erreur sera inscrite via `Write-Error`.
.PARAMETER Source
	Spécifie le chemin d'accès au répertoire source.
	Pour simplifier la ligne de commande, ce chemin d'accès peut être un fichier, dans ce cas le paramètres Files est inutile,
	car il sera remplit avec le nom du fichier.
.PARAMETER Destination
	Répertoire destination de copie (arborescence sera créé par Robocopy si elle n'existe pas).
.PARAMETER Files
	Spécifie le ou les fichiers à copier.
	Vous pouvez utiliser des caractères génériques (* ou ?) si vous le souhaitez.
	Si le paramètre n'est pas spécifié, `*.\*` est utilisé comme valeur par défaut.
	Si Source est un fichier et pas un répertoire, ce paramètre sera remplacé par Source.
.PARAMETER Title
	Si défini, on fait un Write-Host "Title" avant la copie.
.PARAMETER CompareResult
	Si défini, on fait un Compare-Object de source et destination.
	Dans la sortie de la commande, la sortie du Compare-Object peut être filtrée en faisant $result | ? { $_ -is [System.Management.Automation.PSCustomObject] }
.PARAMETER IgnoreFiles
	(/xf) Liste de nom de fichiers ou patterns à ignorer. Supporte les wildcards * et ?, mais pas les expressions régulières.
	Robocopy autorise la saisie d'un chemin d'accès complet, par exemple C:\dir\file.ext.
	Par exemple, si l'on fait -xf "C:\dir\file1.ext" "D:\dir\file2.ext" avec une copie mirroir de "C:\" vers "D:\", et que file1 existe sur C et file2 existe sur D :
	file1 ne sera pas copié et file2 ne sera pas effacé.
	Robocopy n'autorise pas la saisie d'un chemin d'accès partiel, par exemple "\dir\file1.ext". Cette options est ajoutée par ce cmdlet, si un exclude commence par un seul "\",
	le path de la source et de la destination seront ajoutés.
	Les "" sont ajoutés automatiquement.
.PARAMETER IgnoreDirectories
	(/xd) Liste de nom de répertoires ou patterns à ignorer. Supporte les wildcards * et ?, mais pas les expressions régulières.
	Mêmes remarques et possibilités que sur $IgnoreFiles.
.PARAMETER Mirror
	(/mir) Met en miroir une arborescence.
	Ce paramètre n'est pas valide si $Source est un fichier et pas un dossier.
.PARAMETER NoFileList
	(nfl) Pas de liste de fichiers.
	Par défaut robocopy affiche chaque fichier traité.
.PARAMETER NoDirList
	(ndl) Pas de liste de répertoires.
	Par défaut robocopy affiche chaque répertoire traité.
.PARAMETER NoJobHeader
	(njh) Pas d'en-tête de tâche.
	Par défaut robocopy affiche une ligne d'en-tête avec date, paramètres utilisés, etc.
.PARAMETER NoJobSummary
	(njs)
	Pas de sommaire de tâche.
	Par défaut robocopy affiche à la fin un récapitulatif indiquant le nombre de fichiers et répertoires copiés, etc.
.FUNCTIONALITY
	File
.NOTES
	Rappel des paramètres Robocopy
	* File selection options
		* /xf     : Excludes files that match the specified names or paths. Note that FileName can include wildcard characters (* and ?).
		* /xd     : Excludes directories that match the specified names and paths.
	* Copy options
		* /mir    : Mirrors a directory tree (equivalent to /e plus /purge).
	* Logging options
		* /nfl     : Specifies that file names are not to be logged.
		* /ndl     : Specifies that directory names are not to be logged.
		* /unicode : Displays the status output as Unicode text.
		* /njh     : Specifies that there is no job header.
		* /njs     : Specifies that there is no job summary.
.LINK
	https://docs.microsoft.com/fr-fr/windows-server/administration/windows-commands/robocopy
.EXAMPLE
	PS> Invoke-Robocopy -Source 'C:\_\src' -Destination 'C:\_\dst' -mir -xf @('\dir\file1.txt', '\dir\file2.txt') -xd @('\dir1\dir1', '\dir1\dir2') -nfl -ndl -njh -njs -ErrorAction Stop
.EXAMPLE
	PS> Invoke-Robocopy -Source 'C:\_\src' -Destination 'C:\_\dst' -Files 'A.txt', '*.avi' -Mirror
	Copie de tous les fichiers "A.txt" et "*.avi" de src vers dst.
#>
function Invoke-Robocopy
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification="Compatibilité PowerShell 4")]
	[CmdletBinding()]
	param
	(
		[Parameter(Position = 0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[ValidateScript({ Test-Path $_ })]
		[string]$Source,

		[Parameter(Position = 1, Mandatory)]
		[string]$Destination,

		[Parameter(Position = 2)]
		[string[]]$Files,

		[string]$Title,

		[switch]$CompareResult,

		[Parameter()]
		[Alias("xf")]
		[string[]]$IgnoreFiles,

		[Parameter()]
		[Alias("xd")]
		[string[]]$IgnoreDirectories,

		[Alias("mir")]
		[switch]$Mirror,

		[Alias("nfl")]
		[switch]$NoFileList,

		[Alias("ndl")]
		[switch]$NoDirList,

		[Alias("njh")]
		[switch]$NoJobHeader,

		[Alias("njs")]
		[switch]$NoJobSummary
	)
	PROCESS
	{
		# Affiche le titre de l'opération
		# On utilise Write-Host et pas Write-Information pour être compatible v4.
		if ($Title) { Write-Host $Title }

		# Construction des paramètres
		$parameters = @($Source, $Destination)

		## Fichiers
		if (Test-Path  $Source -PathType Leaf)
		{
			$item = gi $Source
			$Files = @($item.Name)
			$Source = $item.Directory.FullName
		}
		if ($files)
		{
			$parameters += $Files
		}

		## Level 20
		$parameters += "/LEV:20"

		## Switchs
		@(@("mir",$mirror),@("nfl",$NoFileList),@("ndl",$NoDirList),@("njh",$NoJobHeader),@("njh",$NoJobSummary)) | % {
			if ($_[1]) { $parameters += "/$($_[0])" }
		}
		## Excludes
		filter Add-SourcePath { if ($_.StartsWith("\") -and (!$_.StartsWith("\\"))) { Join-Path $Source $_; Join-Path $Destination $_ } else { $_ } }
		if ($IgnoreFiles)
		{
			$IgnoreFiles = $IgnoreFiles | Add-SourcePath
			$parameters += "/xf"
			$parameters += $IgnoreFiles
		}
		if ($IgnoreDirectories)
		{
			$IgnoreDirectories = $IgnoreDirectories | Add-SourcePath
			$parameters += "/xd"
			$parameters += $IgnoreDirectories
		}

		# Invocation
		&robocopy @parameters
		# Exit Code
		# Any value greater than or equal to 8 indicates that there was at least one failure during the copy operation.
		if ($LASTEXITCODE -ge 8)
		{
			Write-Error "Robocopy s'est terminé avec le code ($LASTEXITCODE)." -ErrorId "Robocopy"
		}

		# Comparaison si nécessaire
		if ($CompareResult)
		{
			$ref = gci -path $Source -Recurse      | Select-Object -ExpandProperty 'FullName' | % { $_.Substring($Source.Length) }
			$dif = gci -path $Destination -Recurse | Select-Object -ExpandProperty 'FullName' | % { $_.Substring($Destination.Length) }
			if (!$ref) { $ref = @() }
			if (!$dif) { $dif = @() }
			Compare-Object -ReferenceObject $ref -DifferenceObject $dif
		}
	}
}
<#
.SYNOPSIS
	Supprime un élément uniquement si il existe, raccourcis pour `Remove-Item -Recurse -Force`.
.DESCRIPTION
	La seule erreur qui est ignorée est celle levée si l'élément n'existe pas.

	Renvoie les chemins d'accès passés en paramètre si PassThru.
.PARAMETER Path
	Chemin d'accès des éléments à effacer. Les caractères génériques sont autorisés.
.PARAMETER LiteralPath
	Chemin d'accès des éléments à effacer. Les caractères génériques sont autorisés.
.PARAMETER PassThru
	Retourne chaque objet d'entrée. Par défaut, cette cmdlet ne génère aucune sortie.
.PARAMETER Recycle
	Envoie l'élément supprimé à la corbeille comme le ferait une suppression via l'explorateur Windows.
	N'est valide que sous Windows, et que pour des fichiers ou répertoire.
.INPUTS
	[string] Accepte une chaîne contenant un chemin d'accès dans le pipeline, mais pas un chemin littéral.
.INPUTS
	[System.IO.FileSystemInfo] Accepte un `FileInfo` ou un `DirectoryInfo` dans le pipeline, qui sera converti implicitement par
	PowerShell en `string`, et sera donc accepté en tant que chemin d'accès.
.OUTPUTS
	[string] Le chemin d'accès passé en paramètre.
.FUNCTIONALITY
	File
.NOTES
	A noter que l'on ne peut pas l'utiliser pour les variables locales, car `Remove-Item` sera exécuté dans le scope
	de `Remove-ItemIfExists`, pas de le scope de l'appelant.
.EXAMPLE
	PS> Remove-ItemIfExists "D:\Folder\*" -Verbose

	Suppression du contenu d'un répertoire existant.
.EXAMPLE
	PS> (gi "D:\Folder\a.txt"), (gi "D:\Folder\b.txt") | Remove-ItemIfExists

	Suppression de plusieurs fichiers.
.EXAMPLE
	PS> Remove-ItemIfExists "D:\file.txt" -Recycle

	Suppression d'un fichier en l'envoyant à la corbeille.
.EXAMPLE
	PS> $path1, $path2, $path3 | Remove-ItemIfExists -PassThru

	Suppression de fichiers et retourne les éléments d'entrée.
#>
function Remove-ItemIfExists
{
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "")]
	[Alias("Remove-ItemSafely")]
	[CmdletBinding(DefaultParameterSetName = 'Path')]
	[OutputType([string])]
	param
	(
		[Parameter(ParameterSetName = 'Path', Position=0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string]$Path,

        [Parameter(ParameterSetName = 'LiteralPath', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [string]
        $LiteralPath,

		[switch]$PassThru,

		[switch]$Recycle
	)

	BEGIN
	{
		if ($Recycle)
		{
			if (!(Get-Variable 'IsWindows' -ValueOnly))
			{
				# On utilise Get-Variable afin de mocker la variable pour les tests unitaires
				throw New-Object System.PlatformNotSupportedException("Le commutateur Recycle n'est supporté que sur Windows.")
			}
			$shell = New-Object -ComObject 'Shell.Application'
		}
	}
	PROCESS
	{
		$pathParam = @{ Path = $Path}
		if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $pathParam = @{ LiteralPath = $LiteralPath} }

		if (Test-Path @pathParam)
		{
			if ($Recycle)
			{
				foreach ($fullName in ((Get-Item @pathParam) | % FullName))
				{
					$item = Get-Item $fullName
					$shellFolder = $shell.Namespace((Split-Path $fullName -Parent)) # Répertoire parent
					$shellItem = $shellFolder.ParseName($item.Name)
					$shellItem.InvokeVerb('delete')
				}
			}
			else
			{
				Remove-Item @pathParam -Recurse -Force -Verbose:(Get-VerboseSwitch)
			}
		}
		else
		{
			Write-Verbose "Impossible de trouver le chemin d'accès '$Path' car il n'existe pas."
		}

		if ($PassThru) { $_ }
	}
}
<#
.SYNOPSIS
	Remplace dans le contenu d'un fichier une chaîne de caractère.
.DESCRIPTION
	Remplace dans le contenu d'un fichier une chaîne de caractère en utilisant une expression régulière.
.PARAMETER Path
	Chemin d'accès complet au fichier.
.PARAMETER Encoding
	Encodage du fichier.
.PARAMETER Pattern
	Pattern (Expression régulière) à rechercher et remplacer.
.PARAMETER Replacement
	Chaîne de remplacement.
	Passer une chaîne vide, nulle, ou ne pas passer ce paramètre revient à supprimer le pattern dans le fichier.
.PARAMETER EscapeRegex
	Définir de switch pour indiquer que le pattern à remplacer n'est pas une expression régulière.
.FUNCTIONALITY
	File
.EXAMPLE
	C:\PS>Update-FileContent "E:\Test.xml" -Encoding UTF8 -Pattern "(?i)(?s)rOot.*root" -Replacement "toto"
 	Remplace dans le fichier Test.xml le pattern "rOot.*root" (avec les options Case insensitive et Single Line activées) par la chaîne "toto".
.EXAMPLE
	C:\PS>"E:\Test-A.xml","E:\Test-B.xml" | Update-FileContent -p "." -e "utf8" -r "," -EscapeRegex -Verbose -ErrorAction Continue
	Remplace dans les fichier tous les points par des virgules.
	Comme `ErrorAction` est égal à `Continue`, si un des deux fichiers n'existe pas, une erreur sera affichée, et l'autre fichier sera traité.
#>
function Update-FileContent
{
	[CmdletBinding()]
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
	param
	(
		[Parameter(Position=0,Mandatory=$true,ValueFromPipeline = $true)]
		[ValidateScript({ Test-Path $_ -PathType Leaf })]
		[string]$Path,

		[Parameter(Mandatory)]
		[ValidateSet("Ascii", "BigEndianUnicode", "Unicode", "Utf7", "Utf8", "Utf8Bom", "Utf8NoBom", "Utf32")]
		[alias("e")]
		[string]$Encoding,

		[alias("p")]
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$Pattern,

		[alias("r")]
		[Parameter(Mandatory=$false)]
		[string]$Replacement=[String]::Empty,

		[switch]$EscapeRegex
	)

	BEGIN
	{
		if ($EscapeRegex)
		{
			$Pattern = [System.Text.RegularExpressions.Regex]::Escape("$Pattern")
		}
		$ps5 = $PSVersionTable.PSVersion.Major -lt 6
		if ($ps5)
		{
			switch ($Encoding)
			{
				"BigEndianUnicode" { $ps5Encoding = [System.Text.Encoding]::BigEndianUnicode }
				"Unicode"          { $ps5Encoding = [System.Text.Encoding]::Unicode }
				"Utf7"             { $ps5Encoding = [System.Text.Encoding]::UTF7 }
				"Utf8"      { $ps5Encoding = New-Object System.Text.UTF8Encoding $false }
				"Utf8Bom"   { $ps5Encoding = New-Object System.Text.UTF8Encoding $true }
				"Utf8NoBom" { $ps5Encoding = New-Object System.Text.UTF8Encoding $false }
				"Utf32"            { $ps5Encoding = [System.Text.Encoding]::UTF32 }
				Default            { $ps5Encoding = [System.Text.Encoding]::ASCII }
			}
		}
	}

	PROCESS
	{
		# Verbose
		Write-Verbose "Remplace dans le fichier '$path' le modèle '$Pattern' par '$Replacement'..."

		# Remplace dans le contenu et ré-écrit le fichier
		if ($ps5)
		{
			$value = ([IO.File]::ReadAllText($Path, $ps5Encoding)) -replace $Pattern, $Replacement
			[IO.File]::WriteAllText($Path, $value, $ps5Encoding)
		}
		else
		{
			(Get-Content -Raw $Path -Encoding $Encoding) -replace $Pattern, $Replacement | Out-File -FilePath $Path -Encoding $Encoding -NoNewline
		}
	}
}

#endregion FCT-FILE

#————————————————————————————————————————————————————————————————————————————————————————
#region FCT-POWERSHELL
#————————————————————————————————————————————————————————————————————————————————————————
<#
.SYNOPSIS
	Renvoie $true ou $false en fonction de $VerbosePreference.
.DESCRIPTION
	Renvoie $true ou $false en fonction de $VerbosePreference.
    Certaines cmdlet comme New-Item ou Remove-item semble ignorer $VerbosePreference, Get-VerboseSwitch permet
    de forcer le switch Verbose en fonction de $VerbosePreference
.OUTPUTS
	[System.Boolean] True si $VerbosePreference est superieur ou égal à continue.
.FUNCTIONALITY
	Powershell
.EXAMPLE
	PS> New-item "C:\test.txt" -Verbose:(Get-VerboseSwitch)
	True
#>
function Get-VerboseSwitch
{
    [OutputType("System.Boolean")]
    [CmdletBinding()]
    param()
    $VerbosePreference -ge [System.Management.Automation.ActionPreference]::Continue;
}
<#
.SYNOPSIS
    Installation d'un module PowerShell à partir d'un dossier local.
.DESCRIPTION
	Permet de ne pas avoir à passer par un dépôt PowerShell avec la commande Install-Module.

	Le module est installé dans `$env:ProgramFiles\WindowsPowerShell\Modules` pour Windows PowerShell, et dans
	`$env:ProgramFiles\WindowsPowerShell\Modules` pour PowerShell Core.
	Il respecte la convention PowerShell en étant installé dans `\<Name>\<Version>`.

	Attention, si le module est déjà installé, toutes les versions existantes sont supprimées, quelle que soit celle à installer.

	Par simplicité : Le module doit avoir un fichier manifeste .psd1 à la racine du dossier. Le nom et la version du module seront
	déduits de ce manifeste.
	Tous le contenu du dossier parent de ce fichier manifeste sera copié.
.PARAMETER Path
	Chemin d'accès au fichier manifeste .psd1 du module.
.PARAMETER Backup
	Chemin d'accès de l'archive qui sera crée si l'on veut faire une sauvegarde des versions déjà installées du module.
	Si le dossier d'installation n'existe pas, aucune archive ne sera créée.
	La commande utilisée est `Compress-Archive -Path "<DirPath>\*" -DestinationPath $Backup -CompressionLevel Fastest -Force` :
	   * On utilise le format zip plutôt que 7zip car privilégie la rapidité d'exécution au niveau de compression. C'est une archive
	     de secours le temps de l'installation, elle n'est pas destinée à être conservée à long terme.
	   * Si l'archive existe déjà, elle sera écrasée dans avertissement.
	   * L'arborescence sera créée si nécessaire.
.FUNCTIONALITY
	Install
.EXAMPLE
	PS> Install-LocalModule -Path "C:\_\module\Module.Simple.psd1" -Backup "C:\_\backup\$(get-date -Format 'yyyyMMdd-HHmmss').zip"
#>
function Install-LocalModule
{
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact="Medium")]
	param
	(
		[Parameter(Position = 0, Mandatory)]
		[Alias("p")]
		[string]$Path,

		[Parameter()]
		[string]$Backup
	)

	BEGIN
	{
		# Le répertoire des modules est différent entre Windows PowerShell et PowerShell Core
		$pgfiles = (Get-Item 'env:programfiles').Value # Permet d'être mocké
		if ($PSEdition -eq 'Core')
		{
			# C:Program Files\PowerShell\Modules\MyModule
			$pathInstallModule = "$pgfiles\PowerShell\Modules"
		}
		else
		{
			# C:Program Files\WindowsPowerShell\Modules\MyModule
			$pathInstallModule = "$pgfiles\WindowsPowerShell\Modules"
		}
	}
	PROCESS
	{
		#) Validation du Path
		if (!(Test-Path $path -PathType Leaf)) { Throw [IO.FileNotFoundException]::new("Impossible de trouver le fichier sur ""$Path"", car il n'existe pas.", "$Path") }
		$pathInstall = "$pathInstallModule\" + (gi $Path).NameWithoutExtension

		#) Backup si nécessaire
		if (Test-Path $pathInstall)
		{
			# Archivage
			if ($Backup -and $PSCmdlet.ShouldProcess("Source: $pathInstall\*, Destination: $Backup", "Archivage"))
			{
				# Création de l'arborescence
				md (Split-Path $Backup -Parent) -Force | Out-Null
				# Archive
				Compress-Archive -Path "$pathInstall\*" -DestinationPath $Backup -CompressionLevel Fastest -Force
			}
			# Nettoyage des anciennes versions
			Remove-Item -Path $pathInstall -Recurse -Force # /ShouldProcess
		}

		#) Installation
		$ModuleVersion = (Import-PowerShellDataFile -Path $Path).ModuleVersion # Import-PowerShellDataFile n'existe pas en 5.0
		Copy-Item -Path (Split-Path $Path -Parent) -Destination "$pathInstall\$ModuleVersion" -Force -Recurse # /ShouldProcess
	}
}
<#
.SYNOPSIS
	Crée un nouvel objet `PSCredential' à partir d'un nom d'utilisateur et d'un mot de passe.
.DESCRIPTION
	`New-Credential` crée un nouvel objet `PSCredential` à partir d'un nom d'utilisateur et d'un mot de passe,
	en convertissant le mot de passe sous forme de `String` en `Secure-String`.

	Les commandes PowerShell utilisent les objets `PSCredential` au lieu du nom d'utilisateur/mot de passe.
	Bien que Microsoft recommande d'utiliser `Get-Credential` pour obtenir des informations d'identification,
	lors de l'automatisation des installations par exemple, il n'y a généralement personne pour répondre à cette invite de commande,
	les identifiants sont souvent extraits de magasins cryptés.

    Le mot de passe peut être lu en clair à tout moment en utilisant `$cred.GetNetworkCredential().Password`.
.PARAMETER UserName
	Le nom d'utilisateur.
.PARAMETER Password
	Le mot de passe. Peut être une `[string]` or une `[System.Security.SecureString]`.
.NOTES
    Source copiée de [Carbon](https://github.com/pshdo/Carbon/tree/develop/Carbon/Functions).
.OUTPUTS
    [System.Management.Automation.PSCredential].
.FUNCTIONALITY
	PowerShell
.EXAMPLE
	PS> $cred = New-Credential -UserName 'olivier' -Password 'P@assw0rd!'
	PS> $cred.GetNetworkCredential().Password
.EXAMPLE
	PS> New-Credential -UserName 'olivier' -Password (Read-Host -AsSecureString)
.EXAMPLE
	PS> 'P@ss1', 'P@ss2', 'P@ss3' | New-Credential -User 'olivier'
#>
function New-Credential
{
    [CmdletBinding()]
	[OutputType([Management.Automation.PSCredential])]
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions","")]
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword","")]
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText","")]
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUserNameAndPassWordParams","")]
	param
	(
		[Parameter(Mandatory, Position=0)]
		[Alias('User')]
		[string]$UserName,

		[Parameter(Mandatory, Position=1, ValueFromPipeline)]
		[Alias('Pswd')]
		$Password
	)

    PROCESS
    {
		if ($Password -is [string])
		{
			$Password = ConvertTo-SecureString -AsPlainText -Force -String $Password
		}
        elseif ($Password -isnot [securestring])
        {
			Write-Error (
				"Le type [$($Password.GetType())] pour le paramètre Password est invalide, " +
				"il doit être de type [string] ou [System.Security.SecureString].")
			return
        }

		return New-Object "Management.Automation.PsCredential" $UserName, $Password
    }
}
<#
.SYNOPSIS
	Enregistre une pause via l'événement Exiting pour les scripts lancés avec une console qui se fermera automatiquement.
.DESCRIPTION
	Le but est d'afficher une pause pour que l'utilisateur puisse voir le résultat d'exécution du script.
	La pause ne doit être affichée que si nécessaire, elle est par exemple inutile dans Visual Studio Code ou une console ouverte
	qui ne se fermera pas.

	A noter :
	L'évènement n'est pas déclenché lors de la fermeture de la console par l'utilisateur, ce qui nous convient.
	([#8000 Register-EngineEvent Powershell.Exiting does not work](https://github.com/PowerShell/PowerShell/issues/8000))
.FUNCTIONALITY
	PowerShell
#>
function Register-Pause
{
	[CmdletBinding(SupportsShouldProcess=$false)]
	param()

	# La console n'est fermé automatiquement qu'avec le lancement d'un fichier avec le paramètre -NoExit
	$hostWillExit =	([System.Environment]::GetCommandLineArgs() -notcontains "-NoExit")

	# Enregistre un évènement afin d'appeler Pause lors de la fermeture de la console
	# Lorsque l'utilisateur ferme la console en cliquant sur la croix, l'évènement est rarement appelé ce qui correspond
	# à ce que l'on attend
	if ($hostWillExit)
	{
		# On vérifie que l'évènement n'est pas déjà enregistré pour ne pas appeler plusieurs fois Pause
		if (!(Get-EventSubscriber -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue))
		{
			Write-Verbose 'Enregistre la pause sur la sortie de la console...'
			Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Pause } | Out-Null
		}
	}
}
<#
.SYNOPSIS
	Ecrit sur l'hôte une question posée à l'utilisateur.
.DESCRIPTION
	Ecrit sur l'hôte une question posée à l'utilisateur.
	Cette fonction permet juste d'avoir un code couleur consistant entre les scripts.

	La fonction utilise `Write-Host` et pas `Write-Information` par souci de compatibilité PowerShell 4.
	Dans les versions de PowerShell ≥ 5, `Write-Host` n'est de toute façon qu'un Wrapper pour `Write-Information`.
.PARAMETER Message
	Message à écrire.
.PARAMETER NoNewline
	Spécifie que le contenu affiché sur la console ne se termine pas avec un caractère de nouvelle ligne.
.PARAMETER ReadHost
	Si défini, un ReadHost sera effectué après le Write-Host;
.FUNCTIONALITY
	Host
.LINK
	Write-Step
.LINK
	Write-Result
.LINK
	Write-Host
.LINK
	Write-Information
.LINK
	Write-Debug
.LINK
	Write-Verbose
.LINK
	Write-Warning
.LINK
	Write-Error
.LINK
	Pour voir le rendu des couleurs, lancer le script `Write-X.ps1` dans les tests d'intégrations manuels.
#>
function Write-Question
{
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification="Write-Host utilise Write-Information.")]
	[CmdletBinding()]
	param
	(
		[Parameter(Position = 0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		$Message,

		[Alias('NoNL')]
		[switch]$NoNewline,

		[switch]$ReadHost
	)
	PROCESS
	{
		Write-Host $Message -NoNewline:$NoNewline -ForegroundColor $script:ShellCoreStyle.QuestionForegroundColor
		if ($ReadHost) { Read-Host }
	}
}
<#
.SYNOPSIS
	Ecrit sur l'hôte un résultat attendu de commande.
.DESCRIPTION
	Ecrit sur l'hôte un résultat attendu de commande.
	Cette fonction permet juste d'avoir un code couleur consistant entre les scripts.

	La fonction utilise `Write-Host` et pas `Write-Information` par souci de compatibilité PowerShell 4.
	Dans les versions de PowerShell ≥ 5, `Write-Host` n'est de toute façon qu'un Wrapper pour `Write-Information`.
.PARAMETER Message
	Message à écrire.
.PARAMETER If
	Si ce paramètre est défini, `Message` ne sera écrit que si `if` est vrai.
.PARAMETER Else
	Si ce paramètre est défini, et que `if` est faux, `Else`sera écrit à la place de `Message`.
.PARAMETER NoNewline
	Spécifie que le contenu affiché sur la console ne se termine pas avec un caractère de nouvelle ligne.
.FUNCTIONALITY
	Host
.LINK
	Write-Step
.LINK
	Write-Question
.LINK
	Write-Host
.LINK
	Write-Information
.LINK
	Write-Debug
.LINK
	Write-Verbose
.LINK
	Write-Warning
.LINK
	Write-Error
.LINK
	Pour voir le rendu des couleurs, lancer le script `Write-X.ps1` dans les tests d'intégrations manuels.
.EXAMPLE
	PS> 'Résultat 1', 'Résultat 2' | Write-Result
.EXAMPLE
	PS> Write-Result 'La commande a réussie.' -if $success
.EXAMPLE
	PS> Write-Result 'Configuration modifiée.' -if $set -else 'Configuration OK.'
#>
function Write-Result
{
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification="Write-Host utilise Write-Information.")]
	[CmdletBinding(DefaultParameterSetName='noif')]
	param
	(
		[parameter(Position = 0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[AllowNull()]
		$Message,

		[Parameter(ParameterSetName='noif')]
		[Parameter(ParameterSetName='if')]
		[bool]$If,

		[Parameter(ParameterSetName='if')]
		$Else,

		[Alias('NoNL')]
		[switch]$NoNewline
	)
	BEGIN
	{
		$options = @{ ForegroundColor = $script:ShellCoreStyle.ResultForegroundColor }
	}
	PROCESS
	{
		if (!$PSBoundParameters.ContainsKey('If'))
		{
			if ($PSCmdlet.ParameterSetName -eq 'if')
			{
				Write-Warning 'Le paramètre Else a été utilisé dans la commande Write-Result sans le paramètre If. La valeur de Else ne pourra jamais être affichée.'
			}
			Write-Host $Message -NoNewline:$NoNewline @options
		}
		else
		{
			if ($if)
			{
				Write-Host $Message -NoNewline:$NoNewline @options
			}
			elseif ($PSBoundParameters.ContainsKey('Else'))
			{
				Write-Host $Else -NoNewline:$NoNewline @options
			}
		}
	}
}
<#
.SYNOPSIS
	Ecrit sur l'hôte une étape de déroulement du script.
.DESCRIPTION
	Ecrit sur l'hôte une étape de déroulement du script.
	Cette fonction permet juste d'avoir un code couleur consistant entre les scripts, et d'ajouter des caractères de séparation.

	La fonction utilise `Write-Host` et pas `Write-Information` par souci de compatibilité PowerShell 4.
	Dans les versions de PowerShell ≥ 5, `Write-Host` n'est de toute façon qu'un Wrapper pour `Write-Information`.

	A noter que l'on ne considère qu'un seul niveau de séparation d'étape.
	La gestion de plusieurs niveaux d'étape deviendrait vide illisible dans la console.
.PARAMETER Message
	Message à écrire.
.PARAMETER NoNewline
	Spécifie que le contenu affiché sur la console ne se termine pas avec un caractère de nouvelle ligne.
.FUNCTIONALITY
	Host
.LINK
	Write-Result
.LINK
	Write-Question
.LINK
	Write-Host
.LINK
	Write-Information
.LINK
	Write-Debug
.LINK
	Write-Verbose
.LINK
	Write-Warning
.LINK
	Write-Error
.LINK
	Pour voir le rendu des couleurs, lancer le script `Write-X.ps1` dans les tests d'intégrations manuels.
#>
function Write-Step
{
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification="Write-Host utilise Write-Information.")]
	[CmdletBinding()]
	param
	(
		[parameter(Position = 0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		$Message,

		[Alias('NoNL')]
		[switch]$NoNewline
	)

	BEGIN
	{
		$optionsStep = @{ ForegroundColor = $script:ShellCoreStyle.StepForegroundColor }
		$optionsSeparator = @{ ForegroundColor = $script:ShellCoreStyle.StepSeparatorForegroundColor }
	}
	PROCESS
	{
		Write-Host
		Write-Host ([string]$script:ShellCoreStyle.StepSeparatorCharacter * $script:ShellCoreStyle.StepSeparatorWidth) @optionsSeparator
		Write-Host $Message -NoNewline:$NoNewline @optionsStep
	}
}

#endregion FCT-POWERSHELL



# Exporte toutes les fonctions et tous les alias (la liste sera filtrée dans le manifeste)
Export-ModuleMember -Function * -Alias *
