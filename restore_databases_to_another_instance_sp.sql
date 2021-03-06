USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[restore_databases_to_another_instance_sp]    Script Date: 07/09/2018 09:59:50 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dba].[restore_databases_to_another_instance_sp]

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 01/09/2010
-- Version	: 01:00
--
-- Desc		:	To restore databases to another instance from a given shared backup area
--					Both the destination file name (source location for the backup), and a string of 
--					databases to restore / look for to restore are passed in as paramaters ... examples follow ...
--				The procedure is hard coded to include the [LB-SQL-02] linked server which runs under the "sa"
--				account.
--
-- SET @DestinationFileName ='\\172.20.0.153\SQL_BACKUP$\MSSQLSERVER\Daily\SQL_Full\'
-- set @databases = 'Livebookings_One_Aggregator,lbconsole,LiveBookings_One_Profitable_Availability'
--
-- ############################
-- EXAMPLE SQL AGENT JOB CALL
-- ############################
--
--DECLARE @RC							int
--DECLARE @DestFileName			nvarchar(1000)
--DECLARE @databases				nvarchar(1000)
--DECLARE @job_name				VARCHAR(256)
--
--DECLARE @linked_server			varchar(20)
--
-- select @job_name = 'Restore databases to another instance'
-- select @databases =  'Livebookings_One_Aggregator,lbconsole,LiveBookings_One_Profitable_Availability'
-- select @DestFileName = '\\172.20.0.153\SQL_BACKUP$\MSSQLSERVER\Daily\SQL_Full\'
--
-- select @linked_server = 'lb-sql-02'
--
-- EXECUTE @RC = [master].[dba].[restore_databases_to_another_instance_sp] 
-- @DestFileName,
-- @databases,
-- @job_name
--
-- @linked_server	
--
-- ###########################################################
-- the below linked server MUST exist at the source instance
-- ###########################################################
--
--EXEC master.dbo.sp_addlinkedserver @server = N'LB-SQL-02', @srvproduct=N'SQL Server'
-- /* For security reasons the linked server remote logins password is changed with ######## */
--EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'LB-SQL-02',@useself=N'False',@locallogin=NULL,@rmtuser=N'sa',@rmtpassword='########'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'collation compatible', @optvalue=N'false'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'data access', @optvalue=N'true'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'dist', @optvalue=N'false'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'pub', @optvalue=N'false'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'rpc', @optvalue=N'true'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'rpc out', @optvalue=N'true'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'sub', @optvalue=N'false'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'connect timeout', @optvalue=N'0'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'collation name', @optvalue=null
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'lazy schema validation', @optvalue=N'false'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'query timeout', @optvalue=N'7200'
--GO
--EXEC master.dbo.sp_serveroption @server=N'LB-SQL-02', @optname=N'use remote collation', @optvalue=N'true'
--GO
--
----#############################################################
--
-----------------------
-- Modification History
-----------------------
-- 08/09/2010 -- Haden Kingsland -- Added a call to ...
--									exec [LB-SQL-02].[master].[dba].[kill_users_other_than_system_sp] @dbname, @p_error_description output
--									This sp MUST exist in the receiving instance in the MASTER DB as a remote call is made to it.
--
--#################################################################
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
 (
     @DestFileName			nvarchar(1000),
     @databases				nvarchar(1000),
     @job_name				VARCHAR(256)
     --@linked_server			varchar(20)
   -- @p_error_description				varchar(300) OUTPUT -- if a called procedure
  )


as

BEGIN

DECLARE			@SQL VARCHAR(7000),
				@SQL2 VARCHAR(7000),
				@SQL3 VARCHAR(7000),
				@SQL4 VARCHAR(7000),
				@use varchar(50),
				@DestinationFileName nvarchar(1000),
				@DBName SYSNAME,
				@BkpFileName NVARCHAR(260),
				@RowCnt INT,
				@MailProfileName VARCHAR(50),		
				@COMMAND varchar(800),
				@ERR_MESSAGE varchar(200),
				@ERR_NUM int,
				@MESSAGE_BODY varchar(2000),
				@MESSAGE_BODY_OPS varchar(1000),
				@MESSAGE_BODY2 varchar(1000),
				@MESSAGE_BODY3 varchar(1000),
				@ErrorSeverity int,
				@ErrorState int,
				@p_error_description varchar(300),
				@DELAYLENGTH			char(9)

if @databases <> ''
Begin
	SET @databases = ',' + @databases + ','
end

--SET @linked_server= '[' + @linked_server + ']'

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'

