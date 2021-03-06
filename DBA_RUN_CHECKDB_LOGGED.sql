USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[DBA_RUN_CHECKDB_LOGGED]    Script Date: 07/09/2018 09:25:39 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dba].[DBA_RUN_CHECKDB_LOGGED]

--#############################################################################
--
-- Author	: Haden Kingsland
-- Date		: 15/10/2015
-- Version	: 01:00
--
-- Desc		: To run a DBCC CHECKDB across all online databases. This has been written as the original, below process
--			  had issues when running the sp_MSforeachdb procedure and was missing some databases!
--
--	EXEC sp_MSforeachdb N'IF DATABASEPROPERTYEX(''?'', ''Collation'') IS NOT NULL
--
--	BEGIN
--
--		DBCC CHECKDB (?) WITH ALL_ERRORMSGS, EXTENDED_LOGICAL_CHECKS, DATA_PURITY
--
--	END' ;
--
-- Usage:
--
-- exec [dbadmin].[dba].[DBA_RUN_CHECKDB_LOGGED] '' -- 'DBAdmin'
--
-- Modification History
-- ====================
--
-- 07/03/2016 -- Haden Kingsland	First cut of the procedure written to run DBCC CHECKDB and output results to the 
--									dbcc_history (or dbcc_history_2012) table in the DBAdmin database
--
-- 15/03/2016 -- Haden Kingsland    To overcome the below error seen when running DBCC CHECKDB against databases with a hyphon in the name
--									when using the exec @sql syntax!
--
--									Msg 102, Level 15, State 1, Line 1
--									Incorrect syntax near '-'.
--									Msg 319, Level 15, State 1, Line 1
--									Incorrect syntax near the keyword 'with'. If this statement is a common table expression, an xmlnamespaces clause 
--									or a change tracking context clause, the previous statement must be terminated with a semicolon.
--
--	07/04/2016 -- Haden Kingsland	Changed the reference to @@VERSION to make it more efficient in working out what version of SQL it is running under
--									after issues with the wildcard options.
--
-- References -- https://www.mssqltips.com/sqlservertip/2325/capture-and-store-sql-server-database-integrity-history-using-dbcc-checkdb/
--
--##########################################################################################################################
--
/********************************************************************************************************************/
-- Disclaimer...
--
-- This script is provided for open use by Haden Kingsland (theflyingDBA) and as such is provided as is, with
-- no warranties or guarantees.
-- The author takes no responsibility for the use of this script within environments that are outside of his direct
-- control and advises that the use of this script be fully tested and ratified within a non-production environment
-- prior to being pushed into production.
-- This script may be freely used and distributed in line with these terms and used for commercial purposes, but
-- not for financial gain by anyone other than the original author.
-- All intellectual property rights remain solely with the original author.
--
/********************************************************************************************************************/
--
-- This table MUST be created in your admin database BEFORE you can run this procedure!!!!
--
-- If the SQL version is 2008 or below, you need to create this version of the table...
--
--CREATE TABLE [dba].[dbcc_history](
--[Error] [int] NULL,
--[Level] [int] NULL,
--[State] [int] NULL,
--[MessageText] [varchar](7000) NULL,
--[RepairLevel] [int] NULL,
--[Status] [int] NULL,
--[DbId] [int] NULL,
--[Id] [int] NULL,
--[IndId] [int] NULL,
--[PartitionID] [int] NULL,
--[AllocUnitID] [int] NULL,
--[File] [int] NULL,
--[Page] [int] NULL,
--[Slot] [int] NULL,
--[RefFile] [int] NULL,
--[RefPage] [int] NULL,
--[RefSlot] [int] NULL,
--[Allocation] [int] NULL,
--[TimeStamp] [datetime] NULL CONSTRAINT [DF_dbcc_history_TimeStamp] DEFAULT (GETDATE()) -- defaults to current date/time of when written to.
--) ON [PRIMARY]
--GO

-- If the SQL version is 2012 and above, you need to create this version of the table...
--
--create table [dba].[dbcc_history_2012]
--(
--    [Error]        int            null,
--    [Level]        int            null,
--    [State]        int            null,
--    [MessageText]  varchar (7000) null,
--    [RepairLevel]  int            null,
--    [Status]       int            null,
--    [DbId]         int            null,
--    [DbFragId]     int            null,
--    [ObjectId]     int            null,
--    [IndexId]      int            null,
--    [PartitionId]  int            null,
--    [AllocUnitId]  int            null,
--    [RidDbId]      int            null,
--    [RidPruId]     int            null,
--    [File]         int            null,
--    [Page]         int            null,
--    [Slot]         int            null,
--    [RefDBId]      int            null,
--    [RefPruId]     int            null,
--    [RefFile]      int            null,
--    [RefPage]      int            null,
--    [RefSlot]      int            null,
--    [Allocation]   int            null,
--    [Timestamp]	   datetime       NULL CONSTRAINT [DF_dbcc_history_2012_TimeStamp] DEFAULT (GETDATE()) -- defaults to current date/time of when written to.
--) on [PRIMARY];
--
--	truncate table [dba].[dbcc_history]
--
--##########################################################################################################################
@database_name SYSNAME	=	''

