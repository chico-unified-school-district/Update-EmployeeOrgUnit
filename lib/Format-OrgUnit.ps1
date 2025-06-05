
[cmdletbinding()]
param(
 [Parameter(Mandatory = $True)]
 [Alias('DC')]
 [string]$DomainController,
 [Parameter(Mandatory = $True)]
 [Alias('ADCred')]
 [System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)]
 [string]$EmployeeOrgUnit,
 [Parameter(Mandatory = $True)]
 [string]$SQLServerSiteRef,
 [Parameter(Mandatory = $True)]
 [string]$SQLDatabaseSiteRef,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$SQLCredentialSiteRef,
 [Parameter(Mandatory = $True)]
 $EmployeeObj
)

function Add-SiteInfo {
 process {
  $siteData = Get-Site $siteRef $_.siteCode
  if (-not$siteData) {
   $msgVars = $MyInvocation.MyCommand.Name, $_.empId, $_.siteCode
   Write-Host ('{0},{1},{2},No Site Data' -f $msgVars)
   return
  }
  $_ | Add-Member -MemberType NoteProperty -Name siteData -Value $siteData
  $_
 }
}

function Add-OrgLevel {
 process {
  $orgLevel = $_ | Get-OrgLevel
  if (-not$orgLevel) {
   $msgVars = $MyInvocation.MyCommand.Name, $_.empId, $_.BargUnitId
   Write-Host ('{0},{1},{2},No matching BargUnitId. No org level set.' -f $msgVars)
   return
  }
  $_ | Add-Member -MemberType NoteProperty -Name orgLevel -Value $orgLevel
  $_
 }
}

function Get-OrgLevel {
 begin {
  # These Job Classes will be used to
  # route an object to a site 'Admin' OU where applicable.
  $jobClasses = 'Office', 'Mgr', 'Registrar', 'Counselor', 'Principal'
  # These BargUnitIds will be used to
  # route objects to 'Admin' or 'Teacher' OUs where applicable.
  $orgLevels = @{CSEA = 'Teacher'; CUMA = 'Admin'; CUTA = 'Teacher' ; }
 }
 process {
  # Get org level by 'JobClassDescr'
  foreach ($class in $jobClasses) {
   if ($_.JobClassDescr -match $class) {
    "Admin"
    return
   }
  }
  # Get org level by 'BargUnitId'
  if ($_.BargUnitId -match '[A-Za-z0-9]') { $orgLevels[$_.BargUnitId] }
 }
}

function Get-Site ($siteRef, $siteCode) {
 $siteRef.Where({ $_.siteCode -eq $siteCode })
}

function Get-OrgUnit {
 begin {
  $employeeOUs = Get-ADOrganizationalUnit -filter * -SearchBase $EmployeeOrgUnit
 }
 process {
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.siteCode)
  $orgUnit = $_.siteData.orgUnit
  $ouLevel = $_.orgLevel
  $targetOrgUnit = if ($_.siteCode -ge 500) {
   $employeeOus.Where({ ($_.DistinguishedName -match "^OU=$orgUnit,") })
  }
  else {
   $employeeOus.Where({ ($_.DistinguishedName -match "^OU=$orgUnit,") -and
   ($_.DistinguishedName -match "\bOU=$ouLevel,") })
  }
  $targetOrgUnit.DistinguishedName
 }
}

function Get-SiteRefData {
 $params = @{
  Server     = $SQLServerSiteRef
  Database   = $SQLDatabaseSiteRef
  Credential = $SQLCredentialSiteRef
  Query      = 'SELECT * FROM zone_ref;'
 }
 Invoke-Sqlcmd @params
}

$siteRef = Get-SiteRefData
$EmployeeObj | Add-SiteInfo | Add-OrgLevel | Get-OrgUnit