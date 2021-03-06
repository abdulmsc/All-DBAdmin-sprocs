USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[dba_failed_sql_agent_jobs_daily]    Script Date: 07/09/2018 08:56:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- #######################################################################################
--
-- Author:			Haden Kingsland
--
-- Date:			29th September 2015
--
-- Description :	To report on the latest failed SQL Agent jobs from the last run of such jobs.
--
-- This procedure uses the below view to build up the cursor and so this view MUST be
-- created in each SQL instance, under the DBADMIN database before this procedure
-- can be run!
--
--use [dbadmin]
--go

--alter VIEW dba.View_Failed_Jobs
--    AS
--    SELECT   Job.instance_id
--        ,SysJobs.job_id
--        ,SysJobs.name as 'JOB_NAME'
--        ,SysJobSteps.step_name as 'STEP_NAME'
--        ,Job.run_status
--        ,Job.sql_message_id
--        ,Job.sql_severity
--        ,Job.message
--        ,Job.exec_date
--        ,Job.run_duration
--        ,Job.server
--        ,SysJobSteps.output_file_name
--    FROM    (SELECT Instance.instance_id
--        ,DBSysJobHistory.job_id
--        ,DBSysJobHistory.step_id
--        ,DBSysJobHistory.sql_message_id
--        ,DBSysJobHistory.sql_severity
--        ,DBSysJobHistory.message
--        ,(CASE DBSysJobHistory.run_status
--            WHEN 0 THEN 'Failed'
--            WHEN 1 THEN 'Succeeded'
--            WHEN 2 THEN 'Retry'
--            WHEN 3 THEN 'Canceled'
--            WHEN 4 THEN 'In progress'
--        END) as run_status
--        ,((SUBSTRING(CAST(DBSysJobHistory.run_date AS VARCHAR(8)), 5, 2) + '/'
--        + SUBSTRING(CAST(DBSysJobHistory.run_date AS VARCHAR(8)), 7, 2) + '/'
--        + SUBSTRING(CAST(DBSysJobHistory.run_date AS VARCHAR(8)), 1, 4) + ' '
--        + SUBSTRING((REPLICATE('0',6-LEN(CAST(DBSysJobHistory.run_time AS varchar)))
--        + CAST(DBSysJobHistory.run_time AS VARCHAR)), 1, 2) + ':'
--        + SUBSTRING((REPLICATE('0',6-LEN(CAST(DBSysJobHistory.run_time AS VARCHAR)))
--        + CAST(DBSysJobHistory.run_time AS VARCHAR)), 3, 2) + ':'
--        + SUBSTRING((REPLICATE('0',6-LEN(CAST(DBSysJobHistory.run_time as varchar)))
--        + CAST(DBSysJobHistory.run_time AS VARCHAR)), 5, 2))) AS 'exec_date'
--        ,DBSysJobHistory.run_duration
--        ,DBSysJobHistory.retries_attempted
--        ,DBSysJobHistory.server
--        FROM msdb.dbo.sysjobhistory DBSysJobHistory
--        JOIN (SELECT DBSysJobHistory.job_id
--            ,DBSysJobHistory.step_id
--            ,MAX(DBSysJobHistory.instance_id) as instance_id
--            FROM msdb.dbo.sysjobhistory DBSysJobHistory
--            GROUP BY DBSysJobHistory.job_id
--            ,DBSysJobHistory.step_id
--            ) AS Instance ON DBSysJobHistory.instance_id = Instance.instance_id
--        --join msdb.dbo.sysjobsteps st
--        --on st.job_id = DBSysJobHistory.job_id
--        WHERE DBSysJobHistory.run_status <> 1
--        ) AS Job
--    JOIN msdb.dbo.sysjobs SysJobs
--       ON (Job.job_id = SysJobs.job_id)
--    JOIN msdb.dbo.sysjobsteps SysJobSteps
--       ON (Job.job_id = SysJobSteps.job_id AND Job.step_id = SysJobSteps.step_id)
--    GO
    
