-- Get the top 5 missing indexes for each database on an instance
-- and output to a format that can be read as-is, or pasted to Excel for filtering, etc.

-- Thanks to Pinal Dave at www.sqlauthority.com for providing the base query this is built on.
-- Pinal is good guy and great teacher...you should hire him for your performance issues
-- or me, lol

-- Test in your Dev environment before trying this in Prod.  
-- I make no guarantees on performance or SQL version compatibility

-- Filtering out various things is done in the WHERE clause (impact, last_seek, etc.)


-- Create a temp table to hold the results:
CREATE TABLE [dbo].[#MI](
	[dbname] [nvarchar](128) NULL,
	[object_id] [nvarchar](255) NOT NULL,
	[improvement_measure] [bigint] NULL,
	[create_index_statement] [nvarchar](4000) NULL,
	[group_handle] [bigint] NOT NULL,
	[unique_compiles] [bigint] NOT NULL,
	[user_seeks] [bigint] NOT NULL,
	[user_scans] [bigint] NOT NULL,
	[last_user_seek] [datetime] NULL,
	[last_user_scan] [datetime] NULL,
	[avg_total_user_cost] [float] NULL,
	[avg_user_impact] [float] NULL,
	[system_seeks] [bigint] NOT NULL,
	[system_scans] [bigint] NOT NULL,
	[last_system_seek] [datetime] NULL,
	[last_system_scan] [datetime] NULL,
	[avg_total_system_cost] [float] NULL,
	[avg_system_impact] [float] NULL,
	[database_id] [int] NOT NULL	
) 

USE DBAdmin;

CREATE TABLE [dba].[MissingIndexes_history](
	[id] int identity(1,1), 
	[servername] nvarchar(30) NULL,
	[recorded_date] datetime,
	[dbname] [nvarchar](128) NULL,
	[object_id] [nvarchar](255) NOT NULL,
	[improvement_measure] [bigint] NULL,
	[create_index_statement] [nvarchar](4000) NULL,
	[group_handle] [bigint] NOT NULL,
	[unique_compiles] [bigint] NOT NULL,
	[user_seeks] [bigint] NOT NULL,
	[user_scans] [bigint] NOT NULL,
	[last_user_seek] [datetime] NULL,
	[last_user_scan] [datetime] NULL,
	[avg_total_user_cost] [float] NULL,
	[avg_user_impact] [float] NULL,
	[system_seeks] [bigint] NOT NULL,
	[system_scans] [bigint] NOT NULL,
	[last_system_seek] [datetime] NULL,
	[last_system_scan] [datetime] NULL,
	[avg_total_system_cost] [float] NULL,
	[avg_system_impact] [float] NULL,
	[database_id] [int] NOT NULL
	constraint pk_missing_indexes_history_id  primary key clustered
	(
	id asc
	) WITH (PAD_INDEX  = ON, 
			STATISTICS_NORECOMPUTE  = OFF, 
			--SORT_IN_TEMPDB = ON,   
			IGNORE_DUP_KEY = OFF, 
			--DROP_EXISTING = OFF, 
			--ONLINE = OFF,   
			ALLOW_ROW_LOCKS  = ON, 
			ALLOW_PAGE_LOCKS  = ON, 
			FILLFACTOR = 80)
) ON [PRIMARY]

ALTER TABLE [dbo].[MissingIndexes_history] ADD CONSTRAINT DFC_MI_Date DEFAULT GETDATE() FOR [recorded_date]

--drop table [dbo].[MissingIndexes_history]

-- Run through each db on the instance and record results to the temp table
-- yes, sp_MSforeachdb is both undocumented and unsupported, but for this it works just fine

