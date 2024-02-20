$pRoot = (gi -path $PSScriptRoot).Parent.Parent.FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar)

#
# Importe les cmdlets
#
foreach ($cmdlet in (gci "$PSScriptRoot\fct*" -Recurse -Filter "*.ps1"))
{
	. $cmdlet.FullName | Out-Null
	$fctName = $cmdlet.NameWithoutExtension
	if ($fctName -notmatch "private$")
	{
		Export-ModuleMember -Function $fctName -Alias * | Out-Null
	}
}

#
# Création de drives PowerShell afin de faciliter la gestion des chemins d'accès
#
$drives = @(@{ Name = 'dev'; Path = $pRoot }, @{ Name = 'nasdev'; Path = "\\nas\devel" })
foreach ($drive in $drives)
{
	Remove-PSDrive $drive.Name -Force -Erroraction Ignore
	New-PSDrive -Name $drive.Name -PSProvider 'FileSystem' -Root $drive.Path -Scope Global
	# Ajout une variable pour les cas où même PSNativePSPathResolution ne fonctionne pas
	# (généralement des appels .NET Framework ou certaines lignes de commande)
	$varName = $drive.Name
	New-Variable -Name $varName -Value $drive.Path -Description "Alternative au PSDrive $($drive.Name)." -Scope Local
	Export-ModuleMember -Variable $varName
}

#
# Gestion des requirements
#
# Ajout une variable d'environnement pour l'installation des modules
if (!(Test-Path 'env:\PSModulePath_CU')) { $env:PSModulePath_CU = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules' }