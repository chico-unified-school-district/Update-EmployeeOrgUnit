<#
.SYNOPSIS
  Update Active Directory employee organizational-unit placement from employee and site data.
.DESCRIPTION
  Reads recent employee records from sql\active-employees.sql and site and job
  mappings from the SQLite reference database. Employees are matched to enabled,
  eligible Active Directory users by employee ID. The script builds a target OU
  from each employee's site and job classification and moves users whose
  current OU does not match that target.

  Employees without an AD match, a site mapping, or a target OU are skipped.
  Accounts whose info attribute contains "Prevent OrgUnit Update" are also
  skipped. Target OUs that cannot be found are reported, but the script still
  attempts the move unless -WhatIf is used. Review the output before allowing
  changes.

  -WhatIf performs one pass without moving AD objects. Without -WhatIf, the
  script runs a pass immediately and repeats hourly until its local 5:00 PM
  stopping-time check succeeds. The check occurs after each hourly sleep, so the
  final pass can end after 5:00 PM.

  The SQL query and SQLite path are resolved relative to the current working
  directory. Use -Log to write processed account and OU details under .\logs;
  -LogName sets the log filename suffix. Use -Wait to pause before each move;
  pressing Enter continues the move and does not cancel it.
.EXAMPLE
  $adCredential = Get-Credential
  $sqlCredential = Get-Credential
  .\Update-EmployeeOrgUnit.ps1 `
    -ADCredential $adCredential `
    -EmployeeRootOU 'OU=Employees,OU=Users,OU=Root,DC=example,DC=org' `
    -SQLServerEmployees 'sql.example.org' `
    -SQLDatabaseEmployees 'EmployeeDatabase' `
    -SQLCredentialEmployees $sqlCredential `
    -SQLiteSiteRefDatabase '.\sqlite\sites.db' `
    -WhatIf -Verbose

  Reads the configured data and previews one pass without moving AD objects.
.EXAMPLE
  .\Update-EmployeeOrgUnit.ps1 `
    -ADCredential $adCredential `
    -EmployeeRootOU 'OU=Employees,OU=Users,OU=Root,DC=example,DC=org' `
    -SQLServerEmployees 'sql.example.org' `
    -SQLDatabaseEmployees 'EmployeeDatabase' `
    -SQLCredentialEmployees $sqlCredential `
    -SQLiteSiteRefDatabase '.\sqlite\sites.db' `
    -Log -LogName 'preview' -WhatIf

  Previews one pass and writes processed account and OU details to
  .\logs\Update-EmployeeOrgUnit-preview.log.
.INPUTS
  Required parameters:
    -ADCredential          Credential used to query and move AD objects.
    -EmployeeRootOU        Root OU used to search for AD users and construct
                           target distinguished names.
    -SQLServerEmployees    SQL Server hosting employee data.
    -SQLDatabaseEmployees  Employee database name.
    -SQLCredentialEmployees Credential used to query employee data.
    -SQLiteSiteRefDatabase Path to the SQLite site and job reference database.

  Optional parameters:
    -Log                   Write processed account and OU details to a log.
    -LogName               Log filename suffix.
    -Wait                  Pause for input before each move.
    -WhatIf (-wi)           Preview moves without applying them.
.OUTPUTS
  Processing messages are written to the console. The script does not define a
  structured output contract.
.NOTES
  Requires the ActiveDirectory, dbatools, PSSqlite, and CommonScriptFunctions
  modules, and access to the configured SQL Server, SQLite database, and AD.
  See README.md for database requirements and usage details.
#>

[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)][PSCredential]$ADCredential,
 # # Used for building a target ou
 [Parameter(Mandatory = $True)][string]$EmployeeRootOU,
 [Parameter(Mandatory = $True)][string]$SQLServerEmployees,
 [Parameter(Mandatory = $True)][string]$SQLDatabaseEmployees,
 [Parameter(Mandatory = $True)][PSCredential]$SQLCredentialEmployees,
 [Parameter(Mandatory = $True)][string]$SQLiteSiteRefDatabase,
 [Parameter(Mandatory = $False)][string]$LogName,
 [switch]$Log,
 [switch]$Wait,
 [Alias('wi')][SWITCH]$WhatIf
)

