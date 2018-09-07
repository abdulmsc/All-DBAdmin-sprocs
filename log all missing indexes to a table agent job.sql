USE [msdb]
GO

/****** Object:  Job [Log Missing Indexes Daily (all databases)]    Script Date: 08/30/2018 12:36:04 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 08/30/2018 12:36:04 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Log Missing Indexes Daily (all databases)', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Admin job to log all missing indexes in all databases daily and maintain a history of such, with creation statements, for the DBA team to apply if required.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', 
		@notify_email_operator_name=N'CII_SQL_Admin_Alerts', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Maintain rolling window of missing indexes]    Script Date: 08/30/2018 12:36:04 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Maintain rolling window of missing indexes', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=4, 
		@on_success_step_id=2, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'-- only keep a rolling 15 days worth of history for all missing indexes
declare @delete_period int
set @delete_period = 15

delete from [DBAdmin].[dba].[MissingIndexes_history] where recorded_date < getdate()- @delete_period', 
		@database_name=N'master', 
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Check all database for missing indexes]    Script Date: 08/30/2018 12:36:04 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Check all database for missing indexes', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec master.sys.sp_MSforeachdb
''  use [?];
INSERT into [DBAdmin].[dba].[MissingIndexes_history]
SELECT top 5
	@@servername,
	getdate(),
	db_name(mid.database_id) as [dbname],
	Object_name(mid.[object_id]),
	Cast(((migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans)))as INT) AS [improvement_measure],
	''''CREATE INDEX [IDX_'''' + CONVERT (varchar, mig.index_group_handle) + ''''_'''' + CONVERT (varchar, mid.index_handle) 
  + ''''_'''' + LEFT (PARSENAME(mid.statement, 1), 32) + '''']''''
  + '''' ON '''' + mid.statement 
  + '''' ('''' + ISNULL (mid.equality_columns,'''''''') 
    + CASE WHEN mid.equality_columns IS NOT NULL 
    AND mid.inequality_columns IS NOT NULL 
    THEN '''','''' ELSE '''''''' END 
    + ISNULL (mid.inequality_columns, '''''''')
  + '''')'''' 
  + ISNULL ('''' INCLUDE ('''' + mid.included_columns + '''')'''', '''''''') 
  + '''' WITH (PAD_INDEX  = ON, STATISTICS_NORECOMPUTE  = OFF, SORT_IN_TEMPDB = OFF, 
IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, 
ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON, FILLFACTOR = 85
)''''
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
	and db_name(mid.database_id) = ''''?''''						--Get top 5 for only the current database
ORDER BY 
	migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) DESC
''', 
		@database_name=N'master', 
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 2
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