--					
-- Modification History
-- ####################
--
-- exec dbadmin.dba.dba_failed_sql_agent_jobs_daily 'anyperson@anyemail.com;anyperson@anyemail.com'
--
-- #######################################################################################
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



ALTER procedure [dba].[dba_failed_sql_agent_jobs_daily]
@recipient_list varchar(2000) -- list of people to email
as

BEGIN

DECLARE		@MailProfileName VARCHAR(50),		
			@ERR_MESSAGE varchar(200),
			@ERR_NUM int,
			@MESSAGE_BODY varchar(2000),
			@MESSAGE_BODY2 varchar(1000),
			@p_error_description varchar(300),
			@NewLine CHAR(2),
			@Q CHAR(1),
			@tableHTML VARCHAR(MAX),
			@tableHTML2 VARCHAR(MAX),
			@lineHTML VARCHAR(MAX),
			@lineHTML2 VARCHAR(MAX),
			@start_table VARCHAR(MAX),
			@start_table2 VARCHAR(MAX),
			@TR varchar(20),
			@END	 varchar(30),
			@END_TABLE varchar(30),
			@ENDTAB varchar(20),
			--@recipient_list	varchar(1000),
			@email varchar(100),
			@failsafe VARCHAR(100), -- failsafe operator to email
			@value varchar(30),
			@mailsubject varchar(200),
			@propertyid int,
			@userid bigint, 
			--@recipient_list varchar(2000),
			@td varchar(25),
		    @jobname varchar(50), 
			@jobstep varchar(80),
			@runstatus varchar(10),
			@message varchar(100),
			@execdate datetime,
			@runduration int,
			@sqlinstance varchar(20);

SET @NewLine = CHAR(13) + CHAR(10) 
SET @Q = CHAR(39) 

-- initialize variables (otherwise concat fails because the variable value is NULL)

set @lineHTML = '' 
set @tableHTML = ''
set @start_table = ''
--set @days = 10

SET @tableHTML =
		'<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Frameset// EN">' +
		'<html>' +
		'<LANG="EN">' +
		'<head>' +
		'<TITLE>SQL Administration</TITLE>' +
		'</head>' +
		'<body>'
		
set @start_table = '<font color="black" face="Tahoma" >' + 
	'<CENTER>' + 
	'<H1><font size=4>The following SQL Agent Jobs failed... '+ @@servername + '</font></H1>' +
	'<table border="1">' +
	'<tr BGCOLOR="green">' + 
	-- list all table headers here
	'<th BGCOLOR="#0066CC" width="100%" colspan="7">Database Details</th>'+'</tr>' + 
	'<tr>' + 
	--'<th BGCOLOR="#99CCFF">Server Name</th>' + 
	'<th BGCOLOR="#99CCFF">Job Name</th>' +
	'<th BGCOLOR="#99CCFF">Job Step Name</th>' + 
	'<th BGCOLOR="#99CCFF">Run Status</th>' +
	'<th BGCOLOR="#99CCFF">Error Message</th>' +
	'<th BGCOLOR="#99CCFF">Execution Date</th>' +
	'<th BGCOLOR="#99CCFF">Run Duration</th>' + 
	'<th BGCOLOR="#99CCFF">SQL Instance</th>' +
	'</tr>'

SET @TR = '</tr>'
SET @ENDTAB = '</table></font>'
--SET @END = '</table></font></body></html>'
SET @END_TABLE = '</table></font>'
SET @END = '</body></html>'

SET @mailsubject   = 'The following SQL Agent Jobs have failed to complete... '

SELECT @MailProfileName = name
FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
where name like '%DBA%'