function Compare-OU {
 process {
  # Write-Verbose ('{0},{1},[{2}],[{3}]' -f $MyInvocation.MyCommand.Name, $_.ad.SamAccountName, $_.oldNew.old, $_.oldNew.new)
  # Match instead of equals due to some staff being moved into more granular sub-OUs This will prevent a unneeded moves.
  if ($_.oldNew.old -match $_.oldNew.new) { return }
  $_
 }
}

function Get-ADData ($ou, [pscredential]$cred) {
 $properties = 'EmployeeID', 'extensionAttribute1',
 'departmentNumber', 'Description', 'info', 'whenCreated'
 $filter = "
 Enabled -eq 'True' -and
 EmployeeID -like '*' -and
 Mail -like '*@*' -and
 -not(employeeType -eq 'student') -and
 -not(Description -like '*Service*') -and
 -not(Description -like '*Generic*') -and
 -not(Title -like '*Service*') -and
 -not(Title -like '*Generic*')
 "
 $params = @{
  Filter     = $filter
  Properties = $properties
  SearchBase = $ou
  Credential = $cred
 }
 $adResults = Get-ADUser @params | Group-Object -Property EmployeeID -AsHashTable
 # $adResults = Get-ADUser @params | Where-Object { $_.SurName -like 'U*' } | Group-Object -Property EmployeeID -AsHashTable
 Write-Host ('{0},{1},count:{2}' -f $MyInvocation.MyCommand.Name, $ou, @($adResults.values).count) -F Green
 $adResults
}

function Get-EmployeeData ($sqlParams) {
 $query = Get-Content -Path '.\sql\active-employees.sql' -Raw
 $data = New-SqlOperation @sqlParams -Query $query
 Write-Host ('{0},Count:{1}' -f $MyInvocation.MyCommand.Name, @($data).count) -f Green
 $data | ConvertTo-Csv | ConvertFrom-Csv
}

function New-Obj {
 process {
  [PSCustomObject]@{
   emp      = $_
   ad       = $null
   info     = $null
   levelOU  = $null
   siteData = $null
   targetOU = $null
   oldNew   = $null
  }
 }
}

function Set-PropAD ($data) {
 process {
  $id = $_.emp.EmpId
  if (!$id) { return } # Skip if ID  not present
  $_.ad = $data["$id"]
  if (!$_.ad) { return } # Skip if AD object not present
  $_
 }
}

function Set-PropInfo {
 process {
  $_.info = '[{0},{1},{2}]' -f $_.emp.EmpId, $_.ad.SamAccountName, $_.ad.Description
  $_
 }
}

function Set-PropLevelOU ($tData, $altJData) {
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

function Set-PropOldNewOUData ($rootOU) {
 process {
  $_.oldNew = [PSCustomObject]@{
   'old' = $_.ad.DistinguishedName.Replace(",$rootOU", '').Split(',')[1..100] -join ','
   'new' = $_.targetOU.Replace(",$rootOU", '')
  }
  $_
 }
}

function Set-PropSiteData ($data) {
 process {
  $id = $_.emp.SiteID
  $_.siteData = $data.Where({ $_.siteCode -eq $id })
  if (!$_.siteData) { return } # Skip if no site match found
  $_
 }
}

function Set-PropTargetOU ($ou) {
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
   $msg = $MyInvocation.MyCommand.Name, $_.info, $_.emp.SiteID, $_.siteData.siteDesc
   return (Write-Host ('{0},{1},No target OU detected for site {2} - {3}' -f $msg) -F Red)
  } # Skip if no target OU detected
  $_
 }
}

function Skip-Exception {
 process {
  if ($_.ad.info -match 'Prevent OrgUnit Update') {
   Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.info) -f Blue
   return
  }
  $_
 }
}

function Show-Object {
 process {
  Write-Verbose ($MyInvocation.MyCommand.Name, $_ | Out-String)
  # if ($Wait) { Read-Host 'Proceed?' }
 }
}


function Test-OU ($ou, [pscredential]$cred) {
 begin { $allOrgUnits = Get-ADOrganizationalUnit -Filter 'Name -like "*"' -SearchBase $ou -Credential $cred }
 process {
  $targOU = $_.targetOU
  $ou = $allOrgUnits.Where({ $_.DistinguishedName -eq $targOU })
  if (!$ou) {
   Write-Host ('{0},{1},OU NOT FOUND:[{2}]' -f $MyInvocation.MyCommand.Name, $_.emp.EmpID, $_.targetOU) -F Red
  }
  $_
 }
}

