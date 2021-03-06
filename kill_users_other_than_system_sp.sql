USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[kill_users_other_than_system_sp]    Script Date: 07/09/2018 09:52:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dba].[kill_users_other_than_system_sp] 
--
--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 08/09/2010
-- Version	: 01:00
--
-- Desc		:	To check for users other than myself and "sa" in a given (passed in)
--				database. This is to be run prior to a restore to ensure that an exclusive lock
--				can be taken on the database to do the restore.
--				MUST exist in the MASTER DB of the receiving instance as remotely called from the
--				restore_databases_to_another_instance_sp stored procedure on the source instance.
--
----#############################################################
--
-----------------------
-- Modification History
-----------------------
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
@dbname sysname,
--@output nvarchar(500) output,
@p_error_description varchar(300) OUTPUT
)

AS

BEGIN

DECLARE @strSQL varchar(255),
		@MailProfileName VARCHAR(50),
		@spid varchar(10), 
		@loginame varchar(255),
		@program_name varchar(128),
		@hostname varchar(20),
		@MESSAGE_BODY varchar(2000),
		@MESSAGE_BODY2 varchar(1000)
--,
--@p_error_description varchar(300),
--@output nvarchar(500),
--@dbname nvarchar(50);

--set @dbname = 'DynaMaster_Restaurants'

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'

	PRINT 'Killing ' + UPPER(@dbname) + ' Database Connections'
	PRINT '----------------------------------------------------'
	DECLARE LoginCursor CURSOR READ_ONLY
	for select spid, loginame, program_name, hostname from master..sysprocesses
	where UPPER(cmd) not in (
	'LAZY WRITER', 
	'LOG WRITER', 
	'SIGNAL HANDLER', 
	'LOCK MONITOR', 
	'TASK MANAGER', 
	'RESOURCE MONITOR',
	'CHECKPOINT SLEEP',
	'CHECKPOINT',
	'BRKR TASK',
	'BRKR EVENT HNDLR',
	'TRACE QUEUE TASK')
	AND db_name(dbid) = @DBNAME
	--AND hostname != '<any host>'
	and loginame <> 'sa'
	and loginame not like '%NT AUTHORITY\SYSTEM%'
	--and loginame <> '<SQL Agent Account>'

	OPEN LoginCursor

	FETCH NEXT FROM LoginCursor INTO @spid, @loginame, @program_name, @hostname
	
	WHILE (@@fetch_status <> -1)
	BEGIN
		IF (@@fetch_status <> -2)
			BEGIN
			
				PRINT 'Killing user spid: ' + @spid + ' Name: ' + @loginame
				SET @strSQL = 'KILL ' + @spid
				
				BEGIN TRY
				
					--set @output = ISNULL(@output,' ') + ' ' + @strsql
					--print @output
					--PRINT @strSQL
					
				EXEC (@strSQL)
				 
				SET @MESSAGE_BODY = ' User: ' + @spid + ' ' + LTRIM(RTRIM(@loginame)) + ' was killed as part of the restore to database ... ' + @dbname + ' in instance ... ' + @@SERVERNAME + '. Program name: ' + LTRIM(RTRIM(@program_name)) + ' was running on host: ' + @hostname
				SET @MESSAGE_BODY2 = ' User: ' + @spid + ' has been killed! in database ... ' + @dbname

				EXEC msdb.dbo.sp_notify_operator 
					@profile_name = @MailProfileName, 
					@name=N'DBA-Alerts',
					@subject = @MESSAGE_BODY2, 
					@body= @MESSAGE_BODY
				 
				END TRY
				
				BEGIN CATCH
					SELECT @p_error_description = ERROR_MESSAGE();
					RETURN;
				END CATCH
				
			END
	
		FETCH NEXT FROM LoginCursor INTO @spid, @loginame, @program_name, @hostname
		
	END
	
	CLOSE LoginCursor
	
	DEALLOCATE LoginCursor

END
RETURN;

