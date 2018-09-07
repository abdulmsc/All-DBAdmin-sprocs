
CREATE PROCEDURE [dba].[usp_quick_check_user_info]

--#######################################################################
--
-- Author	: Haden Kingsland
-- Date		: 07/09/2018
-- Version	: 01:00
--
-- Desc		: To quickly show any connected users and their state
--
-- Modification History
-- ====================
--
--#######################################################################
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
-- 0 = online, 1 = restoring, 2 = recovering, 
-- 3 = recovery pending, 4 = suspect, 5 = emergency, 
-- 6 = offline
-- run as below...
--
-- 	exec [dba].[usp_quick_check_user_info]
--
/********************************************************************************************************************/
AS

BEGIN

	SELECT DB_NAME(sys.dbid), 
		   sys.loginame, 
		   sys.spid, 
		   sys.blocked,
		   CASE des.status -- added to show status of current sessions
			   WHEN 'RUNNING'
			   THEN 'Session running'
			   WHEN 'SLEEPING'
			   THEN 'No current requests running'
			   WHEN 'DORMANT'
			   THEN 'Connection reset due to resource pooling'
			   WHEN 'PreConnect'
			   THEN 'Session is in the resource governor classifier function'
		   END AS session_status,
		   --req.open_transaction_count,
		   sqltext.TEXT, 
		   sys.hostname, 
		   sys.program_name, 
		   sys.nt_username, 
		   sys.login_time, 
		   sys.last_batch, 
		   COUNT(sys.loginame) OVER(PARTITION BY DB_NAME(sys.dbid)) AS 'Total number of logins/user', -- return total number of logins/login
		   CASE des.transaction_isolation_level
			   WHEN 0
			   THEN 'Unspecified'
			   WHEN 1
			   THEN 'ReadUncommitted'
			   WHEN 2
			   THEN 'ReadCommitted'
			   WHEN 3
			   THEN 'Repeatable'
			   WHEN 4
			   THEN 'Serializable'
			   WHEN 5
			   THEN 'Snapshot'
		   END AS TRANSACTION_ISOLATION_LEVEL
	FROM sys.sysprocesses sys
		 INNER JOIN sys.dm_exec_sessions des ON des.session_id = sys.spid
		 --right outer join sys.dm_exec_requests req
		 --on sys.spid = req.session_id
		 CROSS APPLY sys.dm_exec_sql_text(sys.sql_handle) AS sqltext
	WHERE sys.hostname IS NOT NULL
		  AND sys.hostname <> ''
	GROUP BY sys.loginame, 
			 sys.program_name, 
			 sys.hostname, 
			 sys.nt_username, 
			 sys.login_time, 
			 sys.last_batch, 
			 sys.spid, 
			 sys.dbid, 
			 des.transaction_isolation_level, 
			 des.status, 
			 sys.blocked, 
			 sqltext.TEXT
	ORDER BY des.status, 
			 DB_NAME(sys.dbid), 
			 des.transaction_isolation_level, 
			 sys.login_time ASC
END;