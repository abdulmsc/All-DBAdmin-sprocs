USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[restore_databases_to_another_instance_sp_generic]    Script Date: 07/09/2018 09:59:56 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dba].[restore_databases_to_another_instance_sp_generic]

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 01/09/2010
-- Version	: 01:00
--
-- Desc		:	To restore databases to another instance from a given shared backup area
--				Both the destination file name (source location for the backup), and a string of 
--				databases to restore / look for to restore are passed in as paramaters.
--				You must hard code the linked server into this procedure and change this before use to suit your needs
--
-- ############################
-- EXAMPLE SQL AGENT JOB CALL
-- ############################
--
--DECLARE @RC					int
--DECLARE @DestFileName			nvarchar(1000)
--DECLARE @databases			nvarchar(1000)
--DECLARE @job_name				VARCHAR(256)restore
--DECLARE @destDataDir			VARCHAR(512)
--DECLARE @destLogDir			VARCHAR(512)

-- select @destDataDir = 'F:\SQLDATA\PPManager'
-- select @destLogDir  = 'E:\SQLLOGS\PPManager'
-- select @job_name = 'Restore PPmanager databases to another instance'
-- select @databases =  'PPmanager'
-- select @DestFileName = '\\UNC\share\'

-- EXECUTE @RC = [dbadmin].[dba].[restore_databases_to_another_instance_sp] 
-- @DestFileName,
-- @databases,
-- @job_name,
-- @destDataDir,
-- @destLogDir
--	
-- ###########################################################
-- the below linked server MUST exist at the source instance
-- ###########################################################
--
----  Linked server : your instance\instance
--sp_addlinkedserver 'your instance\instance','SQL Server'
--go
--sp_addlinkedsrvlogin 'your instance\instance','false',null,'ernie','<password here>'
--go
--sp_serveroption 'your instance\instance','collation compatible','off'
--go
--sp_serveroption 'your instance\instance','data access','on'
--go
--sp_serveroption 'your instance\instance','rpc','on'
--go
--sp_serveroption 'your instance\instance','rpc out','on'
--go
--sp_serveroption 'your instance\instance','use remote collation','on'
--go
--sp_serveroption 'your instance\instance','collation name',null
--go
--sp_serveroption 'your instance\instance','connect timeout',0
--go
--sp_serveroption 'your instance\instance','query timeout','7200'
--go
--
----#############################################################
--
-----------------------
-- Modification History
-----------------------
-- 08/09/2010 -- Haden Kingsland -- Added a call to ...
--									exec [<linked server>].[dbadmin].[dba].[kill_users_other_than_system_sp] @dbname, @p_error_description output
--									This sp MUST exist in the receiving instance in the MASTER DB as a remote call is made to it.
--
-- 14/09/2010 -- Haden Kingsland -- Added generic restore functionality, to enable any database passed in the @databases parameter to be 
--									restored to the default data and log paths of the receiving instance, thus removing any hard coding.
--
-- 17/11/2011 -- Haden Kingsland -- Enhanced for Laing O'Rourke, as backups do not go to a central share, and reside on a local path on the
--									source server instead. To overcome this we need to strip out the backup file name, and concatenate it
--									with the passed in UNC path given to the backup share so all servers in the loop can see it. 
--									Also added command to make restored database read only, as it should not be updated.
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

 (
     @DestFileName			nvarchar(1000),
     @databases				nvarchar(1000),
     @job_name				VARCHAR(256),
     @destDataDir			VARCHAR(512),
	 @destLogDir			VARCHAR(512)
     --@linked_server			varchar(20)
   -- @p_error_description				varchar(300) OUTPUT -- if a called procedure
  )

as

BEGIN

DECLARE			@SQL VARCHAR(7000),
				@SQL2 VARCHAR(7000),
				@SQL3 VARCHAR(7000),
				@SQL4 VARCHAR(7000),
				@SQL5 VARCHAR(7000),
				@SQL6 VARCHAR(7000),
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
				@DELAYLENGTH			char(9),
				@DefaultFile nvarchar(512),
				@DefaultLog nvarchar(512),
				@name varchar(80),
				@file_id int,
				@extension varchar(8)
				--,@databases	nvarchar(1000);

if @databases <> ''
Begin
	SET @databases = ',' + @databases + ','
end

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'

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

--select * from  #Backups

SET @RowCnt = @@ROWCOUNT 
set @DELAYLENGTH = '000:00:05' -- wait for 5 seconds

-- get default directories for instance of SQL Server for install areas if no restore directories are passed into the procedure.
-- Directories must be passed in without the trailing "\" as this is added later in the procedure!

IF (@destDataDir <> ''
and @destLogDir <> '')
	BEGIN
		set @DefaultFile = @destDataDir
		set @DefaultLog  = @destLogDir
	END
