USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[generic_backup_all_databases_cloud]    Script Date: 07/09/2018 09:34:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dba].[generic_backup_all_databases_cloud]
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

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 18/08/2006
-- Version	: 01:00
--
-- Desc		: To backup all databases given certain parameters
--
--#############################################################################
-- YOU MUST BE A SYSADMIN IN ORDER TO SWITCH ON XP_CMDSHELL, SO YOU MUST ENSURE THAT THE 
-- AGENT JOB FOR ALL BACKUPS RUNS UNDER THE CONTEXT OF A SYSADMIN USER!
--#############################################################################
--
-- You will need to create a credential for your Azure account in order to perform
-- backups to this location. This must relate to the Blob storage location in azure...
--
-- http://msdn.microsoft.com/en-GB/library/jj919148(v=sql.110).aspx#Support
-- http://azure.microsoft.com/en-us/documentation/articles/storage-manage-storage-account/
-- http://msdn.microsoft.com/en-us/library/jj919149.aspx

-- GRANT alter any credential to "OROURKE\hkadmin"

--IF NOT EXISTS
--(SELECT * FROM sys.credentials 
--WHERE credential_identity = 'dartfordsqlbak')
--CREATE CREDENTIAL mycredential WITH IDENTITY = 'dartfordsqlbak'
--,SECRET = 'rk4UHBoi7nncVYumKHCQ8M5VXY9Jny1bEqs72rssWP65sG25LP2nqcHIjPfGRfNeBRo3X9FfDiG60Vh4lyzXQw==' ;

------------------------------------------------------------
-- EXAMPLE CALL TO SP VIA a SQL SERVER AGENT JOB STEP
------------------------------------------------------------
--
-- declare		@RC int
-- declare	 	@job_name varchar(128)
-- declare		@BACKUP_LOCATION varchar(200)
-- declare		@backup_type VARCHAR(1)
-- declare		@dbname nvarchar(2000)
-- declare		@copy varchar(1)
-- declare		@freq varchar(10)
-- declare  	@production varchar(1)
-- declare 		@INCSIMPLE	varchar(1) 
-- declare 		@ignoredb varchar(1)
-- declare 		@checksum varchar(1)
-- declare 		@isSP varchar(1)
-- declare		@recipient_list	varchar(2000)
--
-- select 		@job_name = 'DARSQL08 (Shared Cluster) Database Backups'
-- select 		@backup_location = '\\darfas01\cifs_sqlbak_sata11$\darsql08\SQLBAK\' --'\\darfas01\cifs_sqlbak_sata11$\DAREPMSQL01\EPM_LIVE\SQLTRN\' --
-- select 		@backup_type = 'F' -- 'F', 'S', 'D', 'T'
-- select 		@dbname ='' --  a valid database name or spaces
-- select 		@copy = 0 -- 1 or 0 -- copy only backup or not
-- select 		@checksum = 1 -- 1 or 0 -- create a checksum for backup integrity validation
-- select 		@freq = 'Daily' -- 'Weekly', 'Daily'
-- select 		@production = 'Y' -- 'Y', 'N' -- only use 'N' for non production instances
-- select 		@INCSIMPLE = 'Y' -- 'Y', 'N' -- include SIMPLE recovery model databases
-- select 		@ignoredb = 'N' -- 'Y' or 'N' -- if "Y" then it will ignore the databases in the @dbname parameter
-- select		@isSP = 'N' -- 'Y' or 'N' -- set to Y if the instance is used for SharePoint. Implemented due to extra long SP database names!
-- select		@recipient_list = 'hkingsland@laingorourke.com;rfinney@laingorourke.com'

