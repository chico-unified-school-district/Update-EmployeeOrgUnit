# Update-EmployeeOrgUnit

Updates Active Directory employee organizational-unit (OU) placement using
employee and site reference data. Employees are matched between the employee
database and Active Directory by employee ID.

## How it works

The script:

1. Reads employee records from `vwHREmploymentList` using
   [`sql/active-employees.sql`](./sql/active-employees.sql).
2. Reads site, bargaining-unit, and alternate-job-category mappings from a
   SQLite reference database.
3. Finds enabled, non-student, non-service, non-generic Active Directory users
   with an employee ID and email address under the configured search base.
4. Builds a target OU from the employee's site and job classification, compares
   it with the user's current OU, and moves users whose OU needs to change.

Employees without a matching AD account, site mapping, or computable target OU
are skipped. The script reports target OUs that it cannot find in Active
Directory; review those messages and the proposed changes before running
without `-WhatIf`.

## Requirements

Run from a Windows computer with network access to Active Directory and the
employee SQL Server. The account credentials must have permission to read the
employee data and query/move the relevant AD objects.

The script imports these PowerShell modules:

- `ActiveDirectory`
- `dbatools`
- `PSSqlite`
- `CommonScriptFunctions`

The SQLite reference database must contain these tables:

- `site_data`: `siteCode`, `siteDesc`, `siteAbbrv`, `deptOU`, and `areaOU`
- `type_data`: `bargUnitId` and `type`
- `alt_job_categories`: `JobCategoryDescr` and `OU`

The script uses rows in `alt_job_categories` where `OU` is `Non-Teaching` to
override the usual bargaining-unit mapping for matching job categories.
[`sqlite/CreateSitesTableStatement.sql`](./sqlite/CreateSitesTableStatement.sql)
shows part of the reference schema; make sure the database also has the
`alt_job_categories` table before running.

## Run

From the repository root, load the script's required credentials and supply the
connection details and distinguished names for your environment:

```powershell
$adCredential = Get-Credential
$sqlCredential = Get-Credential

.\Update-EmployeeOrgUnit.ps1 `
  -ADCredential $adCredential `
  -EmployeeRootOU 'OU=Employees,OU=Users,OU=Root,DC=example,DC=org' `
  -ADSearchBase 'OU=Employees,OU=Users,OU=Root,DC=example,DC=org' `
  -CreationCutOff 'May 1 2025' `
  -SQLServerEmployees 'sql.example.org' `
  -SQLDatabaseEmployees 'EmployeeDatabase' `
  -SQLCredentialEmployees $sqlCredential `
  -SQLiteSiteRefDatabase '.\sqlite\sites.db' `
  -WhatIf -Verbose
```

`CreationCutOff` is currently accepted as a required parameter but is not used
to filter accounts. The script's active-employee query and AD filters determine
which records are processed.

Review the `-WhatIf` output before running for real. Remove `-WhatIf` to allow
the script to move AD objects. Use `-Wait` to pause for input before each move;
the script proceeds after that input and does not use it to cancel the move.
The SQLite database path is resolved relative to the current working directory.

## Reference files

- [`params.ps1`](./params.ps1) contains example local parameter configuration.
- [`jenkins.ps1`](./jenkins.ps1) shows the Jenkins job wrapper and environment
  variable usage.
- [`sqlite/`](./sqlite) contains SQLite schema and example reference data.
