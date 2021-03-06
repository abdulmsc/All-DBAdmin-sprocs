USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[Create_Database_snapshot_relnum]    Script Date: 07/09/2018 08:30:19 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 24/01/2008
-- Version	: 01:00
--
-- Desc		: To create a database snapshot of a given database
--			  exec dba.Create_Database_snapshot haden
--
--			see for listing on ascii characters 
--			http://www.robelle.com/smugbook/ascii.txt
--
--			To restore from a snapshot
--			USE master;
--			RESTORE DATABASE edm FROM DATABASE_SNAPSHOT = 'edm_snap';
--
--			To delete a snapshot
--			DROP DATABASE edm_snap_200802211613;
--
-- Modification History
-- ====================
-- 
--
--#############################################################
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

ALTER PROCEDURE [dba].[Create_Database_snapshot_relnum]
    (
		@Masterdb VARCHAR(255),
		@Relnum VARCHAR(20)
		--@SnapshotName VARCHAR(255)
--		@Execute BIT = 1
	) 


AS 

BEGIN

    SET NOCOUNT ON 
    DECLARE @NewLine CHAR(2);
    DECLARE @Q CHAR(1);
    DECLARE @fname VARCHAR(255);
    DECLARE @extention VARCHAR(255); 
    DECLARE @Directory VARCHAR(255);
    DECLARE @DBname VARCHAR(255); 
    DECLARE @LogicName VARCHAR(255); 
    DECLARE @Command VARCHAR(8000);
    DECLARE @indexExt INT;
    DECLARE @indexPfad INT; 
    DECLARE @lenFname INT;
    DECLARE @lenDirectory INT; 
    DECLARE @lenDB INT; 
    DECLARE @lenExt INT; 
	DECLARE @DATEH VARCHAR(12);
	DECLARE @MACHINE varchar(20);
	DECLARE @SnapshotName VARCHAR(255);
	DECLARE @MailProfileName VARCHAR(50);
	DECLARE @ERR_MESSAGE varchar(300)
	DECLARE @ERR_NUM int;
	DECLARE @MESSAGE_BODY varchar(2000);
	DECLARE @MESSAGE_BODY2 varchar(2000);
	DECLARE @MESSAGE_BODY3 varchar(4000);
	DECLARE @MESSAGE_SUBJECT varchar(2000);

-- SELECT @database_name = DB_NAME()
	SET @DATEH	 = CONVERT(CHAR(8),GETDATE(),112) + REPLACE (CONVERT(CHAR(6),GETDATE(),108),':','')
	SET @MACHINE = CONVERT(VARCHAR,serverproperty('MachineName'))
	SET @SnapshotName = @MasterDB + '_snap'

	SELECT @MailProfileName = name
		FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
		WHERE name like '%DBA%'

	BEGIN TRY

		CREATE TABLE #Info
			(physical_name VARCHAR(255) not null, 
			logicname VARCHAR(255) not null) 

	--
	-- ascii characters for LF, CR & single quote respectively
	--
		SET @newLine = CHAR(13) + CHAR(10) 
		SET @Q = CHAR(39) 

		SET @command = 'INSERT INTO #info (physical_name, logicname) 
			SELECT 
			mf.physical_name,
			mf.name
			FROM
				sys.master_files mf
			INNER JOIN' + Quotename(@MasterDB) + '.sys.filegroups fg ON 
				mf.type = 0 
				AND mf.database_id = db_id(' + @Q + @Masterdb + @Q + ') 
				AND mf.drop_lsn is null 
				AND mf.data_space_id = fg.data_space_id 
			ORDER BY
				fg.data_space_id' 
		EXECUTE (@Command) 

		SET @Command = 'CREATE DATABASE ' + @SnapshotName + '_' + @DATEH + '_REL_' + LTRIM(RTRIM(@Relnum)) + @NewLine 
		SET @Command = @Command + 'ON' + @NewLine 

		DECLARE FILENAMES_CUR CURSOR 
		READ_ONLY 
		FOR SELECT physical_name, logicname FROM #info 

		OPEN FILENAMES_CUR
	 
		FETCH NEXT FROM FILENAMES_CUR INTO @fname,@LogicName 
			WHILE @@FETCH_STATUS = 0
	      
			BEGIN 
	        
	-- get file name in reverse -- eg) fdn.6_mde\SELIF_REVRES_LQS\:d
				SET @fname = REVERSE(@fname) 
	-- get length on filename in full
				SET @lenFname = LEN(@fname)
	-- get length of file extension 
				SET @indexExt = CHARINDEX('.',@fname) -1 
	-- get length of everything upto the first '\' from the left -- this gives you the path
				SET @indexPfad = CHARINDEX('\',@fname) - 1 
	-- get the actual extension, using the length of the extension and the filename
				SET @extention = REVERSE(SUBSTRING (@fname, 1, @indexExt)) 
	-- get the length of the extension once again!
				SET @lenExt = LEN(@extention) 
	-- get the file path from left to right, by taking the length upto the first '/' from the
	-- the total length of the filename
				SET @Directory = LEFT (REVERSE(@fname), @lenFname - @indexPfad) 
	-- get the length of the directory structure
				SET @lenDirectory = LEN(@Directory) 
				--SET @DBname = SUBSTRING(REVERSE(@fname), @lenPfad + 1, (@lenFname - @lenPfad - @lenExt) - 1) 
	-- build up the snapshot command line by line, using the current datafile directory structure
				SET @Command = @Command + '(Name = ' + @Q + @LogicName + @Q + ', Filename = ' + @Q 
				SET @Command = @Command + @Directory + @SnapshotName + '_' + @LogicName + '_' + @DATEH + '_REL_' + LTRIM(RTRIM(@Relnum)) + '.' + 'snap' + @Q + '),' + @NewLine 
	        
	--			print @fname
	--			print @lenFname
	--			print @indexExt
	--			print @indexPfad
	--			print @extention
	--			print @lenExt
	--			print @lenPfad
	--			print @DBname
	--			print @command

				FETCH NEXT FROM FILENAMES_CUR INTO @fname,@LogicName 

			END 

		CLOSE FILENAMES_CUR 
		DEALLOCATE FILENAMES_CUR 

	-- strip off the last comma at the end of the command

		SET @Command = LEFT(@Command,LEN(@Command)-3) + @NewLine + 'AS SNAPSHOT OF ' + @masterdb 
		print @command

		DROP TABLE #Info

		EXEC (@Command) 

	END TRY

	BEGIN CATCH

		SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();
		
		SET @MESSAGE_BODY='Error creating DB Snapshot for ' + @masterdb + '. Error Code ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message ' + @ERR_MESSAGE
		SET @MESSAGE_SUBJECT='Failure of ' + LTRIM(RTRIM(cast(@@SERVICENAME as VARCHAR(20)))) + '.' + @masterdb +  ' database snapshot creation'
		SET @MESSAGE_BODY3 = @MESSAGE_BODY + @newline + @Command
									
		EXEC msdb.dbo.sp_notify_operator 
			@profile_name = @MailProfileName, 
			@name=N'DBA-Alerts',
			@subject = @MESSAGE_SUBJECT, 
			@body= @MESSAGE_BODY3	

	END CATCH

END;

