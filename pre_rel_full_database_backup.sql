USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[pre_rel_full_database_backup]    Script Date: 07/09/2018 09:58:14 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dba].[pre_rel_full_database_backup]

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 12/12/2007
-- Version	: 01:00
--
-- Desc		: To backup a given database prior to a database release
--
--			  Backup path must exist on target server, for example:
--            \\your server\your dir\your other dir\
--
-- Modification History
-- ====================
--
--
--#############################################################
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
-- input parameters, which must be passed in to run procedure, for example ....
-- exec dba.pre_rel_full_database_backup 'edm','rus14file1', 045
--
-- EXECUTE master.dbo.xp_create_subdir N'\\your server\your dir\your other dir\master';
--

 (
    @database_name				varchar(30),
	@backup_location			varchar(30),
	@release_num					int

   -- @p_error_description				varchar(300) OUTPUT
  )

-- WITH RECOMPILE -- recompile the procedure each time it is run

as

BEGIN

DECLARE @DATEH VARCHAR(12);
DECLARE @BACKUP_DB VARCHAR(250);
DECLARE @MailProfileName VARCHAR(50);
DECLARE @COMMAND varchar(800);
DECLARE @ERR_MESSAGE varchar(200);
DECLARE @ERR_NUM varchar(10);
DECLARE @MESSAGE_BODY varchar(250);
DECLARE @SUBJECT_LINE varchar(250);
DECLARE @MACHINE varchar(20)

SET @DATEH	 = CONVERT(CHAR(8),GETDATE(),112) + REPLACE (CONVERT(CHAR(6),GETDATE(),108),':','')
SET @MACHINE = CONVERT(VARCHAR,serverproperty('MachineName'))

	SELECT @MailProfileName = name
		FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
		WHERE name like '%DBA%'

SET @BACKUP_DB = @backup_location + @@SERVICENAME + '\Weekly\SQL_Full\' + 'pre_' + RTRIM(CONVERT(CHAR(3),@release_num)) + '_' + @database_name + @MACHINE + '_BACKUP_' + @DATEH + '.bak'

	PRINT 'Backing up ... ' + @database_name;
	PRINT @BACKUP_DB

	BEGIN TRY
		BACKUP DATABASE @database_name TO DISK=@BACKUP_DB with NOFORMAT;
	END TRY

	BEGIN CATCH

		SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();
		SET @MESSAGE_BODY='Error Backing Up ' + @database_name + ' Error Code ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message ' + @ERR_MESSAGE
		SET @SUBJECT_LINE='Failure of Pre Release Database Backup for ' + @database_name + ' on ' + @@SERVERNAME

		EXEC msdb.dbo.sp_notify_operator 
			@profile_name = @MailProfileName, 
			@name=N'DBA-Alerts',
			@subject = @subject_line, 
			@body= @MESSAGE_BODY

		PRINT @MESSAGE_BODY

	END CATCH

END