AS 

BEGIN

DECLARE		
			--@database_name varchar(200),
			@database_id bigint,
			@MESSAGE_BODY nvarchar(250),
			@MESSAGE_BODY2 nvarchar(250),
			@MESSAGE_BODY3 nvarchar(250),
			@MESSAGE_BODY4 nvarchar(500),
			@MESSAGE_BODY5 nvarchar(500),
			@MESSAGE_SUBJECT varchar(200),
			@command nvarchar(500),
			@ERR_MESSAGE varchar(400),
			@ERR_NUM bigint,
			@XPCMDSH_ORIG_ON varchar(1),
			@MailProfileName VARCHAR(50),
			@SQL varchar(500),
			@ver varchar(15);

-------------
-- DEBUG...
-------------
--declare @database_name SYSNAME
--set @database_name = 'DBAdmin'

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'

---------------------
-- Initialize variables
---------------------

set @XPCMDSH_ORIG_ON = ''
set @SQL = ''
set @ver = ''

			SELECT @ver = CASE WHEN @@VERSION LIKE '%8.0%'	THEN 'SQL2000' 
						   WHEN @@VERSION LIKE '%9.0%'	THEN 'SQL2005'
						   WHEN @@VERSION LIKE '%10.0%' THEN 'SQL2008' 
						   WHEN @@VERSION LIKE '%10.5%' THEN 'SQL2008R2' 
						   WHEN @@VERSION LIKE '%11.0%' THEN 'SQL2012' 
						   WHEN @@VERSION LIKE '%12.0%' THEN 'SQL2014'
						   WHEN @@VERSION LIKE '%13.0%' THEN 'SQL2016'
						   WHEN @@VERSION LIKE '%14.0%' THEN 'SQL2017'
				END;

--select @@VERSION
--select @ver
--------------------------------------------------------------------------------------------------------------------
-- Check whether xp_cmdshell is turned off via Surface Area Configuration (2005) / Instance Facets (>2008)
-- This is best practice !!!!! If it is already turned on, LEAVE it on !!