ELSE
	BEGIN
		exec [stlsql03\ppmanager].master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultData', @DefaultFile OUTPUT
		exec [stlsql03\ppmanager].master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultLog', @DefaultLog OUTPUT
		SELECT ISNULL(@DefaultFile,N'') AS [DefaultFile], ISNULL(@DefaultLog,N'') AS [DefaultLog]
	END

-- start the outer loop

WHILE @RowCnt > 0
BEGIN

	SELECT  TOP 1 @DBName = DatabaseName, @BkpFileName = FullBackupName
	FROM #Backups
	ORDER BY DatabaseName

	SET @RowCnt = @@ROWCOUNT

	IF @RowCnt > 0
	BEGIN
	
		-- do this to remove each row as read from the temporary table, so always get next row from the previous top clause
	
		DELETE FROM #Backups
		WHERE DatabaseName = @DBName

-- ##########################################################################################
-- Remove only if the backup location and restore locations are now on the same share.
-- Use this command if the backup location retrived from the earlier query is NOT a UNC path
-- and is on a local drive. This command will append the backup file name only, to the 
-- passed in @DestinationFileName location, which will be a UNC path to a share that 
-- all servers in this process can see.
-- ##########################################################################################
		SET @DestinationFileName = @DestFileName + 
			SUBSTRING(@BkpFileName, LEN(@BkpFileName) - CHARINDEX('\', REVERSE(@BkpFileName)) + 2, 1000)

-- ##########################################################################################
-- Removed as the backup location and restore locations are now NOT on the same share.
-- only use this command IF the backups are on a UNC share, and this UNC path is returned
-- in the initial check for backups at the start of this procedure.
-- ##########################################################################################

		--set @DestinationFileName = @BkpFileName

-- ##########################################################################################

-- build up restore command string using the default instance file locations

		SET @Sql = 
		'RESTORE DATABASE [' + @DBName + '] ' + 
		'FROM DISK = ''' + @DestinationFileName + ''' ' +
		'WITH REPLACE, '
		
-- loop through the sys.master_files view to get all original file names for the database being restore to 
-- help build up the restore string
		
		select name, file_id
		into #dbfiles
		from sys.master_files
		where DB_NAME(database_id) = @DBName
		order by file_id

		--select * from #dbfiles

		DECLARE restore_db CURSOR 
		FOR 
		SELECT * FROM #dbfiles

		-- Open the cursor.
		OPEN restore_db;

		-- Loop through the partitions.
		FETCH NEXT
		  FROM restore_db
		  INTO @name, @file_id;

		WHILE @@FETCH_STATUS <> -1 -- Stop when the FETCH statement failed or the row is beyond the result set
		BEGIN

			IF @@FETCH_STATUS = 0 -- to ignore -2 status "The row fetched is missing"
			BEGIN

				IF @name not like '%Log%'
				BEGIN
					if @file_id > 1
					BEGIN
						SET @extension = '.ndf'', '
					END
					ELSE
						IF @file_id = 1
						BEGIN
							SET @extension = '.mdf'', '
						END

				SET @Sql = @sql + ' MOVE ''' + @name + ''' TO ''' + @DefaultFile + '\' + @name + @extension

				END
				ELSE
					BEGIN
						SET @Sql = @sql +
						'MOVE ''' + @name + ''' TO ''' + @DefaultLog + '\' + @name + '.ldf'', '
					END	

				FETCH NEXT
				  FROM restore_db
				  INTO @name, @file_id;
			END
		END
		
		CLOSE restore_db;
		DEALLOCATE restore_db;

		DROP TABLE #dbfiles;
	
		-- remove the last comma once you have finished building the restore string
	
		set @Sql = Left(@Sql,Len(@Sql)-1)
		
		BEGIN TRY

--EXEC master.dbo.xp_cmdshell 'dir \\172.20.0.153\SQL_BACKUP$\MSSQLSERVER\Weekly\SQL_FULL\'
--EXEC master.dbo.xp_cmdshell 'dir \\lb-sql-02\Backups from production\'

-- ######################################################################
-- Kill all users on receiving side of the restore
-- ######################################################################
-- ######################################################################
-- LINKED SERVER [stlsql03\ppmanager] MUST EXIST WITHIN THE SOURCE INSTANCE
-- ######################################################################

		exec [stlsql03\ppmanager].[dbadmin].[dba].[kill_users_other_than_system_sp] @dbname, @p_error_description output
		
		WAITFOR DELAY @DELAYLENGTH
		
		IF (@p_error_description <> '' or @p_error_description IS NOT NULL)
			BEGIN
				set @ERR_MESSAGE = @p_error_description
				-- using RAISERROR forces the execution to the CATCH block for this iteration of the loop
				RAISERROR (
					'The remote call to dbadmin.dba.kill_users_other_than_system_sp failed ', -- Message text.
					16, -- Severity.
					1 -- State.
               );
               
			END
		ELSE
			BEGIN

				-- put databases in single user mode prior to the restore
				set @SQL2 = 'alter database ' + @dbname + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'
				exec (@SQL2) AT [stlsql03\ppmanager]
				
				WAITFOR DELAY @DELAYLENGTH -- then wait for 2 seconds in case of any outstanding locks form previous command
				
				-- then restore the databases at the linked server site
				EXEC (@SQL) AT [stlsql03\ppmanager]-- linked server to stlsql03\ppmanager.
				
				-- put databases back in multi user mode once restore in complete
				set @SQL3 = 'ALTER DATABASE ' + @dbname + ' SET MULTI_USER'
				exec (@SQL3) AT [stlsql03\ppmanager] 
				
				set @SQL4 = 'alter database ' + @dbname + ' set recovery SIMPLE with no_wait'
				exec (@SQL4) AT [stlsql03\ppmanager]
				
				-- ############################
				-- DEBUG
				-- ############################
				--DECLARE	@SQL6 VARCHAR(7000)
				--declare @DBName SYSNAME
				--set @DBName = 'PPManager'

				-- change the database owner to be "sa" before putting it into read only mode
				set @SQL6 = 'exec [' + @DBName + '].dbo.sp_changedbowner @loginame = N''sa'', @map = false'
				-- print @sql6
				exec (@SQL6) AT [stlsql03\ppmanager]

				-- as this database is to be used for DR purposes, it should be put in read only mode once restored
				set @SQL5 = 'alter database ' + @DBName + ' set read_only with no_wait'
				exec (@SQL5) AT [stlsql03\ppmanager]

			END

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
					exec (@SQL3) AT [stlsql03\ppmanager] 
				
					set @SQL2 = 'alter database ' + @dbname + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'
					exec (@SQL2) AT [stlsql03\ppmanager]
				
					WAITFOR DELAY @DELAYLENGTH -- then wait for 2 seconds in case of any outstanding locks form previous command
				
				-- then restore the databases at the linked server site
				EXEC (@SQL) AT [stlsql03\ppmanager]-- linked server to stlsql03\ppmanager.
				
				-- put databases back in multi user mode once restore in complete
				set @SQL3 = 'ALTER DATABASE ' + @dbname + ' SET MULTI_USER'
				exec (@SQL3) AT [stlsql03\ppmanager] 
				
				set @SQL4 = 'alter database ' + @dbname + ' set recovery SIMPLE with no_wait'
				exec (@SQL4) AT [stlsql03\ppmanager]
				
				-- change the database owner to be "sa" before putting it into read only mode
				set @SQL6 = 'exec [' + @DBName + '].dbo.sp_changedbowner @loginame = N''sa'', @map = false'
				exec (@SQL6) AT [stlsql03\ppmanager]
				
				-- as this database is to be used for DR purposes, it should be put in read only mode once restored
				set @SQL5 = 'alter database ' + @DBName + ' set read_only with no_wait'
				exec (@SQL5) AT [stlsql03\ppmanager]
				

				
				--ALTER DATABASE [PPmanager] SET  READ_ONLY WITH NO_WAIT
				
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
					
						IF @ERR_NUM = (3201) -- Description from sys.sysmessages is ... Cannot open backup device '%ls'. Operating system error %ls.
						BEGIN
							set @SQL3 = 'ALTER DATABASE ' + @dbname + ' SET MULTI_USER'
							exec (@SQL3) AT [stlsql03\ppmanager] 
							
							set @SQL4 = 'alter database ' + @dbname + ' set recovery SIMPLE with no_wait'
							exec (@SQL4) AT [stlsql03\ppmanager]
							
							-- change the database owner to be "sa" before putting it into read only mode
							set @SQL6 = 'exec [' + @DBName + '].dbo.sp_changedbowner @loginame = N''sa'', @map = false'
							exec (@SQL6) AT [stlsql03\ppmanager]
				
							-- as this database is to be used for DR purposes, it should be put in read only mode once restored
							set @SQL5 = 'alter database ' + @DBName + ' set read_only with no_wait'
							exec (@SQL5) AT [stlsql03\ppmanager]
								
						END
					
						SET @MESSAGE_BODY='Error restoring' + @DestinationFileName + ' to [stlsql03\ppmanager] ' + '. Error Code ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message ' + @ERR_MESSAGE
						SET @MESSAGE_BODY2='Failure of ' + @job_name + ' within ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(30)))) 

						EXEC msdb.dbo.sp_notify_operator 
							@profile_name = @MailProfileName, 
							@name=N'DBA-Alerts',
							@subject = @MESSAGE_BODY2, 
							@body= @MESSAGE_BODY
					END
		END CATCH

	END
END

DROP TABLE #Backups

END

