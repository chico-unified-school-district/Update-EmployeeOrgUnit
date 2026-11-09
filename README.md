# Update-EmployeeOrgUnit

Updates Active Directory employee organizational-unit (OU) placement using
employee and site reference data. Employees are matched between the employee
database and Active Directory by employee ID.

## How it works

The script:

1. Reads employee records from `vwHREmploymentList` using
   [`sql/active-employees.sql`](./sql/active-employees.sql). The query excludes
   records with employment status `R` or `T` and blank site IDs, and includes
   only records edited within the previous 14 days; it is not a full extract of
   all active employees. It returns employee ID, site, bargaining-unit, and job
   category data used by the OU mapping.
2. Reads site, bargaining-unit, and alternate-job-category mappings from a
   SQLite reference database.
3. Finds enabled, non-student, non-service, non-generic Active Directory users
   with an employee ID and email address under `EmployeeRootOU`.
4. Builds a target OU from the employee's site and job classification, compares
   it with the user's current OU, and moves users whose OU needs to change.
   Alternate job-category mappings override the bargaining-unit mapping. Site
   IDs of 500 or greater use the district-services OU pattern; site ID 999
   does not produce a target OU.

Employees without a matching AD account, site mapping, or computable target OU
are skipped. Accounts whose `info` attribute contains `Prevent OrgUnit Update`
are also skipped. The script reports target OUs that it cannot find in Active
Directory, but still attempts those moves when run without `-WhatIf`; review
the reported OUs and proposed changes before allowing changes. Without
`-WhatIf`, it runs an initial pass and then repeats hourly until its local
5:00 PM stopping-time check succeeds. Since the check follows the hourly sleep,
the final pass can end after 5:00 PM. A `-WhatIf` run performs one pass.

## Requirements

Run from a Windows computer with network access to Active Directory and the
employee SQL Server. The supplied AD credential must be able to query the
`EmployeeRootOU` subtree and move relevant AD objects. The SQL credential must
be able to query the employee data.

The script imports these PowerShell modules:

- `ActiveDirectory`
- `dbatools`
- `PSSqlite`
- `CommonScriptFunctions`

The SQLite reference database must contain these tables:

- `site_data`: `siteCode`, `siteDesc`, `siteAbbrv`, `deptOU`, and `areaOU`
- `type_data`: `bargUnitId` and `type`
- `alt_job_categories`: `JobCategoryDescr` and `OU`

Matching rows in `alt_job_categories` use their `OU` value to override the
usual bargaining-unit mapping for that job category. The schema reference also
includes a `site_servers` table, which this script does not currently query.
[`sqlite/CreateSitesTableStatement.sql`](./sqlite/CreateSitesTableStatement.sql)
lists these table definitions, but is not ready to execute as-is; create or
update the database so it contains the required tables before running.

## Run

From the repository root, load the script's required credentials and supply the
connection details and distinguished names for your environment:

```powershell
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
```

Review the `-WhatIf` output before running for real. Remove `-WhatIf` to allow
the script to move AD objects. Use `-Wait` to pause for input before each move;
pressing Enter continues the move and does not cancel it. Use `-Log` to write
account identifiers and old/new OU details to
`.\logs\Update-EmployeeOrgUnit-<name>.log`; the `logs` directory must exist.
Use `-LogName <name>` to set the filename suffix (a timestamp is used if omitted).
`-LogName` only affects the output when `-Log` is also specified. The SQL query
and SQLite database paths are resolved relative to the current working directory.

## Reference files

- [`params.ps1`](./params.ps1) contains example local parameter configuration.
- [`jenkins.ps1`](./jenkins.ps1) shows the Jenkins job wrapper and environment
  variable usage.
- [`sqlite/`](./sqlite) contains SQLite schema and example reference data.
