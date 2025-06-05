CREATE TABLE "site_data" (
	"siteCode"	INTEGER,
	"siteDesc"	TEXT,
	"siteAbbrv"	TEXT,
	"deptOU"	TEXT,
	"areaOU"	TEXT
)

CREATE TABLE "type_data" (
	"bargUnitId"	TEXT,
	"type"	TEXT
)

CREATE TABLE "site_servers" (
	"SiteCode"	INTEGER,
	"SiteDescr"	TEXT,
	"Groups"	TEXT,
	"HomePath"	TEXT,
)