function Update-OU ([pscredential]$cred) {
 begin {
  $i = 0
  $list = @()
  if (!$LoGName) { $LogName = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') }
  $logFilePath = ".\logs\Update-EmployeeOrgUnit-$LogName.log"
  if ($Log) { 'empid|old_ou|new_ou' | Out-File -FilePath $logFilePath -Encoding UTF8 -Force }
 }
 process {
  if (!$_.targetOU) { return $_ }
  $params = @{
   Identity   = $_.ad.ObjectGUID
   TargetPath = $_.targetOU
   Credential = $cred
   Confirm    = $false
   WhatIf     = $WhatIf
  }
  $i++
  if ($Log) { $list += '{0}|{1}|{2}' -f $_.ad.SamAccountName, $_.oldNew.old, $_.oldNew.new }
  $msg = $MyInvocation.MyCommand.Name, $_.info, $_.oldNew.old, $_.oldNew.new
  Write-Host ('{0},{1},OLD:{2},NEW:{3}' -f $msg) -F Magenta
  if ($Wait) { Read-Host 'Proceed with OrgUnit update?' }
  Move-ADObject @params
  $_
 }
 end {
  Write-Host ('{0},Total Updated:{1}' -f $MyInvocation.MyCommand.Name, $i) -F Green
  if ($Log) { $list | Out-File -FilePath $logFilePath -Encoding UTF8 -Append -Force }
 }
}

# =====================================================================================
Show-BlockInfo Start
Import-Module -Name 'CommonScriptFunctions', 'PSSqlite'
Import-Module -Name dbatools -Cmdlet Invoke-DbaQuery, Set-DbatoolsConfig, Connect-DbaInstance, Disconnect-DbaInstance
Import-Module -Name ActiveDirectory -Cmdlet 'Get-ADUser', 'Move-ADObject', 'Get-ADOrganizationalUnit' -WarningAction SilentlyContinue -ErrorAction Stop
Show-BlockInfo Main
if ($WhatIf) { Show-TestRun }

$siteData = Invoke-SqliteQuery -DataSource $SQLiteSiteRefDatabase -Query 'SELECT * FROM site_data'
$typeData = Invoke-SqliteQuery -DataSource $SQLiteSiteRefDatabase -Query 'SELECT * FROM type_data'
$nonTeachingSql = 'SELECT * from alt_job_categories'
# $nonTeachingSql = "SELECT * from alt_job_categories WHERE OU = 'Non-Teaching'"
$altJobData = Invoke-SqliteQuery -DataSource $SQLiteSiteRefDatabase -Query $nonTeachingSql

$empDBParams = @{
 Server     = $SQLServerEmployees
 Database   = $SQLDatabaseEmployees
 Credential = $SQLCredentialEmployees
}

$stopTime = Get-Date '5:00PM'
if (!$WhatIf) { Write-Host ('{0},Stop Time:{1}' -f $MyInvocation.MyCommand.Name, $stopTime) -F Green }
do {
 $empData = Get-EmployeeData $empDBParams
 $adData = Get-ADData -ou $EmployeeRootOU -cred $ADCredential

 $empData |
  New-Obj |
   Set-PropAD -data $adData |
    Set-PropInfo |
     Skip-Exception |
      Set-PropSiteData -data $siteData |
       Set-PropLevelOU $typeData $altJobData |
        Set-PropTargetOU $EmployeeRootOU |
         Set-PropOldNewOUData $EmployeeRootOU |
          Test-OU $EmployeeRootOU $ADCredential |
           Compare-OU |
            Update-OU -cred $ADCredential |
             Show-Object

 if ($WhatIf) { break }
 Write-Host ('{0},Next run at {1}' -f $MyInvocation.MyCommand.Name, (Get-Date).AddMinutes(3600)) -F Green
 Start-Sleep -Seconds 3600
} until ((Get-Date) -gt (Get-Date $stopTime))

if ($WhatIf) { Show-TestRun }
Show-BlockInfo end