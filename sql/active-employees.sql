SELECT
    EmpId,
  -- If NameFirstPreferred is present then use this as first name
		(CASE
		WHEN NameFirstPreferred <> ''
		   THEN NameFirstPreferred
		ELSE NameFirst
		END
	 + ' ' + NameLast) AS FullName
  , CASE
     WHEN NameFirstPreferred <> ''
      THEN NameFirstPreferred
     ELSE NameFirst
     END AS NameFirst
    , NameLast
    , NameMiddle
    , BargUnitID
    , EmailWork
    , SiteId
    , SiteDescr
    , JobClassDescr
    , JobCategoryDescr
FROM vwHREmploymentList
WHERE
  EmploymentStatusCode NOT IN ('R','T')
  AND SiteID <> ''
  -- AND JobCategoryDescr <> 'Instructional Assistance'
  -- AND BargUnitID IN ('CSEA', 'CUTA', 'REST', 'CUMA')
  -- AND EmpID in (99999999)
  -- AND PersonTypeId IN (1,2,4,6)
  AND DateTimeEdited > DATEADD(day,-14,getdate())
ORDER BY empId;