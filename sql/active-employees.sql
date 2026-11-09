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
  -- AND EmpID in (99999999)
  AND DateTimeEdited > DATEADD(day,-14,getdate())
ORDER BY empId;