--#####################################################################################
-- removed as does not return UNC named backups even if they are the lastest ones!
--#####################################################################################
--SELECT bs.database_name AS DatabaseName, MAX(bms.physical_device_name) AS FullBackupName
--INTO #Backups
--FROM msdb.dbo.backupset bs
--INNER JOIN msdb.dbo.backupmediafamily bms 
--ON bs.media_set_id = bms.media_set_id
--INNER JOIN master.dbo.sysdatabases s 
--ON bs.database_name = s.name
--WHERE CONVERT(VARCHAR(20), bs.backup_finish_date, 101) = CONVERT(VARCHAR(20), GETDATE(), 101) AND
--	bs.type = 'D' and 
--	(CHARINDEX(',' + bs.database_name + ',' , @databases) > 0) -- check whether databases are in the list of those passed in
--	--(
--	--	bs.database_name LIKE 'Livebookings_One_Aggregator' or 
--	--	bs.database_name LIKE 'lbconsole' or
--	--	bs.database_name LIKE 'LiveBookings_One_Profitable_Availability'
--	--)
--GROUP BY bs.database_name
--#####################################################################################

SELECT bs.database_name AS DatabaseName, 
bms.physical_device_name AS FullBackupName
INTO #Backups
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bms 
ON bs.media_set_id = bms.media_set_id
INNER JOIN master.dbo.sysdatabases s 
ON bs.database_name = s.name
where bs.backup_finish_date = 
	(select MAX(bs1.backup_finish_date)
	FROM msdb.dbo.backupset bs1
	INNER JOIN master.dbo.sysdatabases s1
	ON bs1.database_name = s1.name
	where s.name = s1.name
	and  bs1.type = 'D')
AND bs.type = 'D' and 
(CHARINDEX(',' + bs.database_name + ',' , @databases) > 0) -- check whether databases are in the list of those passed in
GROUP BY bs.database_name, bms.physical_device_name

SET @RowCnt = @@ROWCOUNT 
set @DELAYLENGTH = '000:00:05' -- wait for 5 seconds

WHILE @RowCnt > 0
BEGIN

	SELECT  TOP 1 @DBName = DatabaseName, @BkpFileName = FullBackupName
	FROM #Backups
	ORDER BY DatabaseName

	SET @RowCnt = @@ROWCOUNT

--	SET @use = 'USE [' + @dbname + ']'
--	SET @SQL4 =
--	'
--DECLARE @orphened_users	TABLE
--							(
--								row_id	 INT IDENTITY(1,1),
--								UserName VARCHAR(50),
--								UserSID  VARCHAR(100)
--							)

--DECLARE
--	@min INT,
--	@max INT,
--	@user_id VARCHAR(50)

--set @min = 1

---- List of orphened users
--INSERT INTO @orphened_users (UserName,UserSID)
--	SELECT name,
--		   [sid]
--	  FROM sysusers
--	 WHERE issqluser = 1 
--	   AND ([sid] IS NOT NULL
--			AND [sid] <> 0x0)
--	   AND (LEN([sid]) <= 16)
--	   AND SUSER_SNAME([sid]) is null
--	 ORDER BY name

--SELECT @max = COUNT(*)
--  FROM @orphened_users

--WHILE(@min <= @max)
--	BEGIN
--		SELECT @user_id = UserName
--		  FROM @orphened_users
--		 WHERE row_id = @min
		
--		EXEC sp_change_users_login
--			@Action				= ''update_one'',
--			@UserNamePattern	= @user_id, 
--			@LoginName			= @user_id;
		
--		SELECT @min = @min+1
--	END
--	'


	IF @RowCnt > 0
	BEGIN
		DELETE FROM #Backups
		WHERE DatabaseName = @DBName