PRINT @MailProfileName

	BEGIN TRY
	
	DECLARE build_report_failed_jobs CURSOR
	FOR
		SELECT   SysJobs.name
			,SysJobSteps.step_name
			,Job.run_status
			,Job.message
			,max(Job.exec_date) as 'Execution Date' -- get most recent failed job run date
			,Job.run_duration
			,Job.server
		FROM    (SELECT Instance.instance_id
			,DBSysJobHistory.job_id
			,DBSysJobHistory.step_id
			,DBSysJobHistory.sql_message_id
			,DBSysJobHistory.sql_severity
			,DBSysJobHistory.message
			,(CASE DBSysJobHistory.run_status
				WHEN 0 THEN 'Failed'
				WHEN 1 THEN 'Succeeded'
				WHEN 2 THEN 'Retry'
				WHEN 3 THEN 'Cancelled'
				--WHEN 4 THEN 'In progress' -- not needed as these should be ignored!
			END) as run_status
			,((SUBSTRING(CAST(DBSysJobHistory.run_date AS VARCHAR(8)), 5, 2) + '/'
			+ SUBSTRING(CAST(DBSysJobHistory.run_date AS VARCHAR(8)), 7, 2) + '/'
			+ SUBSTRING(CAST(DBSysJobHistory.run_date AS VARCHAR(8)), 1, 4) + ' '
			+ SUBSTRING((REPLICATE('0',6-LEN(CAST(DBSysJobHistory.run_time AS varchar)))
			+ CAST(DBSysJobHistory.run_time AS VARCHAR)), 1, 2) + ':'
			+ SUBSTRING((REPLICATE('0',6-LEN(CAST(DBSysJobHistory.run_time AS VARCHAR)))
			+ CAST(DBSysJobHistory.run_time AS VARCHAR)), 3, 2) + ':'
			+ SUBSTRING((REPLICATE('0',6-LEN(CAST(DBSysJobHistory.run_time as varchar)))
			+ CAST(DBSysJobHistory.run_time AS VARCHAR)), 5, 2))) AS 'exec_date'
			,DBSysJobHistory.run_duration
			,DBSysJobHistory.retries_attempted
			,DBSysJobHistory.server
			FROM msdb.dbo.sysjobhistory DBSysJobHistory
			JOIN (SELECT DBSysJobHistory.job_id
				,DBSysJobHistory.step_id
				,MAX(DBSysJobHistory.instance_id) as instance_id
				FROM msdb.dbo.sysjobhistory DBSysJobHistory
				GROUP BY DBSysJobHistory.job_id
				,DBSysJobHistory.step_id
				) AS Instance ON DBSysJobHistory.instance_id = Instance.instance_id
			--join msdb.dbo.sysjobsteps st
			--on st.job_id = DBSysJobHistory.job_id
			WHERE DBSysJobHistory.run_status in (0,3) -- cancelled or failed
			) AS Job
		JOIN msdb.dbo.sysjobs SysJobs ON (Job.job_id = SysJobs.job_id)
		JOIN msdb.dbo.sysjobsteps SysJobSteps ON (Job.job_id = SysJobSteps.job_id AND Job.step_id = SysJobSteps.step_id)
		   where job.run_status != 'In progress' -- to ignore long running jobs or jobs used for log shipping!
		   group by SysJobs.name,
		   SysJobSteps.step_name,
			Job.run_status,
			Job.message,
			Job.run_duration,
			Job.server


-- print 'i am here 1!'

		-- Open the cursor.
		OPEN build_report_failed_jobs;