-- EXECUTE @RC = [dbadmin].[dba].[generic_backup_all_databases_cloud] 
-- @backup_location,
-- @job_name,
-- @backup_type,
-- @dbname,
-- @copy,
-- @freq,
-- @production,
-- @INCSIMPLE,
-- @ignoredb,
-- @checksum,
-- @isSP,
-- @recipient_list
--
-----------------------
-- Modification History
-----------------------
--
-- 28/10/2008 -- Haden Kingsland --		Added link to Idera SQLDM to email body for Ops.
-- 16/01/2009 -- Haden Kingsland --		Amended procedure to be generic for all backup types.
-- 26/01/2009 -- Haden Kingsland --		Amended procedure to create directory structure if run for a production backup
--										and to enhance error handling and reported error messages.
-- 26/02/2009 -- Haden Kingsland --		To add the @INCSIMPLE flag to allow for differential backups of SIMPLE mode databases 
-- 09/03/2009 -- Haden Kingsland --		To cater for a status of "-2" being returned from the cursor
-- 18/03/2009 -- Haden Kingsland --		To cater for new databases that do not yet have a WEEKLY FULL database backup, when
--										the request is for a TX LOG or DIFF backup. Backup type changed to FULL under these
--										circumstances
--  31/03/2009 -- Haden Kingsland --	Changed to include BULK-LOGGED mode databases for FULL backups.
--										Added the option to check whether xp_cmdshell is on, and if not, turn it on for 
--										the duration on this procedure.
--  07/04/2009 -- Haden Kingsland --	Added a check for "m.mirroring_role <> 1" to ignore all databases acting as a mirror
--
--  01/09/2010 -- Haden Kingsland --	Changed the select statement so that it checks for multiple passed in database names and either 
--										processes all that are passed in, or ignores those that are passed in via a new paramater 
--										call @ignoredb
-- 
--	22/11/2012 -- Haden Kingsland --	To add version checking enhancements for SQL 2012 so that backup compression occurs natively
--										for appropriate versions
--
--	03/02/2014 -- Haden Kingsland --	Added the option to allow for a checksum when performing a backup.
--
--	11/03/2014 -- Haden Kingsland --	Added the @isSP parameter to cater for extraordinary long SharePoint database names!
--										Also added ltrim(rtrim() to the @dbname_dir parameter to remove leading and trailing spaces.
--										Added in a link to the SCOM console in the backup failure email, for when an LOR backup fails
--
--  14/03/2014  -- Haden Kingsland		Now changed to email a list of recipients passed in at runtime upon failure of any one
--										database backup of any type, or if blank, to check for the failsafe operator and email 
--										these addresses.
--
-- backup type can be "F"ull, "D"ifferential, "T"ransaction Log or "S"ystem only. 
--
--#################################################################
 (
    @BACKUP_LOCATION					varchar(200),
    @isCloud							varchar(1), -- ('Y' or 'N')
	@job_name							VARCHAR(128),
	@backup_type						VARCHAR(1), 
	@dbname								nvarchar(2000),
	@copy								varchar(1),
	@freq								varchar(10),
	@production							varchar(1), -- ('Y' or 'N')
	@INCSIMPLE							varchar(1), -- ('Y' or 'N')
	@ignoredb							varchar(1), -- ('Y' or 'N')
	@checksum							varchar(1),	-- ('Y' or 'N')
	@isSP								varchar(1),	-- ('Y' or 'N') -- Used to identify whether an instance is used for SharePoint!
	@recipient_list						varchar(2000) -- list of people to email on failure (for example -- 'hkingsland@laingorourke.com;rfinney@laingorourke.com')
   -- @p_error_description				varchar(300) OUTPUT -- if a called procedure
  )
  
as

BEGIN

DECLARE		@database_name nvarchar(300),
			@dbname_dir varchar(300),
			@DATEH VARCHAR(12),
			@BACKUP_TRAN VARCHAR(500),
			@BACKUP_DB VARCHAR(500),
			@MailProfileName VARCHAR(50),		
			@COMMAND varchar(800),
			@ERR_MESSAGE varchar(200),
			@ERR_NUM int,
			@MESSAGE_BODY varchar(600),
			@MESSAGE_BODY_OPS varchar(600),
			@MESSAGE_BODY2 varchar(600),
			@MESSAGE_BODY3 varchar(600),
			@mirrorrole tinyint,
			@mirror_status tinyint,
			@role varchar(15),
			@ver varchar(15),
			@sql varchar(1000),
			@ext varchar(6),
			@MACHINE varchar(20),
			@Q CHAR(1),
			@dir_type varchar(10),
			@dir varchar(400),
			@subdir varchar(250),
			@diff varchar(12),
			@full_backup_name varchar(30),
			@orig_backup_type varchar(1),
			@changed_backup_type varchar(1),
			@freq_changed varchar(1),
			@orig_freq varchar(10),
			@level varchar(2),
			@XPCMDSH_ORIG_ON varchar(1),
			@credential varchar(30),
			@failsafe VARCHAR(100);


-- ##########
-- START DEBUG
-- ##########

--declare		@RC int
--declare	 	@job_name varchar(128)
--declare		@BACKUP_LOCATION varchar(200)
--declare		@isCloud varchar(1)
--declare		@backup_type VARCHAR(1)
--declare		@dbname nvarchar(2000)
--declare		@copy varchar(1)
--declare		@freq varchar(10)
--declare  	@production varchar(1)
--declare 	@INCSIMPLE	varchar(1) 
--declare 	@ignoredb varchar(1)
--declare 	@checksum varchar(1)
--declare 	@isSP varchar(1)
--declare		@recipient_list varchar(2000)

-- select 		@job_name = 'LABSQLMON01 Database Backups'
-- select 		@backup_location = 'https://dartfordsqlbaktest.blob.core.windows.net/sqlbak/' -- physical location or Azure URL
-- select			@isCloud = 'Y'
-- select 		@backup_type = 'F' -- 'F', 'S', 'D', 'T'
-- select 		@dbname ='RedGateMonitor' --  a valid database name or spaces
-- select 		@copy = 0 -- 1 or 0 -- copy only backup or not
-- select 		@checksum = 1 -- 1 or 0 -- create a checksum for backup integrity validation
-- select 		@freq = 'Daily' -- 'Weekly', 'Daily'
-- select 		@production = 'Y' -- 'Y', 'N' -- only use 'N' for non production instances
-- select 		@INCSIMPLE = 'Y' -- 'Y', 'N' -- include SIMPLE recovery model databases
-- select 		@ignoredb = 'Y' -- 'Y' or 'N' -- if "Y" then it will ignore the databases in the @dbname parameter
-- select			@isSP = 'N' -- 'Y' or 'N' -- set to Y if the instance is used for SharePoint. Implemented due to extra long SP database names!
-- select			@recipient_list = 'hkingsland@laingorourke.com' -- ;rfinney@laingorourke.com'


-- #########
-- END DEBUG
-- #########

-- initialize the variables

select @credential = name 
from sys.credentials
where credential_identity like '%dartfordsqlbaktest%'

select * from sys.credentials

set @orig_backup_type = ''
set @orig_freq = ''
set @changed_backup_type = 'N'
set @freq_changed = 'N' 
set @XPCMDSH_ORIG_ON = ''

SELECT @ver = CASE WHEN @@VERSION LIKE '%9.0%'	THEN 'SQL 2005' 
				   WHEN @@VERSION LIKE '%8.0.%'	THEN 'SQL 2000'
				   WHEN @@VERSION LIKE '%10.0%' THEN 'SQL 2008' 
				   WHEN @@VERSION LIKE '%10.5%' THEN 'SQL 2008 R2' 
				   WHEN @@VERSION LIKE '%11.0%' THEN 'SQL 2012'
				   WHEN @@VERSION LIKE '%12.0%' THEN 'SQL 2014' 
END;

select @@VERSION

SELECT @level =	CASE 
	WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Enterprise%' THEN 'EE' 
	WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Developer%' THEN 'DE' 
	WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Standard%' THEN 'SE'
	WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Web%' THEN 'WE' 
	WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Express%' THEN 'EX'
	WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Business%' THEN 'BI' 
	ELSE 'UNKNOWN'
END;

--SELECT @level =	CASE 
-- 		WHEN @@VERSION LIKE '%Enterprise%' THEN 'EE' 
-- 		WHEN @@VERSION LIKE '%Developer%' THEN 'DE' 
--		WHEN @@VERSION LIKE '%Standard%' THEN 'SE' 
--		WHEN @@VERSION LIKE '%Express%' THEN 'EX' 
--END;

SELECT @full_backup_name = CASE WHEN @backup_type = 'F' THEN 'Full Backup' 
				 WHEN @backup_type = 'D' THEN 'Differential Backup' 
				 WHEN @backup_type = 'T' THEN 'Transaction Log Backup' 
				 WHEN @backup_type = 'S' THEN 'System (Master & MSDB) Backup'  
			 END;

if @dbname<> ''
Begin
	SET @dbname = ',' + @dbname + ','
end

-- SELECT @database_name = DB_NAME()
SET @DATEH	 = CONVERT(CHAR(8),GETDATE(),112) + REPLACE (CONVERT(CHAR(6),GETDATE(),108),':','')
SET @MACHINE = CONVERT(VARCHAR,serverproperty('MachineName'))
SET @Q = CHAR(39) -- ANSI value for a single quote

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%EU-IT-SQL_Alerts%'

--------------------------------------------------------------------------------------------------------------------
-- Check whether xp_cmdshell is turned off via Surface Area Configuration (2005) / Instance Facets (2008)
-- This is best practice !!!!! If it is already turned on, LEAVE it on !!

-- turn on advanced options
	EXEC sp_configure 'show advanced options', 1 reconfigure 
	RECONFIGURE  

	CREATE TABLE #advance_opt (name VARCHAR(20),min int, max int, conf int, run int)
			INSERT #advance_opt
		EXEC sp_configure 'xp_cmdshell' -- this will show whether it is turned on or not
				
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

IF (@BACKUP_LOCATION <> ' ' 
and @job_name <> ' ' 
and @backup_type <> ' ' 
and @copy IN ('1','0')
and @production in ('Y','N')
and @INCSIMPLE in ('Y','N')
and @freq in ('Weekly', 'Daily'))

BEGIN

	DECLARE backup_databases CURSOR FOR
		 
-- #########
-- FOR DEBUG
-- #########

--		 declare @backup_type varchar(1)
--		 declare @dbname varchar(300)
--		 declare @INCSIMPLE varchar(1)
--		 declare @ignoredb varchar(1)

--		 set @INCSIMPLE = 'Y'
--		 set @backup_type = 'F'
--		set @dbname = 'Project_Search_Service_Application_CrawlStoreDB_ae19be63d4fd4a36a9982027c08dcbdb'
--		set @ignoredb = 'N'
		
--	if @dbname<> ''
--Begin
--	SET @dbname = ',' + @dbname + ','
--end
	
-- ######### 
		
	-- Recovery model 
	-- 1 = FULL
	-- 2 = BULK_LOGGED
	-- 3 = SIMPLE
		 		 
			select 
				d.name,
				m.mirroring_role
				from sys.databases d
				inner join sys.database_mirroring m
				on d.database_id = m.database_id
				-- Full Database backups
				--where d.state_desc <> UPPER('restoring') -- ignore any restoring databases
				where d.state not in (1,2,3,6) -- ignore restoring, recovering, recovery pending and offline databases
				and (d.source_database_id is NULL) -- ignore all database snapshots 
				and (
				-- Full Database Backups
						(
							@backup_type = 'F' and @dbname = ''
							and
							-- Pick up ALL SIMPLE mode db's apart from TEMPDB & MODEL, as well as ALL FULL mode databases
							((d.recovery_model = 3 and d.database_id  NOT IN (2,3) and @INCSIMPLE = 'Y' 
							or (d.recovery_model in (1,2) or m.mirroring_role <> 1)) -- ignore databases acting as a mirror
							-- Pick up Master & MSDB in SIMPLE mode as well as ALL FULL/BULK-LOGGED mode databases
							or (d.recovery_model = 3 and d.database_id  IN (1,4) or d.recovery_model in (1,2) and @INCSIMPLE <> 'Y') 
							and d.source_database_id is NULL) -- ignore all database snapshots 	
						)
					-- Differential backups -- ignore all SIMPLE mode databases
					or (
							@backup_type = 'D' and @dbname = ''
							and
							-- Pick up all other FULL recovery mode databases
							(((d.recovery_model in (1,2) or m.mirroring_role <> 1)	-- ignore databases acting as a mirror
							-- Pick up all SIMPLE mode databases not including system db's
							or (d.recovery_model = 3 and @INCSIMPLE = 'Y' and d.database_id  NOT IN (1,2,3,4)))
							and d.source_database_id is NULL) -- ignore all database snapshots		
						)
					-- Transaction Log Backups
					or (
							-- Pick up all other FULL/BULK-LOGGED recovery mode databases
							@backup_type = 'T' and @dbname = ''
							and
							(((d.recovery_model = 1  
							or d.recovery_model = 2) or m.mirroring_role <> 1 ) -- ignore databases acting as a mirror
							and d.database_id  NOT IN (1,2,3,4)
							and d.source_database_id is NULL) -- ignore all database snapshots
						)
						-- Master & MSDB only
					or
						(
							-- Pick up MASTER & MSDB system databases only
							@backup_type = 'S' and @dbname = ''
							and (d.recovery_model = 3 and d.database_id  IN (1,4))
						)
						-- adhoc database backups
					or 
						(
							-- Pick up only the database that has been passed into the procedure
							
							--#################### COMMENTED OUT ON 01/09/2010 ###############################
							--(@dbname = d.name
							--and @dbname <> '') -- will only pick up a single database name passed into the procedure as a parameter
							-- #### NEW ADDED  ON 01/09/2010 ####
							
							-- added to ignore databases that are passed in as they are either backed up elsewhere or don't need backing up
							--or (@dbname <> '' and NOT (CHARINDEX(',' + d.name + ',' , @dbname) > 0) and d.database_id  NOT IN (2,3) and @ignoredb = 'Y')
							(@dbname <> '' and NOT (CHARINDEX(',' + d.name + ',' , @dbname) > 0) and d.database_id  NOT IN (2,3) and @ignoredb = 'Y')
							-- added to only process multiple databases that are passed in as a parameter
							or (@dbname <> '' and  (CHARINDEX(',' + d.name + ',' , @dbname) > 0) and @ignoredb = 'N')
							-- #### NEW END ####
							and 
							(
							((@backup_type = 'F'
							or (@backup_type = 'T' and d.database_id  NOT IN (1,2,3,4)) -- ignore all system databases if backup type TX
							or (@backup_type = 'D' and d.database_id  NOT IN (1,2,3,4)) -- ignore all system databases if backup type Diff
							) or m.mirroring_role <> 1)
							or (@backup_type = 'S' and d.database_id  IN (1,4)) -- ignore model and tempdb databases if backup type System
							)
						) 			
					)
						order by d.name
										
	-- Open the cursor.
	OPEN backup_databases;

	-- Loop through the update_stats cursor.

	FETCH NEXT
	  FROM backup_databases
	  INTO @database_name, @mirrorrole;

	print @@fetch_status

	WHILE @@FETCH_STATUS <> -1 -- Stop when the FETCH statement failed or the row is beyond the result set
	BEGIN

		IF @@FETCH_STATUS = 0 -- to ignore -2 status "The row fetched is missing"
		BEGIN

		set @dbname_dir = ltrim(rtrim(@database_name)) -- put the database name in another variable so it can be used in directory paths
		select @database_name = '[' + @database_name + ']' -- bracket the database name to allow for unusual characters

-- ######################################################################
-- Check to see whether a full database backup has been completed within the last 7 days if the user
-- if requesting a DIFF or TX LOG backup. If not, then change the backup type to be FULL and do a 
-- WEEKLY FULL backup. This is to prevent any errors occuring due to missing FULL database backups.
--
-- D = Database/Full 
-- I = Differential database 
-- L = Log 
-- F = File or filegroup 
-- G = Differential file 
-- P = Partial 
-- Q = Differential partial 
-- Can be NULL.
		
-- ##########
-- START DEBUG
-- ##########
	-- DECLARE @database_name varchar(80),
	--		@orig_backup_type varchar(1),
	--		@changed_backup_type varchar(1),
	--		@dbname_dir varchar(80),
	--		@backup_type varchar(1);
		
	--	set @database_name = 'bpelc3'
	--	set @dbname_dir = @database_name -- put the database name in another variable so it can be used in directory paths
	--	select @database_name = '[' + @database_name + ']' -- bracket the database name to allow for unusual characters
		
	-- set @backup_type = 'T'

	-- print 'Orig .... ' + @orig_backup_type
	-- print 'Changed .... ' + @changed_backup_type
	-- print 'Type ....' + @backup_type
	----select @database_name = '[' + @database_name + ']'

	 
-- ##########
-- END DEBUG
-- ##########

				if @backup_type = 'D' -- Differential
				or @backup_type = 'T' -- Transaction Log
					begin
						if not exists (
						select * from msdb.dbo.backupset
						where type = 'D' -- Database/Full Backup
						and database_name = @dbname_dir -- database name without square brackets
						and backup_finish_date  >= GETDATE()-7 -- there should be a full backup within 7 days of these types
						)
							Begin
								set @orig_backup_type = @backup_type -- store original backup type
								set @changed_backup_type = 'Y'
								set @backup_type = 'F'
								SET @full_backup_name = 'Full Backup' 
								
								if @freq = 'Daily' -- We only want to do a WEEKLY FULL backup to fulfil our needs !!!!
									begin 
										set @orig_freq = @freq
										set @freq = 'Weekly'
										set @freq_changed = 'Y'
									end
								-- print 'Backup Type was changed here to ....' + @backup_type	
							end						
					end
			
-- ##########
-- START DEBUG
-- ##########	
	 --print 'Orig .... ' + @orig_backup_type
	 --print 'Changed .... ' + @changed_backup_type
	 --print 'Type ....' + @backup_type
-- ##########
-- END DEBUG
-- ##########

-- ######################################################################
-- decide which file extension should be used based on the backup type that is passed into the procedure

				if @backup_type <> ('T')
					begin
						if @backup_type = 'D'
							begin
								set @ext = '.diff'
							end
						else	
							begin
								if @backup_type in ('F','S')
									begin
										set @ext = '.bak'
									end
							end
						set @dir_type = 'SQL_Full'
					end
				else
					begin
						set @ext = '.trn'
						set @dir_type = 'SQL_Trans'
					end		

-- not if azure......
IF @isCloud = 'N'
BEGIN

			IF @production = 'Y'
			or @production is NULL
			or @production = '' -- if backup for a prod/systest/uat system then use folders per database name
			
				begin	

					-- build up query string of file location in order to check for it's existence
					
					If @isSP = 'Y'
						Begin
							set @subdir = @backup_location + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\SharePoint_DB\'
							print @subdir
						end
					else
						Begin
							set @subdir = @backup_location + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\' + @dbname_dir + '\'
							print @subdir
						end

					set @dir = 'dir ' + @subdir
					--set @dir = @Q + 'dir ' + @subdir + @Q

					print 'Directory structure is ..... ' + @dir
					
					-- use xp_cmdshell to check existence of the required database named directory
					CREATE TABLE #DirResults (Diroutput VARCHAR(500))
						INSERT #DirResults
					exec xp_cmdshell @dir  
					--exec xp_cmdshell "dir \\chs120nas1\sql_backup$\CODA_SQL\CODALIVE\Weekly\SQL_Full\CODAPROCLIVE"

					-- if no directory of the required name is found, then create one
					IF EXISTS (
						select * from #DirResults where Diroutput like '%File Not Found%'  
						or (Diroutput like '%The system cannot find the path specified%')
						or (Diroutput like '%The system cannot find the file specified%')
					)
					BEGIN
					print 'creating dir here ...'
						--EXECUTE master.dbo.xp_create_subdir N'\\rus14file1\y$\EDM SYSTEST_BKP\Weekly\Database\\master';
						-- re-define the @subdir variable using a \\ after the @backup_location to create a directory from that point onwards 
						
						If @isSP = 'Y'
							Begin
								set @subdir = 'execute master.dbo.xp_create_subdir ' +'N' + @Q + @backup_location + '\' + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\SharePoint_DB' + @Q
							end
						else
							Begin
								set @subdir = 'execute master.dbo.xp_create_subdir ' +'N' + @Q + @backup_location + '\' + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\' + @dbname_dir + @Q
							end
							
						exec (@subdir); -- create directory structure
						print @subdir
					END

					drop table #DirResults
				
					--SET @BACKUP_DB = @backup_location + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\' + @dbname_dir  + '\'  + @database_name + '_' + @MACHINE + '_BACKUP_' + @DATEH + @ext

-- ####################################################################
-- 11/03/2014
-- ####################################################################
					If @isSP = 'Y'
						Begin
							SET @BACKUP_DB = @backup_location + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\SharePoint_DB\'  + @database_name + '_' + @DATEH + @ext
						end
					else
						begin
							SET @BACKUP_DB = @backup_location + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\' + @dbname_dir  + '\'  + @database_name + '_' + @MACHINE + '_BACKUP_' + @DATEH + @ext
						end
				end
				
-- ############################################################################################################################################
-- if for a development system, then use a generic area with NO specific database named directories, so db's can be added/removed as required.
-- ############################################################################################################################################	

			else
				begin
							
					-- build up query string of file location in order to check for it's existence
					
					If @isSP = 'Y'
						Begin
							set @subdir = @backup_location + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\SharePoint_DB\'
							print @subdir
						end
					else
						Begin
							set @subdir = @backup_location + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\'
							print @subdir
						end

					set @dir = 'dir ' + @subdir

					print 'Directory structure is ..... ' + @dir

					-- use xp_cmdshell to check existence of the required database named directory
					CREATE TABLE #DirResults2 (Diroutput VARCHAR(500))
						INSERT #DirResults2
					exec xp_cmdshell @dir 
					--exec xp_cmdshell "dir \\chs120nas1\sql_backup$\CHS123SQL\SQL_INST1\Daily\SQL_Full\"

					-- if no directory of the required name is found, then create one
					IF EXISTS (
						select * from #DirResults2 where Diroutput like '%File Not Found%'  
						or (Diroutput like '%The system cannot find the path specified%')
						or (Diroutput like '%The system cannot find the file specified%')
					)
					BEGIN
						--EXECUTE master.dbo.xp_create_subdir N'\\rus14file1\y$\EDM SYSTEST_BKP\Weekly\Database\\master';
						-- re-define the @subdir variable using a \\ after the @backup_location to create a directory from that point onwards 					
						If @isSP = 'Y'
							Begin
								set @subdir = 'execute master.dbo.xp_create_subdir ' +'N' + @Q + @backup_location + '\' + @@SERVICENAME + '\' + @freq + '\SharePoint_DB' + @Q
							end	
						else		
							Begin
								set @subdir = 'execute master.dbo.xp_create_subdir ' +'N' + @Q + @backup_location + '\' + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + @Q
							end
							
						exec (@subdir); -- create directory structure
						print 'creating dir .... ' + @subdir
					END

					drop table #DirResults2

					--SET @BACKUP_DB = @backup_location + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\' +  @database_name +  '_' + @MACHINE + '_BACKUP_' + @DATEH + @ext

-- ####################################################################
-- 11/03/2014
-- ####################################################################

					If @isSP = 'Y'
						Begin
							SET @BACKUP_DB = @backup_location + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\SharePoint_DB\'  + @database_name + '_' + @DATEH + @ext
						end
					else
						begin
							SET @BACKUP_DB = @backup_location + @@SERVICENAME + '\' + @freq +  '\' + @dir_type + '\' +  @database_name +  '_' + @MACHINE + '_BACKUP_' + @DATEH + @ext
						end
				

				end	
-- not if azure......

END

-- if it is azure......
if @isCloud = 'Y'
	BEGIN
		Set @BACKUP_DB = @backup_location +  @database_name +  '_' + @MACHINE + '_BACKUP_' + @DATEH + @ext
	END


					PRINT 'Backing up ... ' + @database_name;
					PRINT @BACKUP_DB

					BEGIN TRY
					
					--  format correct syntax for type of backup specified
					
					IF @backup_type in ('F','D', 'S')
						BEGIN
							set @sql = 'BACKUP DATABASE ' 
						END;
					ELSE
						BEGIN
							set @sql = 'BACKUP LOG '
						END;
					print @sql
					
					-- If SQL 2012 or 2014 and we do not require cloud backups, OR the version is not
					-- SQL 2012 or 2014, then...
					
					IF ((LTRIM(RTRIM(@ver)) = 'SQL 2012' or  LTRIM(RTRIM(@ver)) = 'SQL 2014')
					    and @isCloud = 'N')
					OR 
					   (LTRIM(RTRIM(@ver)) != 'SQL 2012' 
					   and  LTRIM(RTRIM(@ver)) != 'SQL 2014')
						BEGIN
							IF @backup_type = 'D' -- if a differential backup
								BEGIN
									set @sql = @sql + @database_name + ' TO DISK='  + @Q + @BACKUP_DB  + @Q + 
									' WITH DIFFERENTIAL, RETAINDAYS = 14, NOFORMAT, NOINIT'
								END
							ELSE
								BEGIN
									print 'here i am'
									set @sql = @sql + @database_name + ' TO DISK='  + @Q + @BACKUP_DB  + @Q + 
									' WITH RETAINDAYS = 14, NOFORMAT, NOINIT'
								END
						END
						print @ver
						print @iscloud
						
					-- If SQL 2012 or 2014 and we require cloud backups, then...
						
					IF ((LTRIM(RTRIM(@ver)) = 'SQL 2012'
					or  LTRIM(RTRIM(@ver)) = 'SQL 2014')
					and @isCloud = 'Y')
						BEGIN
							IF @backup_type = 'D' -- if a differential backup
								BEGIN
									set @sql = @sql + @database_name + ' TO URL = '  + @Q + @BACKUP_DB  + @Q + 
									' WITH CREDENTIAL =' + @Q + @credential + @Q + 
									', DIFFERENTIAL, NOFORMAT, NOINIT'
								END
							ELSE
								BEGIN
								--print @database_name
								--print @backup_db
								--print @credential
								--print @SQL
								
								print 'here i am in the azure bit'
									set @sql = @sql + @database_name + ' TO URL = '  + @Q + @BACKUP_DB  + @Q +
									' WITH CREDENTIAL =' + @Q + @credential + @Q + 
									', NOFORMAT, NOINIT'
								END
						END;
					-- SQL Server 2008 Enterprise Edition or SQL Server 2008 R2/SQL 2012 SE,DE or EE 
					-- can backup using page level compression.
	
--	BACKUP DATABASE AdventureWorks2012 
--TO URL = 'https://mystorageaccount.blob.core.windows.net/mycontainer/AdventureWorks2012.bak' 
--      WITH CREDENTIAL = 'mycredential' 
--     ,COMPRESSION
--     ,STATS = 5;
--GO 

--BACKUP DATABASE [DBAdmin] 
--TO URL = 'https://dartfordsqlbak.blob.core.windows.net/dartfordsqlbak/DBAdmin_LABSQLMON01_BACKUP.bak' 
--WITH CREDENTIAL ='mycredential', NOFORMAT, NOINIT,  CHECKSUM, NO_COMPRESSION
			
						--print 'version=' + @ver
					
						IF LTRIM(RTRIM(@ver)) = 'SQL 2008'
							BEGIN
								IF @level = 'EE' 
								or @level = 'DE'
								BEGIN
									set @sql = @sql + ', COMPRESSION'
								END
							END;
						ELSE
						-- amended to cater for SQL 2012 as this also uses compression for both 
						-- Standard and Enterprise editions
							IF LTRIM(RTRIM(@ver)) = 'SQL 2008 R2'  
							or LTRIM(RTRIM(@ver)) = 'SQL 2012'
							or LTRIM(RTRIM(@ver)) = 'SQL 2014'
								BEGIN
								IF @level != 'EX' -- not supported in Express version
									BEGIN
										set @sql = @sql + ', COMPRESSION'
									END
								END
								
						-- if you want a copy only backup, it will be appended to the end of the backup command		
						IF @copy = 1 
							BEGIN
								set @sql = @sql + ', COPY_ONLY'
							END;

-- ##############################################################################################################						
-- 03/02/2014 -- checksum added	
-- if you want a checksum for the backup, it will be appended to the end of the backup command		
-- ##############################################################################################################

						IF @checksum = 1 
							BEGIN
								set @sql = @sql + ', CHECKSUM'
							END;			
							
-- ##############################################################################################################

						-- execute the backup command
						print @sql;
						exec (@sql);
									
					END TRY

					BEGIN CATCH
					
-- ##############################################################################################################
-- 14/03/2014 -- Now changed to email a list of recipients passed in at runtime, or if blank, to check for the 
-- failsafe operator and email these address
-- ##############################################################################################################	
	
			IF @recipient_list IS NULL 
			or @recipient_list = ''
			BEGIN
			
				SELECT @recipient_list = email_address
				FROM msdb..sysoperators
				WHERE name = 'LOR_SQL_Admin_Alerts' -- Name of main required operator
				
				IF @recipient_list IS NULL
				BEGIN
							
					EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
												 N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',
												 N'AlertFailSafeOperator',
												 @failsafe OUTPUT,
												 N'no_output'

					SELECT @recipient_list = email_address
					FROM msdb..sysoperators
					WHERE name = @failsafe
					                             
				END
			END
			
			PRINT @recipient_list

			--select email_Address 
			--FROM msdb..sysoperators
			--WHERE name = 'LOR_SQL_Admin_Alerts' -- Name of main required operator

-- ##############################################################################################################		

						SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();
						SET @MESSAGE_BODY='Error Backing Up ' + @database_name + '. Error Code ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message ' + @ERR_MESSAGE
						--SET @MESSAGE_BODY_OPS='Error Backing Up ' + @database_name + 'Error Code ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message ' + @ERR_MESSAGE + 'Please inform Tech Services for next working day'
						SET @MESSAGE_BODY2='Failure of ' + @job_name + ' ' + @freq + ' ' + @full_backup_name + ' within ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(30)))) + '.' + @database_name
						-- 11/03/2014 -- Added in a link to the SCOM console for LOR
						SET @MESSAGE_BODY3=' Check the SCOM Console for further information...  http://lorom01:51908/default.aspx'
						SET @MESSAGE_BODY = @MESSAGE_BODY + @MESSAGE_BODY3

						--EXEC msdb.dbo.sp_notify_operator 
						--	@profile_name = @MailProfileName, 
						--	@name=N'Haden Kingsland',
						--	@subject = @MESSAGE_BODY2, 
						--	@body= @MESSAGE_BODY

						PRINT @MESSAGE_BODY
						
						EXEC msdb.dbo.sp_send_dbmail
							@profile_name = @MailProfileName,
							--@recipients = 'hkingsland@laingorourke.com',
							@recipients = @recipient_list,
							@importance = 'HIGH',
							@body = @MESSAGE_BODY,
							@subject = @MESSAGE_BODY2

						-- on error within the procedure, check for existence of temporary tables
						-- used by this procedure and delete them if they exist, just to be tidy!

						IF EXISTS (select * from tempdb.sys.objects
						where name like '%advance_opt%')
							BEGIN
								drop table #advance_opt
							END

					END CATCH
					
			-- END

		END -- end of @@fetchstatus if
		
		-- if the backup type has been changed for the database that has just been processed,
		-- then change the backup type back to it's original value and reset the other associated
		-- variables.
		
		if @changed_backup_type = 'Y'
			begin
				set @backup_type = @orig_backup_type
				set @orig_backup_type = ''
				set @changed_backup_type = 'N'
				
				-- set the Full Backup name back to be what it was prior to the change 
				SELECT @full_backup_name = CASE 
					WHEN @backup_type = 'F' THEN 'Full Backup' 
					WHEN @backup_type = 'D' THEN 'Differential Backup' 
					WHEN @backup_type = 'T' THEN 'Transaction Log Backup' 
					WHEN @backup_type = 'S' THEN 'System (Master & MSDB) Backup'  
				 END;
				
				-- set @freq back to it's original value
				if @freq_changed = 'Y'
					begin
						set @freq = @orig_freq
						set @orig_freq = ''
						set @freq_changed = 'N'
					end
			end

	FETCH NEXT FROM backup_databases INTO @database_name, @mirrorrole;
	
	--print 'DATABASE NAME IS ..... ' + @database_name
	--print 'Fetch is ... ' + convert(nvarchar(10),@@FETCH_STATUS)

	END

	-- Close and deallocate the cursor.

	CLOSE backup_databases;
	DEALLOCATE backup_databases;

END;

ELSE

-- raise appropriate errors if parameters are left blank or incorrect values are given

	BEGIN
		IF @backup_location = ' '
			BEGIN
				raiserror('Parameter @backup_location must NOT be spaces', 16, 1);
			END
		ELSE
			BEGIN
				IF @job_name = ' '
					BEGIN
						raiserror('Parameter @job_name must NOT be spaces', 16, 1);
					END
				ELSE
					BEGIN
						IF @backup_type = ' '
							BEGIN
								raiserror('Parameter @backup_type must NOT be spaces', 16, 1);
							END
						ELSE
							BEGIN
								IF @copy not in ('0','1')
									BEGIN
										raiserror('Parameter @copy MUST be a value of ''1'' or ''0'')', 16, 1);
									END
								ELSE
									BEGIN
										IF @production not in ('Y','N')
											BEGIN
												raiserror('Parameter @production MUST be a value of ''Y'' or ''N'')', 16, 1);
											END
										ELSE
											BEGIN
												IF @freq not in ('Weekly','Daily')
													BEGIN
														raiserror('Parameter @freq MUST have a value of ''Weekly'' or ''Daily'')', 16, 1);
													END
												ELSE
													BEGIN
														IF @INCSIMPLE not in ('Y','N')
															BEGIN
																raiserror('Parameter @INCSIMPLE MUST be a value of ''Y'' or ''N'')', 16, 1);
															END
														ELSE
															BEGIN
																IF @ignoredb not in ('Y','N')
																	BEGIN
																		raiserror('Parameter @ignoredb MUST be a value of ''Y'' or ''N'')', 16, 1);
																	END
															END
													END
											END
									END
							END
					END
			END		
	END	
	
	-----------------------------------------------------------------------------------------------------------------------		
-- turn off advanced options

	IF @XPCMDSH_ORIG_ON = 'N'  -- if xp_cmdshell was NOT originally turned on, then turn it off 
	BEGIN

		--  turn off xp_cmdshell to dis-allow operating system commands to be run
		EXEC sp_configure 'xp_cmdshell', 0  reconfigure
		RECONFIGURE

		EXEC sp_configure 'show advanced options', 0 reconfigure
		RECONFIGURE
		
		 
	END
-----------------------------------------------------------------------------------------------------------------------
			
END;

