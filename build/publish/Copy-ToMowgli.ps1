<#
.SYNOPSIS
	Copie la solution Visual Studio dans MOWGLI et compile la DLL.
.DESCRIPTION
	Le chemin de MOWGLI doit avoir été saisi lors de l'initialisation du projet (Initialize-Environment.ps1).
#>
[CmdletBinding()]
param()
. "$PSScriptRoot\..\..\console.ps1"

Copy-ToMowgli -Target mowgli