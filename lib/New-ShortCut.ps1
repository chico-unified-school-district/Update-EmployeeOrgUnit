<#
Thanks!
https://stackoverflow.com/questions/31459938/creating-a-directory-shortcut-in-powershell
https://renenyffenegger.ch/development/Windows/PowerShell/examples/WinAPI/ExtractIconEx/imageres.html
#>
function New-Shortcut {
 [cmdletbinding()]
 param(
  [Parameter(Mandatory = $True)]
  $Samid,
  [Parameter(Mandatory = $True)]
  [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 2 })]
  $FileServer,
  [Parameter(Mandatory = $True)]
  $ShareName,
  [Parameter(Mandatory = $True)]
  $ShortCutName,
  [Parameter(Mandatory = $True)]
  $TargetPath,
  [Parameter(Mandatory = $True)]
  [System.Management.Automation.PSCredential]$FileServerCredential,
  [switch]$WhatIf
 )

 $scLocation = '.\{0}.lnk' -f $ShortCutName

 $wsshell = New-Object -ComObject WScript.Shell
 $lnk = $wsshell.CreateShortcut($scLocation)
 $lnk.WindowStyle = 1
 $lnk.TargetPath = $TargetPath
 $lnk.Description = 'Shortcut to previous data'
 # $lnk.Arguments = $args
 $lnk.IconLocation = "imageres.dll,3"

 $msg = $MyInvocation.MyCommand.Name, $Samid, $FileServer, $scLocation
 Write-Host ('{0},[{1}],Dest:[{2}], Name:[{3}]' -f $msg) -Fore Green

 if ($WhatIf) {
  Write-Host ( $lnk | Out-String ) -Fore DarkCyan
 }
 else {
  $lnk.save() # This will overwrite the previous link if it existed
  $myNewDrive = '{0}:' -f $FileServer
  $myRoot = '\\{0}\{1}\{2}\Documents' -f $FileServer, $ShareName, $Samid
  $newDrive = @{
   Name       = $FileServer
   Root       = $myRoot
   PSProvider = 'FileSystem'
   Credential = $FileServerCredential
  }
  New-PSDrive @newDrive | Out-Null
  Move-Item -Path $scLocation -Destination $myNewDrive -Force -Confirm:$false
  Remove-PSDrive -Name $FileServer -Confirm:$false -Force
 }
}
