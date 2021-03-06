USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_readerrorlog]    Script Date: 07/09/2018 10:22:46 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 12/12/2008
-- Version	: 01:00
--
-- Desc		: To search the SQL Agent or SQL Error Logs for specific strings using a call
--				   to the extended stored procedure sys.xp_readerrorlog.
--
-- Modification History
-- ====================
--
--#############################################################
--
--This procedure takes four parameters:
--If you do not pass any parameters this will return the contents of the current error log.
--
--@logfile_value		Value of error log file you want to read: 0 = current, 1 = Archive #1, 2 = Archive #2, etc...  
--@logfile_type		    Log file type: 1 or NULL = error log, 2 = SQL Agent log 
--@str1					Search string 1: String one you want to search for 
--@str2					Search string 2: String two you want to search for to further refine the results
--
-- This script was written in order to alert us that the following event has occured within the
-- SQL Agent log ....
--

--EXEC sys.xp_readerrorlog 0,1,'ENABLE'

-- [LOG] Exception 253 caught at line 431 of file t:\yukon\sql\komodo\src\core\sqlagent\src\job.cpp  
-- SQLServerAgent initiating self-termination.
--
-- Effects of this error are as follows .....
--
-- This seems to be caused by SQL Agent jobs that are set to run when the CPU is idle.
-- This affects more than just the agent. The memory allocated to the SQL instance drops right off 
-- after this error causes the agent to crash and then there are issues reading and writing to the database. 
-- The only way to get the agent started again and everything back to normal has been a reboot of the server.
--
-- Here are a few examples:
--
-- EXEC master.dba.usp_readerrorlog 6, 1, '2005', 'exec'
-- 
-- exec master.dba.usp_readerrorlog 0, 2, 'Exception 253' (EXEC sys.xp_readerrorlog 0 ,2, 'Exception 253')
--
-- insert master.dba.readerrorlog_results EXEC master.dba.dba_readerrorlog 2, 2, 'start'
-- insert master.dba.readerrorlog_results (lastrun) values (getdate());
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

ALTER PROC  [dba].[usp_readerrorlog]
( 
   @logfile_value     INT = 0, 
   @logfile_type      INT = NULL, 
   @str1				 VARCHAR(255) = NULL, 
   @str2				 VARCHAR(255) = NULL
  ) 
   
AS 

BEGIN 

SET NOCOUNT ON

DECLARE @NewLine CHAR(2),
			@Q CHAR(1),
			@message varchar(1000),
			@COMMAND varchar(1000),
			@ERR_MESSAGE varchar(800),
			@ERR_NUM int,
			@MESSAGE_BODY varchar(500),
			@MESSAGE_BODY_OPS varchar(350),
			@MESSAGE_BODY2 varchar(500),
			@MESSAGE_BODY3 varchar(500),
			@MESSAGE_BODY5 varchar(1000),
			@DATEH VARCHAR(12),
			@MACHINE varchar(20),
			@MailProfileName VARCHAR(50),
			@messdate varchar(30),
			@like varchar(100);

--
-- FOR DEBUG PURPOSES
--
-- DECLARE @logfile_value   INT, 
--			@logfile_type INT, 
--			@str1		VARCHAR(255), 
--			@str2		VARCHAR(255);

--set @logfile_value = 1
--set @logfile_type = 1
--set @str1 = 'Error:'
--set @str2 = ''

--EXEC sys.xp_readerrorlog @logfile_value,@logfile_type,@str1,@str2

--insert into dba.readerrorlog_results EXEC sys.xp_readerrorlog @logfile_value,@logfile_type,@str1,@str2

SET @DATEH	 = CONVERT(CHAR(8),GETDATE(),112) + REPLACE (CONVERT(CHAR(6),GETDATE(),108),':','')
SET @MACHINE = CONVERT(VARCHAR,serverproperty('MachineName'))
--set @message = ''

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'
--
-- ascii characters for LF, CR & single quote respectively
--
SET @Q = CHAR(39) 
SET @newLine = CHAR(13) + CHAR(10) 

	BEGIN TRY