-- ################################################################################
-- Removed as the backup location and restore locations are now on the same share.
-- ################################################################################
		--SET @DestinationFileName = @DestFileName + 
		--	SUBSTRING(@BkpFileName, LEN(@BkpFileName) - CHARINDEX('\', REVERSE(@BkpFileName)) + 2, 1000)

-- so you can just set the destinationfilename variable as per the bkpfilename

		set @DestinationFileName = @BkpFileName

	--select @destinationfilename

		--SET @SQL = 'copy ' + @BkpFileName + ' "' + @DestinationFileName + '"'

		--EXECUTE AS login = 'backupmover'
		--EXEC master.dbo.xp_cmdshell @SQL
		--REVERT

		-- Restore the database on lb-sql-02
		IF @DBName = 'LiveBookings_One_Aggregator' 
			BEGIN
			SET @SQL =
'
--Make Database to single user Mode
--ALTER DATABASE LiveBookings_One_Aggregator
--SET SINGLE_USER WITH ROLLBACK IMMEDIATE

--Restore Database
RESTORE DATABASE LiveBookings_One_Aggregator
FROM DISK = ''' + @DestinationFileName + '''
WITH 
	MOVE ''LiveBookings_One_Aggregator_Data'' TO ''E:\SQL_DATA\LiveBookings_One_Aggregator_Data.mdf'',
	MOVE ''LiveBookings_One_Aggregator_Metric'' TO ''E:\SQL_DATA\LiveBookings_One_Aggregator_Metric.mdf'',
	MOVE ''LiveBookings_One_Aggregator_Index'' TO ''E:\SQL_DATA\LiveBookings_One_Aggregator_Index.mdf'',
	MOVE ''LiveBookings_One_Aggregator_Log'' TO ''E:\SQL_LOG\LiveBookings_One_Aggregator_Log.ldf'',
	MOVE ''LiveBookings_One_Aggregator_LogOld'' TO ''E:\SQL_LOG\LiveBookings_One_Aggregator_LogOld.ldf'',
	REPLACE

--If there is no error in statement before database will be in multiuser mode.
--If error occurs please execute following command it will convert database in multi user.
--ALTER DATABASE LiveBookings_One_Aggregator SET MULTI_USER
'
			END
				ELSE IF @DBName = 'LiveBookings_One_Profitable_Availability' 
			BEGIN
				SET @SQL =
'
--Make Database to single user Mode
--ALTER DATABASE LiveBookings_One_Profitable_Availability
--SET SINGLE_USER WITH ROLLBACK IMMEDIATE
Set AUTO_UPDATE_STATISTICS_ASYNC to OFF
--Restore Database
RESTORE DATABASE LiveBookings_One_Profitable_Availability
FROM DISK = ''' + @DestinationFileName + '''
WITH 
	MOVE ''LiveBookings_One_Profitable_Availability_Data'' TO ''D:\MSSQL2005\MSSQL.1\MSSQL\Data\LiveBookings_One_Profitable_Availability_Data_prod.mdf'',
	MOVE ''LiveBookings_One_Profitable_Availability_Log'' TO ''D:\MSSQL2005\MSSQL.1\MSSQL\Data\LiveBookings_One_Profitable_Availability_Log_prod.ldf'',
	MOVE ''LiveBookings_One_Profitable_Availability_Index'' TO ''D:\MSSQL2005\MSSQL.1\MSSQL\Data\LiveBookings_One_Profitable_Availability_Index_prod.ndf'',
	REPLACE

--If there is no error in statement before database will be in multiuser mode.
--If error occurs please execute following command it will convert database in multi user.
--ALTER DATABASE LiveBookings_One_Profitable_Availability SET MULTI_USER
'
		END
			ELSE IF @DBName = 'lbconsole' 
			BEGIN
				SET @SQL =
'
--Make Database to single user Mode
--ALTER DATABASE lbconsole
--SET SINGLE_USER WITH ROLLBACK IMMEDIATE

--Restore Database
RESTORE DATABASE lbconsole
FROM DISK = ''' + @DestinationFileName + '''
WITH 
	MOVE ''lbconsole_Data'' TO ''D:\MSSQL2005\MSSQL.1\MSSQL\Data\lbconsole_data_prod.mdf'',
	MOVE ''lbconsole_Log'' TO ''D:\MSSQL2005\MSSQL.1\MSSQL\Data\lbconsole_log_prod.ldf'',
	MOVE ''lbconsole_Log2'' TO ''D:\MSSQL2005\MSSQL.1\MSSQL\Data\lbconsole_log2_prod.ldf'',
	REPLACE

--If there is no error in statement before database will be in multiuser mode.
--If error occurs please execute following command it will convert database in multi user.
--ALTER DATABASE lbconsole SET MULTI_USER
'
			END
		
		BEGIN TRY

--EXEC master.dbo.xp_cmdshell 'dir \\172.20.0.153\SQL_BACKUP$\MSSQLSERVER\Weekly\SQL_FULL\'
--EXEC master.dbo.xp_cmdshell 'dir \\lb-sql-02\Backups from production\'

-- ######################################################################
-- LINKED SERVER [LB-SQL-02] MUST EXIST WITHIN THE SOURCE INSTANCE
-- ######################################################################

		--set @SQL2 = 'exec master.dba.kill_users_other_than_system_sp ' + @DBName + ',' + @p_error_description + ' output'
		--set @SQL = 'exec [master].[dba].[kill_users_other_than_system_sp]' + ' ' + @dbname + ',' + ' ' + ISNULL(@p_error_description,'@p_error_description') + ' output'
		
		--print @SQL2
		----SET @sql2 = @sql2 + @DBname  + ', ' + @p_error_description + ' output'
		
		--exec (@SQL2) AT [lb-sql-02]
		
		-- ######################################################################
		-- Kill all users on receiving side of the restore
		-- ######################################################################
		
		exec [LB-SQL-02].[master].[dba].[kill_users_other_than_system_sp] @dbname, @p_error_description output
		
		WAITFOR DELAY @DELAYLENGTH
		
		IF (@p_error_description <> '' or @p_error_description IS NOT NULL)
			BEGIN
				set @ERR_MESSAGE = @p_error_description
				-- using RAISERROR forces the execution to the CATCH block for this iteration of the loop
				RAISERROR (
					'The remote call to master.dba.kill_users_other_than_system_sp failed ', -- Message text.
					16, -- Severity.
					1 -- State.
               );
               
			END
		ELSE
			BEGIN

				-- put databases in single user mode prior to the restore
				set @SQL2 = 'alter database ' + @dbname + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'
				exec (@SQL2) AT [lb-sql-02]
				
				WAITFOR DELAY @DELAYLENGTH -- then wait for 2 seconds in case of any outstanding locks form previous command
				
				-- then restore the databases at the linked server site
				EXEC (@SQL) AT [lb-sql-02]-- linked server on both LB-SQL-01 & LB-SQL-03.
				
				-- put databases back in multi user mode once restore in complete
				set @SQL3 = 'ALTER DATABASE ' + @dbname + ' SET MULTI_USER'
				exec (@SQL3) AT [lb-sql-02] 
				
				set @SQL4 = 'alter database ' + @dbname + ' set recovery SIMPLE with no_wait'
				exec (@SQL4) AT [lb-sql-02]
				
				--exec (@USE) AT [LB-SQL-02] -- change database context
				--exec (@SQL4) AT [LB-SQL-02] -- run repair orphaned users code

			END
			
		-- EXEC (@SQL) AT [lb-sql-02] -- linked server on both LB-SQL-01 & LB-SQL-03.

		END TRY
		
		BEGIN CATCH
			
			-- check whether the @ERR_MESSAGE parameter already has a value from an earlier error
			If @ERR_MESSAGE <> ''
			BEGIN
				select @ERR_NUM = ERROR_NUMBER();
			END
			ELSE
				BEGIN
					SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();
				END
				
			IF @ERR_NUM in (5061,3101)	-- Error Message ALTER DATABASE failed because a lock could not be placed on database
										-- Error Message Exclusive access could not be obtained because the database is in use.
				BEGIN
					set @SQL3 = 'ALTER DATABASE ' + @dbname + ' SET MULTI_USER'
					exec (@SQL3) AT [lb-sql-02] 
				
					set @SQL2 = 'alter database ' + @dbname + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'
					exec (@SQL2) AT [lb-sql-02]
				
					WAITFOR DELAY @DELAYLENGTH -- then wait for 2 seconds in case of any outstanding locks form previous command
				
				-- then restore the databases at the linked server site
				EXEC (@SQL) AT [lb-sql-02]-- linked server on both LB-SQL-01 & LB-SQL-03.
				
				-- put databases back in multi user mode once restore in complete
				set @SQL3 = 'ALTER DATABASE ' + @dbname + ' SET MULTI_USER'
				exec (@SQL3) AT [lb-sql-02] 
				
				set @SQL4 = 'alter database ' + @dbname + ' set recovery SIMPLE with no_wait'
				exec (@SQL4) AT [lb-sql-02]
				
				--exec (@USE) AT [LB-SQL-02]
				--exec (@SQL4) AT [LB-SQL-02]
				
				END
			ELSE 
				IF @ERR_NUM NOT IN (5061,3101) 
					BEGIN
			--SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();
			
-- Use RAISERROR inside the CATCH block to return error
-- information about the original error that caused
-- execution to jump to the CATCH block.
			--RAISERROR (@ERR_MESSAGE, -- Message text.
			--		   @ErrorSeverity, -- Severity.
			--		   @ErrorState -- State.
			--		   );
					
						SET @MESSAGE_BODY='Error restoring' + @DestinationFileName + ' to [LB-SQL-02] ' + '. Error Code ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message ' + @ERR_MESSAGE
						SET @MESSAGE_BODY2='Failure of ' + @job_name + ' within ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(30)))) 

						EXEC msdb.dbo.sp_notify_operator 
							@profile_name = @MailProfileName, 
							@name=N'DBA-Alerts',
							@subject = @MESSAGE_BODY2, 
							@body= @MESSAGE_BODY
					END
		
		END CATCH

		-- Delete the backup file on sql-02
		--SET @SQL = 'del "' + @DestinationFileName + '"'

		--EXECUTE AS login = 'backupmover'
		--EXEC master.dbo.xp_cmdshell @SQL
		--REVERT
	END
END

DROP TABLE #Backups

-- Cleanup
--EXEC sp_xp_cmdshell_proxy_account null

END