-- print 'i am here 2!'

		-- Loop through the update_stats cursor.

		FETCH NEXT
		   FROM build_report_failed_jobs
		   INTO  @jobname, 
		   @jobstep,
		   @runstatus,
		   @message,
		   @execdate,
		   @runduration,
		   @sqlinstance

		PRINT 'Fetch Status is ... ' + CONVERT(VARCHAR(10),@@FETCH_STATUS)

		WHILE @@FETCH_STATUS <> -1 -- Stop when the FETCH statement fails or the row is beyond the result set
		BEGIN

			IF @@FETCH_STATUS = 0 -- to ignore -2 status "The row fetched is missing"
			BEGIN

				set @lineHTML = RTRIM(LTRIM(@lineHTML)) + 
								'<tr>' + 
								'<td>' + ISNULL(cast(@jobname as varchar(50)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@jobstep as varchar(50)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@runstatus as varchar(10)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@message as varchar(50)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(left( convert (char(20) ,@execdate, 113 ), 17),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@runduration as varchar(5)),'NOVAL') + '</td>' +
								'<td>' +  ISNULL(cast(@sqlinstance as varchar(20)),'NOVAL') + '</td>'
								+ '</tr>'
								
				-- set @lineHTML = REPLACE( @lineHTML, '<td>', '<td BGCOLOR=orange>' );
	
				IF @runstatus = 'Failed'
				BEGIN
					set @lineHTML = REPLACE( @lineHTML, '<td>', '<td BGCOLOR=#FF0000>' ); -- red
				END
		
				IF @runstatus != 'Failed' 
				BEGIN
					set @lineHTML = REPLACE( @lineHTML, '<td>', '<td BGCOLOR=#66FF33>' ); -- green
				END

				-- print @lineHTML

			END
		
		FETCH NEXT
		   FROM build_report_failed_jobs
		   INTO  @jobname, 
		   @jobstep,
		   @runstatus,
		   @message,
		   @execdate,
		   @runduration,
		   @sqlinstance
		   
		END

		-- Close and deallocate the cursor.

		CLOSE build_report_failed_jobs;
		DEALLOCATE build_report_failed_jobs;

print ' i am here 3!'

-- 03/02/2012 -- changed to check the contents of the @linehtml variable, so that it will not generate an email if there
-- is not data to display.

print '@linehtml is ... ' + @lineHTML

		IF (@lineHTML != '' and @lineHTML is not NULL)
		BEGIN
	
			set @tableHTML = RTRIM(LTRIM(@tableHTML)) + @start_table + RTRIM(LTRIM(@lineHTML)) + @END_TABLE + @END

			-- as the <td> tags are auto-generated, I need to replace then with a new <td>
			-- tag including all the required formatting.

			--set @tableHTML = REPLACE( @tableHTML, '<td>', '<td BGCOLOR=yellow>' );
			
			print @tableHTML
		
			IF @recipient_list IS NULL 
			or @recipient_list = ''
			BEGIN
			
				SELECT @recipient_list = email_address
				FROM msdb..sysoperators
				WHERE name = 'DBA-Alerts' -- Name of main required operator
				
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
			
			EXEC msdb.dbo.sp_send_dbmail
				@profile_name = @MailProfileName,
				@recipients = @recipient_list,
				@body_format = 'HTML',
				@importance = 'HIGH',
				@body = @tableHTML,
				@subject = @mailsubject
				
		END
		
	END TRY

	BEGIN CATCH
	
	print 'Error Code is ... ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message is ... ' + @ERR_MESSAGE
	
		SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();
		SET @MESSAGE_BODY='Error running the ''dba_failed_sql_agent_jobs_daily'' ' 
		+  '. Error Code is ... ' + RTRIM(CONVERT(CHAR(10),@ERR_NUM)) + ' Error Message is ... ' + @ERR_MESSAGE
		SET @MESSAGE_BODY2='The script failed whilst running against the... ' + LTRIM(RTRIM(cast(@@SERVERNAME as VARCHAR(30)))) + ' instance'
		SET @MESSAGE_BODY = @MESSAGE_BODY -- + @MESSAGE_BODY3

		EXEC msdb.dbo.sp_notify_operator 
			@profile_name = @MailProfileName, 
			@name=N'DBA-Alerts',
			@subject = @MESSAGE_BODY2, 
			@body= @MESSAGE_BODY
	
	-- If for some reason this script fails, check for any temporary
	-- tables created during the run and drop them for next time.
	
		IF object_id('tempdb..#temp_vm_create') IS NOT NULL
		BEGIN
		   DROP TABLE #temp_vm_create
		END

	END CATCH
	
END

