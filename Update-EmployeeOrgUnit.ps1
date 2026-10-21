<#
.SYNOPSIS
  Pull data from Employee Database (Escape Online) and
  update Active Direcrtory user object attrbutes using employeeId as the foreign key.
.DESCRIPTION
.EXAMPLE
.\Update-EmployeeOrgUnit.ps1 -DomainController DC1.our.org -ADCredential $adCredObj -SearchBase 'OU=Employees,DC=our,DC=org' -SQLServer EscapeDBServer.our.org -SQLDatabase EscapeOnline -SQLCred $sqlCredObj
.EXAMPLE
  .\Update-EmployeeOrgUnit.ps1-DomainController DC1.our.org -ADCredential $adCredObj -SearchBase 'OU=Employees,DC=our,DC=org' -SQLServer EscapeDBServer.our.org -SQLDatabase EscapeOnline -SQLCred $sqlCredObj -WhatIf -Verbose -Debug
.INPUTS
  Common parameters are used as inputs.
.OUTPUTS
.NOTES
Special Thanks:
http://woshub.com/powershell-get-folder-sizes/
#>

[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)]
 [Alias('DCs')]
 [string[]]$DomainControllers,
 [Parameter(Mandatory = $True)]
 [Alias('ADCred')]
 [System.Management.Automation.PSCredential]$ADCredential,
 # # Used for building a target ou
 [Parameter(Mandatory = $True)]
 [string]$EmployeeRootOU,
 # Isolate/limit source user objects
 [Parameter(Mandatory = $True)]
 [string]$ADSearchBase,
 [string]$CreationCutOff,
 [Parameter(Mandatory = $True)]
 [string]$SQLServerEmployees,
 [Parameter(Mandatory = $True)]
 [string]$SQLDatabaseEmployees,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$SQLCredentialEmployees,
 [Parameter(Mandatory = $True)]
 [string]$SQLiteSiteRefDatabase,
 # [Parameter(Mandatory = $True)]
 # [System.Management.Automation.PSCredential]$FileServerCredential,
 [switch]$Check,
 [Alias('wi')]
 [SWITCH]$WhatIf
)

function Compare-OU {
 process {
  Write-Verbose ('{0},{1},[{2}],[{3}]' -f $MyInvocation.MyCommand.Name, $_.ad.SamAccountName, $_.oldNew.old, $_.oldNew.new)
  if ($_.oldNew.old -eq $_.oldNew.new) { return }
  $_
 }
}

function Complete-Processing {
 process {
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.emp.EmpID, $_.ad.SamAccountName) -F Green
  Write-Verbose ($MyInvocation.MyCommand.Name, $_ | Out-String)
  if ($Check) { Read-Host }
 }
}

function Get-ADData ([pscredential]$cred) {
 $properties = 'EmployeeID', 'extensionAttribute1', 'departmentNumber', 'whenCreated'
 $filter = "EmployeeID -like '*' -and mail -like '*@*' -and -not(employeeType -eq 'student')"
 $params = @{
  Filter     = $filter
  Properties = $properties
  Credential = $cred
 }
 $adResults = Get-ADUser @params | Sort-Object -Property whenCreated
 Write-Host ('{0},count:{1}' -f $MyInvocation.MyCommand.Name, @($adResults).count) -F DarkGreen
 $adResults
}

# function Get-ADData ($ou) {
#  $properties = 'EmployeeID', 'extensionAttribute1', 'departmentNumber', 'whenCreated'
#  $adResults = Get-ADUser -Filter "EmployeeID -like '*' -and mail -like '*@*'" -SearchBase $ou -Properties $properties | Sort-Object -Property whenCreated
#  Write-Host ('{0},count:{1}' -f $MyInvocation.MyCommand.Name, @($adResults).count) -F DarkGreen
#  $adResults
# }

function Get-EmployeeData ($sqlParams) {
 $query = Get-Content -Path '.\sql\active-employees.sql' -Raw
 $data = New-SqlOperation @sqlParams -Query $query
 Write-Host ('{0},Count:{1}' -f $MyInvocation.MyCommand.Name, @($data).count) -f Green
 $data | ConvertTo-Csv | ConvertFrom-Csv
}

function Get-RecentAccounts ($cutOff) {
 process {
  if (!$cutOff) { return $_ }
  if ($_.whenCreated -gt $cutOff) {
   Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.SamAccountName, $_.whenCreated)
   $_
  }
 }
}

function New-Obj {
 process {
  [PSCustomObject]@{
   emp      = $_
   ad       = $null
   levelOU  = $null
   siteData = $null
   targetOU = $null
   oldNew   = $null
  }
 }
}

function Set-ADData ($data) {
 process {
  $id = $_.emp.EmpId
  $_.ad = $data.Where({ $_.EmployeeID -eq $id })
  if (!$_.ad) { return } # Skip if AD object not present
  $_
 }
}