-- turn on advanced options
	EXEC sp_configure 'show advanced options', 1 reconfigure 
	RECONFIGURE  

	CREATE TABLE #advance_opt (name VARCHAR(20),min int, max int, conf int, run int)
			INSERT #advance_opt
		EXEC sp_configure 'xp_cmdshell' -- this will show whether xp_cmdshell is turned on or not
				
	IF (select conf from #advance_opt) = 0 -- check if xp_cmdshell is turned on or off, if off, then turn it on
		BEGIN

			set @XPCMDSH_ORIG_ON = 'N' -- make a note that it is NOT supposed to be on all the time
			
			--turn on xp_cmdshell to allow operating system commands to be run
			EXEC sp_configure 'xp_cmdshell', 1 reconfigure
			RECONFIGURE
		END
	ELSE
		BEGIN
		 -- make a note that xp_cmdshell was already turned on, so not to turn it off later by mistake
			set @XPCMDSH_ORIG_ON = 'Y'
		END

-- drop the temporary table to tidy up after ourselves.

	IF EXISTS (
	select * from tempdb.sys.objects
	where name like '%advance_opt%'
	)
		BEGIN
			drop table #advance_opt
		END
		
--------------------------------------------------------------------------------------------------------------------

IF @database_name = '' -- Then run the procedure against all databases
	BEGIN

		DECLARE check_databases CURSOR FOR

		select 
		name, 
		database_id
		from sys.databases
		where database_id  NOT IN (3) -- ignore the model database
		and state in (0,4) -- online or suspect mode databases only
		and is_read_only = 0
		and source_database_id IS NULL -- only real database, so no database snapshots!
		order by name;


	-- Open the cursor.
		OPEN check_databases;

	-- Loop through the update_stats cursor.

		FETCH NEXT
		   FROM check_databases
		   INTO @database_name, @database_id;


			WHILE @@FETCH_STATUS <> -1 -- Stop when the FETCH statement failed or the row is beyond the result set
			BEGIN

					IF @@FETCH_STATUS = 0 -- to ignore -2 status "The row fetched is missing"
					BEGIN

						BEGIN TRY
							
							-- DEBUG
							--declare @sql varchar(500)
							--declare @database_name sysname
							--declare @ver varchar(15)
							--set @ver = 'SQL 2014'
							--set @database_name = 'DBAdmin'
							
							set @sql = 'DBCC CHECKDB ' + '(' + '[' + @database_name + ']' + ')' + ' WITH ALL_ERRORMSGS, DATA_PURITY, tableresults'
						
							--print @sql;
							--exec (@sql);
							
							
							IF LTRIM(RTRIM(@ver)) not in ('SQL2012','SQL2014','SQL2016','SQL2017') -- before version 2012 and 2014
								BEGIN
									INSERT INTO dbadmin.dba.dbcc_history ([Error], [Level], [State], MessageText, RepairLevel, [Status], 
									[DbId], Id, IndId, PartitionId, AllocUnitId, [File], Page, Slot, RefFile, RefPage, 
									RefSlot,Allocation) exec(@sql)
								END;
							ELSE
								BEGIN -- for versions 2012 and 2014 only
									INSERT INTO dbadmin.dba.dbcc_history_2012
									([Error],[Level],[State],[MessageText],[RepairLevel],[Status],[DbId],[DbFragId],[ObjectId],[IndexId],[PartitionId],
									[AllocUnitId],[RidDbId],[RidPruId],[File],[Page],[Slot],[RefDBId],[RefPruId],[RefFile],[RefPage],[RefSlot],
									[Allocation]) exec(@sql)
								END;
						
						END TRY
						
						BEGIN CATCH
						
							SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();

							SET @MESSAGE_BODY='Failure running the DBCC CHECKDB LOGGED job for ' + @database_name + ' Error Message = ' + @ERR_MESSAGE
							SET @MESSAGE_SUBJECT='Failure running the DBCC CHECKDB LOGGED job for ' + @database_name + '  on ' + @@SERVERNAME
									
							EXEC msdb.dbo.sp_notify_operator 
								@profile_name = @MailProfileName, 
								@name=N'DBA-Alerts',
								@subject = @MESSAGE_SUBJECT,
								@body= @MESSAGE_BODY;
							
							print @MESSAGE_BODY
							print @MESSAGE_SUBJECT

						END CATCH
						
						--FETCH NEXT FROM check_databases INTO @database_name, @database_id;

					END -- end of @@fetchstatus if
					
					FETCH NEXT FROM check_databases INTO @database_name, @database_id;
			END

	-- Close and deallocate the cursor.

		CLOSE check_databases;
		DEALLOCATE check_databases;
	END


ELSE -- run against a specified database (ie: exec [dba].[DBA_RUN_CHECKDB_LOGGED] 'DB Name Here'

	set @sql = 'DBCC CHECKDB ' + '(' + '[' + @database_name + ']' + ')' + ' WITH ALL_ERRORMSGS, DATA_PURITY, tableresults'
	select @ver
	BEGIN

		IF LTRIM(RTRIM(@ver)) not in ('SQL2012','SQL2014','SQL2016','SQL2017') -- before version 2012 and 2014
			BEGIN
				INSERT INTO dbadmin.dba.dbcc_history ([Error], [Level], [State], MessageText, RepairLevel, [Status], 
				[DbId], Id, IndId, PartitionId, AllocUnitId, [File], Page, Slot, RefFile, RefPage, 
				RefSlot,Allocation) exec(@sql)
			END
		ELSE
			BEGIN -- for versions 2012 and 2014 only
				INSERT INTO dbadmin.dba.dbcc_history_2012
				([Error],[Level],[State],[MessageText],[RepairLevel],[Status],[DbId],[DbFragId],[ObjectId],[IndexId],[PartitionId],
				[AllocUnitId],[RidDbId],[RidPruId],[File],[Page],[Slot],[RefDBId],[RefPruId],[RefFile],[RefPage],[RefSlot],
				[Allocation]) exec(@sql)
			END
	
		--INSERT INTO dbadmin.dba.dbcc_history ([Error], [Level], [State], MessageText, RepairLevel, [Status], 
		--[DbId], Id, IndId, PartitionId, AllocUnitId, [File], Page, Slot, RefFile, RefPage, RefSlot,Allocation)
		--EXEC ('DBCC CHECKDB ' + '(' + @database_name + ')' + ' WITH ALL_ERRORMSGS, DATA_PURITY, tableresults')
		
	END		
	
-----------------------------------------------------------------------------------------------------------------------		
-- turn off advanced options

	IF @XPCMDSH_ORIG_ON = 'N'  -- if xp_cmdshell was NOT originally turned on, then turn it off 
	BEGIN

		-- turn on advanced options again just to ensure we can turn off xp_cmdshell!
		EXEC sp_configure 'show advanced options', 1 reconfigure 
		RECONFIGURE  

		--  turn off xp_cmdshell to dis-allow operating system commands to be run
		EXEC sp_configure 'xp_cmdshell', 0  reconfigure
		RECONFIGURE

		EXEC sp_configure 'show advanced options', 0 reconfigure
		RECONFIGURE
		
	END
-----------------------------------------------------------------------------------------------------------------------
	
END


--exec [dba].[DBA_RUN_CHECKDB_LOGGED] 'DBAdmin'

