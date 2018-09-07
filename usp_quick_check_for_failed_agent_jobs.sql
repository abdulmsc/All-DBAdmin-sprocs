
USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_quick_check_for_failed_agent_jobs]    Script Date: 07/09/2018 11:21:17 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
alter PROCEDURE [dba].[usp_quick_check_for_failed_agent_jobs]

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 07/09/2018
-- Version	: 01:00
--
-- Desc		: To quickly show any failed SQL Agent jobs
--
-- Modification History
-- ====================
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
-- 	exec [dba].[usp_quick_check_for_failed_agent_jobs]
--
/********************************************************************************************************************/
AS

BEGIN
	SELECT name AS [Job Name]
			 ,CONVERT(VARCHAR,DATEADD(S,(run_time/10000)*60*60 /* hours */
			 +((run_time - (run_time/10000) * 10000)/100) * 60 /* mins */
			 + (run_time - (run_time/100) * 100) /* secs */
			   ,CONVERT(DATETIME,RTRIM(run_date),113)),100) AS [Time Run]
			 ,CASE WHEN enabled=1 THEN 'Enabled'
				   ELSE 'Disabled'
			 END [Job Status]
			 ,CASE WHEN SJH.run_status=0 THEN 'Failed'
						   WHEN SJH.run_status=1 THEN 'Succeeded'
						   WHEN SJH.run_status=2 THEN 'Retry'
						   WHEN SJH.run_status=3 THEN 'Cancelled'
				   ELSE 'Unknown'
			 END [Job Outcome]
	FROM   MSDB..sysjobhistory SJH 
	JOIN   MSDB..sysjobs SJ   
	ON     SJH.job_id=sj.job_id 
	WHERE step_id=0 
	AND   DATEADD(S,
	(run_time/10000)*60*60 /* hours */
	+((run_time - (run_time/10000) * 10000)/100) * 60 /* mins */
	+ (run_time - (run_time/100) * 100) /* secs */,
	CONVERT(DATETIME,RTRIM(run_date),113)) >= DATEADD(d,-1,GetDate())
	and SJH.run_status = 0 -- failed
	ORDER BY name,run_date,run_time
END;