function Set-LevelOU ($tData, $altJData) {
 process {
  $jobCatDesc = $_.emp.JobCategoryDescr
  $altJob = $altJData.Where({ $_.JobCategoryDescr -eq $jobCatDesc })

  $_.levelOU = if ([int]$_.emp.SiteID -eq 999) { $null }
  elseif ([int]$_.emp.SiteID -ge 500 ) { 'District Services' }
  else {
   if ($altJob) {
    Write-Verbose ('{0},{1},Alt Job detected [{2}]' -f $MyInvocation.MyCommand.Name, $_.ad.SamAccountName, $altJob.OU)
    $altJob.OU
   }
   else {
    $bargID = $_.emp.BargUnitID
    ($tData.Where({ $_.barGUnitID -eq $bargID })).type
   }
  }
  $_
 }
}

function Set-OldNewOUData ($rootOU) {
 process {
  $_.oldNew = [PSCustomObject]@{
   'old' = $_.ad.DistinguishedName.Replace(",$rootOU", '').Split(',')[1..100] -join ','
   'new' = $_.targetOU.Replace(",$rootOU", '')
  }
  $_
 }
}

function Set-SiteData ($data) {
 process {
  $id = $_.emp.SiteID
  $_.siteData = $data.Where({ $_.siteCode -eq $id })
  if (!$_.siteData) { return } # Skip if no site match found
  $_
 }
}

function Set-TargetOU ($ou) {
 begin {
  $rootOU = $ou.Trim('OU').Trim('=')
 }
 process {
  $_.targetOU = if ([int]$_.emp.SiteID -ge 500) {
   if ($_.levelOU -and $_.siteData.areaOU) {
    'OU={0},OU={1},OU={2}' -f $_.siteData.deptOU , $_.levelOU, $rootOU
   }
  }
  else {
   if ($_.levelOU -and $_.siteData.areaOU -and $_.siteData.deptOU) {
    'OU={0},OU={1},OU={2},OU={3}' -f $_.siteData.deptOU, $_.siteData.areaOU, $_.levelOU, $rootOU
   }
  }
  if (!$_.targetOU) {
   $msg = $MyInvocation.MyCommand.Name, $_.ad.SamAccountName, $_.emp.SiteID, $_.siteData.siteDesc
   return (Write-Host ('{0},{1},No target OU detected for site {2} - {3}' -f $msg) -F Red)
  } # Skip if no target OU detected
  $_
 }
}

function Test-OU ($ou) {
 begin { $allOrgUnits = Get-ADOrganizationalUnit -Filter 'Name -like "*"' -SearchBase $ou }
 process {
  $targOU = $_.targetOU
  $ou = $allOrgUnits.Where({ $_.DistinguishedName -eq $targOU })
  if (!$ou) {
   Write-Host ('{0},{1},OU NOT FOUND:[{2}]' -f $MyInvocation.MyCommand.Name, $_.emp.EmpID, $_.targetOU) -F Red
  }
  $_
 }
}

function Update-OU {
 process {
  if (!$_.targetOU) { return $_ }
  Write-Host ('{0},{1},OLD:[{2}],NEW:[{3}]' -f $MyInvocation.MyCommand.Name, $_.ad.SamAccountName, $_.oldNew.old, $_.oldNew.new) -F Magenta
  Move-ADObject -Identity $_.ad.ObjectGUID -TargetPath $_.targetOU -Confirm:$false -WhatIf:$WhatIf
  $_
 }
}

# =====================================================================================
Import-Module -Name 'dbatools', 'CommonScriptFunctions', 'PSSqlite'
Show-BlockInfo Main
if ($WhatIf) { Show-TestRun }

$cmdlets = 'Get-ADUser', 'Move-ADObject', 'Get-ADOrganizationalUnit'
Connect-ADSession $DomainControllers $ADCredential $cmdlets

$siteData = Invoke-SqliteQuery -DataSource $SQLiteSiteRefDatabase -Query 'SELECT * FROM site_data'
$typeData = Invoke-SqliteQuery -DataSource $SQLiteSiteRefDatabase -Query 'SELECT * FROM type_data'
$nonTeachingSql = "SELECT * from alt_job_categories WHERE OU = 'Non-Teaching'"
$altJobData = Invoke-SqliteQuery -DataSource $SQLiteSiteRefDatabase -Query $nonTeachingSql

$empDBParams = @{
 Server     = $SQLServerEmployees
 Database   = $SQLDatabaseEmployees
 Credential = $SQLCredentialEmployees
}

$empData = Get-EmployeeData $empDBParams
$adData = Get-ADData $ADSearchBase | Get-RecentAccounts $CreationCutOff

$empData |
 New-Obj |
  Set-ADData $adData |
   Set-SiteData $siteData |
    Set-LevelOU $typeData $altJobData |
     Set-TargetOU $EmployeeRootOU |
      Set-OldNewOUData $EmployeeRootOU |
       Test-OU $EmployeeRootOU |
        Compare-OU |
         Update-OU |
          Complete-Processing

if ($WhatIf) { Show-TestRun }
Show-BlockInfo end