USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[sp_block_info]    Script Date: 07/09/2018 10:05:54 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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


ALTER proc [dba].[sp_block_info]
as

select t1.resource_type as [lock type]
	,db_name(resource_database_id) as [database]
	,t1.resource_associated_entity_id as [blk object]
	,t1.request_mode as [lock req]			-- lock requested
	,t1.request_session_id as [waiter sid]  -- spid of waiter
	,t2.wait_duration_ms as [wait time]	
	,(select text from sys.dm_exec_requests as r  --- get sql for waiter
		cross apply sys.dm_exec_sql_text(r.sql_handle) 
		where r.session_id = t1.request_session_id) as waiter_batch
	,(select substring(qt.text,r.statement_start_offset/2, 
			(case when r.statement_end_offset = -1 
			then len(convert(nvarchar(max), qt.text)) * 2 
			else r.statement_end_offset end - r.statement_start_offset)/2) 
		from sys.dm_exec_requests as r
		cross apply sys.dm_exec_sql_text(r.sql_handle) as qt
		where r.session_id = t1.request_session_id) as waiter_stmt    --- this is the statement executing right now
	 ,t2.blocking_session_id as [blocker sid] -- spid of blocker
     ,(select text from sys.sysprocesses as p		--- get sql for blocker
		cross apply sys.dm_exec_sql_text(p.sql_handle) 
		where p.spid = t2.blocking_session_id) as blocker_stmt
	from 
	sys.dm_tran_locks as t1, 
	sys.dm_os_waiting_tasks as t2
where 
	t1.lock_owner_address = t2.resource_address

