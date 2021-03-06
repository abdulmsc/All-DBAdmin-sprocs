USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_LongRunningJobs]    Script Date: 07/09/2018 10:16:02 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 18/09/2010
-- Version	: 01:00
--
-- Desc		: To email selected operators the details of long running 
--			  SQL Agent jobs
--
-- Modification History
-- ====================
--
-- 07/09/2018		Haden Kingsland		To add the ability to pass in the email address to send details to.
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
-- Useage..
--
--exec dbadmin.dba.usp_LongRunningJobs 'yourname@youremail.com'
--
ALTER PROCEDURE [dba].[usp_LongRunningJobs]
@MailRecipients VARCHAR(200)
AS
--Set Mail Profile
DECLARE @MailProfile VARCHAR(50),
		@email_subject varchar(250),
		@JobLimitPercentage FLOAT;

-- Use a table variable to hold all of the currently running jobs
DECLARE @currently_running_jobs TABLE (
    job_id UNIQUEIDENTIFIER NOT NULL
    ,last_run_date INT NOT NULL
    ,last_run_time INT NOT NULL
    ,next_run_date INT NOT NULL
    ,next_run_time INT NOT NULL
    ,next_run_schedule_id INT NOT NULL
    ,requested_to_run INT NOT NULL
    ,-- BOOL
    request_source INT NOT NULL
    ,request_source_id SYSNAME COLLATE database_default NULL
    ,running INT NOT NULL
    ,-- BOOL
    current_step INT NOT NULL
    ,current_retry_attempt INT NOT NULL
    ,job_state INT NOT NULL
    )

-- 0 = Not idle or suspended 
-- 1 = Executing
-- 2 = Waiting For Thread
-- 3 = Between Retries 
-- 4 = Idle
-- 5 = Suspended 
-- 6 = WaitingForStepToFinish 
-- 7 = PerformingCompletionActions


SELECT @MailProfile = name
FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
where name like '%DBA%'

--SET @MailProfile = (
--        SELECT @@SERVERNAME
--        ) --Replace with your mail profile name
 
--Set Email Recipients

--Set limit in minutes (applies to all jobs)
--NOTE: Percentage limit is applied to all jobs where average runtime greater than 5 minutes
--else the time limit is simply average + 10 minutes

SET @JobLimitPercentage = 150 --Use whole percentages greater than 100
    -- Create intermediate work tables for currently running jobs
 
--Capture Jobs currently working
INSERT INTO @currently_running_jobs
EXECUTE master.dbo.xp_sqlagent_enum_jobs 1,''
 
--Temp table exists check
IF OBJECT_ID('tempdb..##RunningJobs') IS NOT NULL
    DROP TABLE ##RunningJobs
 
CREATE TABLE ##RunningJobs (
    [JobID] [UNIQUEIDENTIFIER] NOT NULL
    ,[JobName] [sysname] NOT NULL
    ,[StartExecutionDate] [DATETIME] NOT NULL
    ,[AvgDurationMin] [INT] NULL
    ,[DurationLimit] [INT] NULL
    ,[CurrentDuration] [INT] NULL
    )
 
INSERT INTO ##RunningJobs (
    JobID
    ,JobName
    ,StartExecutionDate
    ,AvgDurationMin
    ,DurationLimit
    ,CurrentDuration
    )
SELECT jobs.Job_ID AS JobID
    ,jobs.NAME AS JobName
    ,act.start_execution_date AS StartExecutionDate
    ,AVG(FLOOR(run_duration / 100)) AS AvgDurationMin
    ,CASE
        --If job average less than 5 minutes then limit is avg+10 minutes
        WHEN AVG(FLOOR(run_duration / 100)) <= 5
            THEN (AVG(FLOOR(run_duration / 100))) + 10
        --If job average greater than 5 minutes then limit is avg*limit percentage
        ELSE (AVG(FLOOR(run_duration / 100)) * (@JobLimitPercentage / 100))
        END AS DurationLimit
    ,DATEDIFF(MI, act.start_execution_date, GETDATE()) AS [CurrentDuration]
FROM @currently_running_jobs crj
INNER JOIN msdb..sysjobs AS jobs ON crj.job_id = jobs.job_id
INNER JOIN msdb..sysjobactivity AS act ON act.job_id = crj.job_id
    AND act.stop_execution_date IS NULL
    AND act.start_execution_date IS NOT NULL
INNER JOIN msdb..sysjobhistory AS hist ON hist.job_id = crj.job_id
    AND hist.step_id = 0
WHERE crj.job_state = 1
GROUP BY jobs.job_ID
    ,jobs.NAME
    ,act.start_execution_date
    ,DATEDIFF(MI, act.start_execution_date, GETDATE())
HAVING CASE
        WHEN AVG(FLOOR(run_duration / 100)) <= 5
            THEN (AVG(FLOOR(run_duration / 100))) + 10
        ELSE (AVG(FLOOR(run_duration / 100)) * (@JobLimitPercentage / 100))
        END < DATEDIFF(MI, act.start_execution_date, GETDATE())
 
--Checks to see if a long running job has already been identified so you are not alerted multiple times
IF EXISTS (
        SELECT RJ.*
        FROM ##RunningJobs RJ
        WHERE CHECKSUM(RJ.JobID, RJ.StartExecutionDate) NOT IN (
                SELECT CHECKSUM(JobID, StartExecutionDate)
                FROM dbo.LongRunningJobs
                )
        )
    --Send email with results of long-running jobs
    set @email_subject = 'Long Running SQL Agent Job Alert for... ' + @@SERVERNAME + ' Please Read!'
    
    EXEC msdb.dbo.sp_send_dbmail 
		@profile_name = @MailProfile,
        @recipients = @MailRecipients,
        @query = 'USE DBAdmin; Select RJ.*
			From ##RunningJobs RJ
			WHERE CHECKSUM(RJ.JobID,RJ.StartExecutionDate) 
			NOT IN (Select CHECKSUM(JobID,StartExecutionDate) From dbo.LongRunningJobs) '
        ,@body = 'View attachment to view long running SQL Agent jobs'
        ,@subject = @email_subject
        ,@attach_query_result_as_file = 1;
 
--Populate LongRunningJobs table with jobs exceeding established limits
INSERT INTO [DBAdmin].[dbo].[LongRunningJobs] (
    [JobID]
    ,[JobName]
    ,[StartExecutionDate]
    ,[AvgDurationMin]
    ,[DurationLimit]
    ,[CurrentDuration]
    ) (
    SELECT RJ.* FROM ##RunningJobs RJ WHERE CHECKSUM(RJ.JobID, RJ.StartExecutionDate) NOT IN (
        SELECT CHECKSUM(JobID, StartExecutionDate)
        FROM dbo.LongRunningJobs
        )
    )
    DROP TABLE ##RunningJobs
