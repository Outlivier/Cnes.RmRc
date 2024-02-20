<#
.SYNOPSIS
	Wrapper de Invoke-RestMethod pour l'API GitHub.
.DESCRIPTION
	Permet de gérer automatiquement la pagination.
	On ne supporte que la méthode Get.
	Source complète : https://github.com/microsoft/PowerShellForGitHub/blob/master/GitHubCore.ps1
.PARAMETER Uri
	URI à laquelle la requête Web est envoyée.
.FUNCTIONALITY
    GitHub
.EXAMPLE
    PS> Invoke-GitHubRestMethod "https://api.github.com/repos/pester/Pester/issues"
	Récupère la liste des tickets du projet Pester.
#>
function Invoke-GitHubRestMethod
{
	[CmdletBinding()]
	[OutputType([PSObject])]
	param
	(
		[Parameter(Position=0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[ValidateNotNull()]
		[string]$Uri
	)

	BEGIN
	{
		$headers = Get-GitHubRestHeader

		# Initialisation des variables
		$hasNextPage = $true
		$page = 1
	}
	PROCESS
	{
		while ($hasNextPage)
		{
			# Construit la requête
			$uriBuilder = [UriBuilder]$Uri
			$queryBuilder = [System.Web.HttpUtility]::ParseQueryString($uriBuilder.Query)
			if ($page -gt 1)
			{
				$queryBuilder.Add("page", $page)
			}
			$uriBuilder.Query = $queryBuilder.ToString()
			$uri = $uriBuilder.Uri.ToString()

			# Invoke
			#  | % { $_ } : Comme on fait plusieurs passes avec la pagination, permet de retourner un pipeline continu
			#  au lieu de plusieurs tableaux
			Invoke-RestMethod $Uri -Headers $headers -ResponseHeadersVariable "responseHeader" | % { $_ }

			# Gestion de la pagination
			$hasNextPage = $false
			if ($responseHeader.link -split ',' | ? { $_ -match '<(.*page=(\d+)[^\d]*)>; rel="next"' })
			{
				$page = [int]$Matches[2]
				$hasNextPage = $true
			}
		}
    }
}