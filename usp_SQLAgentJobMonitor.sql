USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_SQLAgentJobMonitor]    Script Date: 07/09/2018 10:29:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- #####################################################################################################################
--
-- exec dbadmin.dba.usp_SQLAgentJobMonitor 'last24'
-- exec dbadmin.dba.usp_SQLAgentJobMonitor 'LastRun'
-- exec dbadmin.dba.usp_SQLAgentJobMonitor 'Nightly Full Backups'
--
-- Description:		To get the history of all/any SQL Agent jobs and timings associated with them
-- Date:			22/10/2012
-- Author:			Haden Kingsland
-- Reference:		http://www.sqlmag.com/article/tsql3/tracking-for-your-sql-server-agent-jobs
--
-- #####################################################################################################################

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


ALTER procedure [dba].[usp_SQLAgentJobMonitor]
	(@listType varchar(1000) = 'LastRun')
as

if @listType = 'LastRun'
	select distinct [name] as 'Job Name',
		case [enabled] when 1 then 'Enabled' else 'Disabled' end as 'Enabled',
		cast (ltrim(str(run_date))+' '+stuff(stuff(right('000000'+ltrim(str(run_time)), 6) , 3, 0, ':'), 6, 0, ':') as datetime) as 'Last Run',
		step_id as Step,
		case [h].[run_status] 
			when 0 then 'Failed' else 'Success'
			end as 'Status' , 
		STUFF(STUFF(REPLACE(STR(run_duration,6),' ','0'),5,0,':'),3,0,':') as 'Duration', 
		case next_run_date 
			  when '0' then '9999-jan-01'
			  else cast (ltrim(str(next_run_date))+' '+stuff(stuff(right('000000'+ltrim(str(next_run_time)), 6) , 3, 0, ':'), 6, 0, ':') as datetime) 
				end as 'Next Run' 
	from msdb.dbo.sysjobs         j
	left join msdb.dbo.sysjobschedules s on j.job_id = s.job_id
	join msdb.dbo.sysjobhistory   h on j.job_id = h.job_id
	where step_id = 0
	  and h.instance_id in (select max(sh.instance_id)
					from msdb.dbo.sysjobs sj   
					join msdb.dbo.sysjobhistory   sh on sj.job_id = sh.job_id
					where h.step_id = 0
					group by sj.name	)
else
if @listType = 'Last24'
	select distinct [name] as 'Job Name',
		case [enabled] when 1 then 'Enabled' else 'Disabled' end as 'Enabled',
		cast (ltrim(str(run_date))+' '+stuff(stuff(right('000000'+ltrim(str(run_time)), 6) , 3, 0, ':'), 6, 0, ':') as datetime) as 'Job Run',
		step_id as Step,
		case [h].[run_status] 
			when 0 then 'Failed' else 'Success'
			end as 'Status' , 
		STUFF(STUFF(REPLACE(STR(run_duration,6),' ','0'),5,0,':'),3,0,':') as 'Duration', 
		case next_run_date 
			  when '0' then '9999-jan-01'
			  else cast (ltrim(str(next_run_date))+' '+stuff(stuff(right('000000'+ltrim(str(next_run_time)), 6) , 3, 0, ':'), 6, 0, ':') as datetime) 
				end as 'Next Run' 
	from msdb.dbo.sysjobs         j
	left join msdb.dbo.sysjobschedules s on j.job_id = s.job_id
	join msdb.dbo.sysjobhistory   h on j.job_id = h.job_id
	where 
		cast (ltrim(str(run_date))+' '+stuff(stuff(right('000000'+ltrim(str(run_time)), 6) , 3, 0, ':'), 6, 0, ':') as datetime)
			  > dateadd(hour, -24, getdate())
	 and step_id = 0
	 
else
  begin
	select [name] as 'Job Name',
		case [enabled] when 1 then 'Enabled' else 'Disabled' end as 'Enabled',
		cast (ltrim(str(run_date))+' '+stuff(stuff(right('000000'+ltrim(str(run_time)), 6) , 3, 0, ':'), 6, 0, ':') as datetime) as 'Job Run',
		step_id as Step,
		case [h].[run_status] 
			when 0 then 'Failed' else 'Success'
			end as 'Status' , 
		STUFF(STUFF(REPLACE(STR(run_duration,6),' ','0'),5,0,':'),3,0,':') as 'Duration', 
		case next_run_date 
			  when '0' then '9999-jan-01'
			  else cast (ltrim(str(next_run_date))+' '+stuff(stuff(right('000000'+ltrim(str(next_run_time)), 6) , 3, 0, ':'), 6, 0, ':') as datetime) 
				end as 'Next Run' 
	from msdb.dbo.sysjobs         j
	left join msdb.dbo.sysjobschedules s on j.job_id = s.job_id
	join msdb.dbo.sysjobhistory   h on j.job_id = h.job_id
	where  j.name like '%' + @listType + '%'
		 and step_id = 0
    order by 3 desc
  end