exec master.sys.sp_MSforeachdb
'  use [?];
INSERT #MI
SELECT top 5
	db_name(mid.database_id) as [dbname],
	Object_name(mid.[object_id]),
	Cast(((migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans)))as INT) AS [improvement_measure],
	''CREATE INDEX [missing_index_'' + CONVERT (varchar, mig.index_group_handle) + ''_'' + CONVERT (varchar, mid.index_handle)
	+ ''_'' + LEFT (PARSENAME(mid.statement, 1), 32) + '']''
	+ '' ON '' + mid.statement
	+ '' ('' + ISNULL (mid.equality_columns,'''')
	+ CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN '','' ELSE '''' END
	+ ISNULL (mid.inequality_columns, '''')
	+ '')''
	+ ISNULL ('' INCLUDE ('' + mid.included_columns + '')'', '''') AS create_index_statement,
	migs.*, 
	mid.database_id
FROM sys.dm_db_missing_index_groups mig
	INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
	INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE 1=1
	--and migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 40000 --uncomment to filter by improvement measure
	--and migs.user_seeks > 250									-- change this for activity level of the index, leave commented out to get back everything
	and mid.database_id > 4										--Skip system databases
	and db_name(mid.database_id) = ''?''						--Get top 5 for only the current database
ORDER BY 
	migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) DESC
'

--([servername],
--	[dbname] ,
--	[object_id] ,
--	[improvement_measure] ,
--	[create_index_statement] ,
--	[group_handle] ,
--	[unique_compiles] ,
--	[user_seeks] ,
--	[user_scans],
--	[last_user_seek],
--	[last_user_scan],
--	[avg_total_user_cost] ,
--	[avg_user_impact] ,
--	[system_seeks] ,
--	[system_scans] ,
--	[last_system_seek] ,
--	[last_system_scan] ,
--	[avg_total_system_cost] ,
--	[avg_system_impact] ,
--	[database_id])


exec master.sys.sp_MSforeachdb
'  use [?];
INSERT into [DBAdmin].[dba].[MissingIndexes_history]
SELECT top 20
	@@servername,
	getdate(),
	db_name(mid.database_id) as [dbname],
	Object_name(mid.[object_id]),
	Cast(((migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans)))as INT) AS [improvement_measure],
	''CREATE INDEX [IDX_'' + CONVERT (varchar, mig.index_group_handle) + ''_'' + CONVERT (varchar, mid.index_handle) 
  + ''_'' + LEFT (PARSENAME(mid.statement, 1), 32) + '']''
  + '' ON '' + mid.statement 
  + '' ('' + ISNULL (mid.equality_columns,'''') 
    + CASE WHEN mid.equality_columns IS NOT NULL 
    AND mid.inequality_columns IS NOT NULL 
    THEN '','' ELSE '''' END 
    + ISNULL (mid.inequality_columns, '''')
  + '')'' 
  + ISNULL ('' INCLUDE ('' + mid.included_columns + '')'', '''') 
  + '' WITH (PAD_INDEX  = ON, STATISTICS_NORECOMPUTE  = OFF, SORT_IN_TEMPDB = OFF, 
IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, 
ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON, FILLFACTOR = 85
)''
AS create_index_statement,
	migs.*, 
	mid.database_id
FROM sys.dm_db_missing_index_groups mig
	INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
	INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE 1=1
	--and migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 40000 --uncomment to filter by improvement measure
	--and migs.user_seeks > 250									-- change this for activity level of the index, leave commented out to get back everything
	and mid.database_id > 4										--Skip system databases
	and db_name(mid.database_id) = ''?''						--Get top 5 for only the current database
ORDER BY 
	migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) DESC
'

select count(1) from [DBAdmin].[dba].[MissingIndexes_history]
select * from [DBAdmin].[dba].[MissingIndexes_history]

-- only keep a rolling 15 days worth of history for all missing indexes
declare @delete_period int
set @delete_period = 31

delete from [VANDBA].[dbo].[MissingIndexes_history] where recorded_date < getdate()- @delete_period

--now that the table is populated, show me the data!
--no data for a DB means no index recommendations.

Select
	[dbname] 
	,[object_id] 
	,[Improvement_Measure]
	,[create_index_statement]
	,[user_seeks]
	,[user_scans]
	,[last_user_seek]
	,[last_user_scan]
	,[avg_total_user_cost]
	,[avg_user_impact]
From #MI
Where 1=1
Order by [dbname],[improvement_measure] desc

--Clean up your mess, you weren't raised in a barn!
Drop Table #MI


