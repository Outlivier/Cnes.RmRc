<#
.SYNOPSIS
	Obtient les Headers HTTP nécessaires pour appeler l'API REST GitHub.
.DESCRIPTION
	Ces Headers sont :
	* Authorization = 'token $token'
	* Accept        = 'application/vnd.github.v3+json'

	Le token est lu via la commande `git config --get github.token`.
.FUNCTIONALITY
    GitHub
.LINK
    Add-GitHubToken.
.EXAMPLE
    PS> $headers = Get-GitHubRestHeader
	PS> $headers += @{ 'header-name' = 'value' }
	PS> $headers = [PSCustomObject]$headers

	Récupère les headers et en ajoute un avant de le transformer en PSCustomObject.
#>
function Get-GitHubRestHeader
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param()

	$token = git config --get github.token
	if (!$token)
	{
		Write-Error -Message "Le jeton d'accès GitHub n'a pas été défini. Utilisez Initialize-Environment pour l'ajouter." -ErrorAction Stop -Category AuthenticationError -ErrorId "GitHubTokenMissing"
	}

	@{ 'Authorization' = "token $token"; 'Accept' = 'application/vnd.github.v3+json' }
}