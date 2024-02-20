<#
.SYNOPSIS
	Génère un changelog HTML à partir d'un jalon GitHub.
.DESCRIPTION
	Le but est de pouvoir faire un copier-coller dans OneNote en conservant le formatage.
	Le copier-coller fonctionne avec Edge, c'est donc ce navigateur qui est ouvert en ligne de commande sur le fichier HTML.
.PARAMETER Owner
	Propriétaire du dépôt.
.PARAMETER Repo
	Nom du dépôt.
.PARAMETER Milestone
	Nom du jalon pour lequel générer le changelog.
.PARAMETER Output
	Chemin d'accès du fichier HTML à générer.
	Si le fichier existe déjà, il sera effacé.
	Le fichier sera ensuite ouvert avec Edge.
.PARAMETER IncludeLabel
    Noms ordonnés des labels à inclure. Le premier label trouvé correspondant déterminera la couleur de fond de la colonne.
	L'operateur `like`est utilisé, les wildcards sont dont autorisés.
.FUNCTIONALITY
    GitHub
.EXAMPLE
    PS> Build-GitHubChangelog -Owner "Datian" -Repo "ShellCore" -Milestone "7.0.0" -Output "D:\change.html" -IncludeLabel "wontfix", "doc*", "build"
#>
function Build-GitHubChangelog
{
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
	param
	(
		[Parameter(Mandatory)]
		[string]$Owner,

		[Parameter(Mandatory)]
		[string]$Repo,

		[Parameter(Mandatory)]
		[string]$Milestone,

		[Parameter(Mandatory)]
		[string]$Output,

		[Parameter(Mandatory)]
		[string[]]$IncludeLabel
	)

	#
	#region LABELS / JALON / TICKETS
	#
	# Récupération des labels
	Write-Verbose "Récupération des labels..."
	$allLabels = Invoke-GitHubRestMethod "https://api.github.com/repos/$Owner/$Repo/labels?per_page=50"
	# Fait un hash ordonné en fonction de IncludeLabel
	$labels = [ordered]@{}
	foreach ($include in $IncludeLabel)
	{
		$allLabels | ? { $_.Name -like $include } | % { $labels.Add($_.name, $_) }
	}

	# Récupération du jalon
	# L'API ne supporte que l'id du jalon, on récupère donc tous les milestones afin de comparer au nom.
	Write-Verbose "Récupération du jalon..."
	$milestones = Invoke-GitHubRestMethod "https://api.github.com/repos/$Owner/$Repo/milestones?state=all"
	$milestoneObj = $milestones | ? { $_.Title -eq $Milestone }
	if (!$milestoneObj)
	{
		Write-Error "Le jalon ""$Milestone"" n'a pas été trouvé." -Category ObjectNotFound -ErrorId "MilestoneNotFound"
		return
	}

	# Récupération des tickets
	Write-Verbose "Récupération des tickets..."
	$issues = Invoke-GitHubRestMethod "https://api.github.com/repos/$Owner/$Repo/issues?state=all&milestone=$($milestoneObj.number)"
	#endregion  Labels / Jalon / Tickets


	#
	#region Fichier
	#
	Write-Verbose "Génération du fichier..."

	# Classes CSS pour les labels
	$labelsStyle = @()
	foreach ($label in $labels.Values)
	{
		$red    = [Convert]::ToInt32($label.color.Substring(0, 2), 16)
		$green  = [Convert]::ToInt32($label.color.Substring(2, 2), 16)
		$blue   = [Convert]::ToInt32($label.color.Substring(4, 2), 16)
		$color = "white"
		if (($red*0.299 + $green*0.587 + $blue*0.114) -gt 186){ $color = "black" }
		$labelsStyle += ".label-$($label.id) { color: $color; background-color: $($label.color); }"
	}

	# Milestone
	[string]$milestoneDiv = $milestoneObj.description

	# Issues
	$trlist = @()
	foreach ($issue in $issues)
	{
		$tdlabel = @()

		# Conserve et tri les labels en fonction de $IncludeLabel
		$issueLabels = $issue.labels | % Name
		$issueLabels = $labels.Values | ? { $issueLabels -contains $_.name }

		# td
		# On corrige le nom des labels commençant par "_ " ou "x "
		$issueLabels | % { $tdlabel += ("<span class=`"label-$($_.id)`">" + [System.Web.HttpUtility]::HtmlEncode(($_.Name -replace '^. ', '')) + "</span> ") }
		$td = "<td class=""label-$($issueLabels[0].id)"">$($tdlabel -join ' ')</td>"

		# Div de la description
		$divDescription = "<div class=`"description`">$($issue.body)</div>`n"

		# Création du tr
		$trlist += "<tr>"
		$trlist += $td
		$trlist += "<td>"
		$trlist += "<a href=`"$($issue.html_url)`">#$($issue.number)</a> <span class=`"title`">$($issue.title)<span>"
		$trlist += $divDescription
		$trlist += "</td>`n</tr>`n"
	}

	# Génération HTML
	$template = Get-Content 'dev:\build\.dev\files\github-changelog.html' -Raw
	mkdir (Split-Path $Output -Parent) -Force | Out-Null # Créé le dossier si il n'existe pas
	(($template -Replace "%TR%",$trlist) -replace "%LABELS%", $labelsStyle) -replace "%MIL%",$milestoneDiv | Out-File -FilePath $Output -Encoding utf8 -Force

	# Ouverture du fichier dans Edge
	&"${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" (gi $Output).FullName
	#endregion
}