-- 
-- if it doesn't already exist, create the dba.readerrorlog_results table in the master database
-- to store the results of this sp. The following is run from a seperate SQL Agent job in order 
-- to keep the table house kept
--
-- 	delete from master.dba.readerrorlog_results
--	where LogDate < getdate()-7
--
		IF NOT EXISTS (select * from sys.sysobjects WHERE name = N'readerrorlog_results')
			BEGIN
				create table dba.readerrorlog_results
				(
				LogDate char(24), --datetime, 
				Processinfo varchar(200),
				Text varchar(8000)
				)
			END

	-- drop table master.dba.readerrorlog_results
	-- select * from master.dba.readerrorlog_results

		-- only continue if the user is of sysadmin level !!!!

		IF (NOT IS_SRVROLEMEMBER(N'securityadmin') = 1) 
		BEGIN 
			RAISERROR(15003,-1,-1, N'securityadmin') 
			--RETURN (1)
		END 
		    	    
		-- run the extended stored procedure sys.xp_readerrorlog to read the sql log
		-- for the specified input parameter and search the errorlog.
		
		IF (@logfile_type IS NULL) 
			BEGIN
				insert into dba.readerrorlog_results EXEC sys.xp_readerrorlog @logfile_value
			END
	--select * from master.dba.readerrorlog_results 
		ELSE 
				BEGIN
					--EXEC sys.xp_readerrorlog 0,1,'unsent log'
					insert into dba.readerrorlog_results EXEC sys.xp_readerrorlog @logfile_value,@logfile_type,@str1,@str2 
				END
				

-- set the @message parameter to be the text from the errorlog entry whose date/time is between the current
-- date/time and the current date/time - 30 minutes. This will only flag up events that happened within the last
-- 30 minutes, and ignore any old events in the log.

		set @like = '%' + @str1 + '%'
		print @like

		select @message = text,
				 @messdate = RTRIM(convert(varchar(30),logdate))
				 from dba.readerrorlog_results
				 where text like @like
				 group by LogDate, text
				having max(LogDate) between  DATEADD(mi,-30, getdate()) and getdate() -- < DATEADD(mi,-2, getdate())
				order by (cast(LogDate as varchar(20))) desc
		--group by text,LogDate
		--having max(LogDate) between  DATEADD(mi,-600, getdate()) and getdate() -- < DATEADD(mi,-2, getdate())
		
			--print RTRIM(convert(varchar(30),@messdate))
			--print @message
	
	
		select  text,
				 RTRIM(convert(varchar(30),logdate))
				 from dba.readerrorlog_results
				  where text like @like
		group by LogDate, text
		having max(LogDate) between  DATEADD(mi,-30, getdate()) and getdate() -- < DATEADD(mi,-2, getdate())
		order by (cast(LogDate as varchar(20))) desc
		
		--print  @message + ' ' +  CONVERT(CHAR(8),@messdate,112) + REPLACE (CONVERT(CHAR(6),@messdate,108),':','')
		
		-- if an event of the required type has occurred within the last 30 minutes, then @message will not be NULL and
		-- so an email should be sent to the nominated person to this effect.
		
		If @message is NOT NULL
		or @message <> ''
		BEGIN
		
			--print  @message 
		
			--set @MESSAGE_BODY2 = ''
			--set @MESSAGE_BODY5 = ''
			SET @MESSAGE_BODY2 = 'An event containing ' + @str1 + ' has occured within the SQL Log for ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(20))))
			SET @MESSAGE_BODY5 = 'The following event has occured within .... ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(20)))) + 
			@newline + @message  + ' ' + RTRIM(convert(varchar(30),@messdate)) + @newline + 'Please check the SQL Server Log on this server\instance for full details of the event'
			
			print @MESSAGE_BODY2
			print @MESSAGE_BODY5
			print @str1
			print RTRIM(convert(varchar(30),@messdate))
			print @message

			EXEC msdb.dbo.sp_notify_operator 
				@profile_name = @MailProfileName, 
				@name=N'DBA-Alerts',
				@subject = @MESSAGE_BODY2, 
				@body= @MESSAGE_BODY5
		
		END

	END TRY

	BEGIN CATCH
	
		--print  @message

		SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();
		SET @MESSAGE_BODY='Error details follow .... Error Code ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message ' + @ERR_MESSAGE
		SET @MESSAGE_BODY2='Failure of running the dba_readerrorlog sp within the ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(20)))) + ' instance'
		SET @MESSAGE_BODY = @MESSAGE_BODY

		EXEC msdb.dbo.sp_notify_operator 
			@profile_name = @MailProfileName, 
			@name=N'DBA-Alerts',
			@subject = @MESSAGE_BODY2, 
			@body= @MESSAGE_BODY

	END CATCH

END

