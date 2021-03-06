USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_show_IO_latency_for_SQL_drives]    Script Date: 07/09/2018 10:24:07 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 31/10/2010
-- Version	: 01:00
--
-- Desc		: To email details of IO latency over a given scheduled period
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
/********************************************************************************************************************/
-- Useage...
--
-- exec dba.usp_show_IO_latency_for_SQL_drives 'youname@youremail.com'
--
ALTER procedure [dba].[usp_show_IO_latency_for_SQL_drives]
 @EmailRecipients varchar(200)
as

begin

declare @EmailSubject as varchar (255),
		@EmailBody as nvarchar (max),
		@MailProfileName VARCHAR(50);

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'

set @EmailSubject = 'I-O Latency Report for... ' + @@servername;
set @EmailBody = 'Report to show I-O latency within for all SQL Server drives ';

	--set @sqlcmd = 'SELECT
	--	[Total Read Latency (MS)] =
	--		CASE WHEN [num_of_reads] = 0
	--			THEN 0 
	--			ELSE ([io_stall_read_ms] / [num_of_reads])
	--		END,
	--	[Total Write Latency (MS)] =
	--		CASE WHEN [num_of_writes] = 0
	--			THEN 0 
	--			ELSE ([io_stall_write_ms] / [num_of_writes]) 
	--		END,
	--	[Average Latency (MS)] =
	--		CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
	--			THEN 0 
	--			ELSE ([io_stall] / ([num_of_reads] + [num_of_writes]))
	--		END,
	--	[Avg KB / Read] =
	--		CASE WHEN [num_of_reads] = 0
	--			THEN 0 
	--			ELSE (([num_of_bytes_read] / [num_of_reads]) /1024)
	--		END,
	--	[Avg KB / Write] =
	--		CASE WHEN [io_stall_write_ms] = 0
	--			THEN 0 
	--			ELSE (([num_of_bytes_written] / [num_of_writes]) /1024)
	--		END,
	--	[Avg KB / Transfer] =
	--		CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
	--			THEN 0 
	--			ELSE
	--				((([num_of_bytes_read] + [num_of_bytes_written]) / ([num_of_reads] + [num_of_writes])) / 1024)
	--		END,
	--	LEFT ([mf].[physical_name], 2) AS [Drive],
	--	DB_NAME ([vfs].[database_id]) AS [DB],
	--	[mf].[physical_name]
	--FROM
	--	sys.dm_io_virtual_file_stats (NULL,NULL) AS [vfs]
	--JOIN sys.master_files AS [mf]
	--	ON [vfs].[database_id] = [mf].[database_id]
	--	AND [vfs].[file_id] = [mf].[file_id]
	--ORDER BY [Total Write Latency (MS)] DESC'

	--execute (@sqlcmd)

    execute msdb.dbo.sp_send_dbmail
    @profile_name = @MailProfileName,
    @recipients = @EmailRecipients, 
    @subject = @EmailSubject,
    @body_format = TEXT,
    @body = @EmailBody,
    @execute_query_database = 'DBAdmin',
    @query = 'SELECT
    	cast(LTRIM(RTRIM(DB_NAME ([vfs].[database_id]))) AS VARCHAR(10)) AS [DB],
		[Total Read Latency (MS)] =
			CASE WHEN [num_of_reads] = 0
				THEN 0 
				ELSE CAST(([io_stall_read_ms] / [num_of_reads]) AS VARCHAR(10))
			END,
		[Total Write Latency (MS)] =
			CASE WHEN [num_of_writes] = 0
				THEN 0 
				ELSE CAST(([io_stall_write_ms] / [num_of_writes]) AS VARCHAR(10))
			END,
		[Average Latency (MS)] =
			CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
				THEN 0 
				ELSE CAST(([io_stall] / ([num_of_reads] + [num_of_writes])) AS VARCHAR(10))
			END,
		[Avg KB / Read] =
			CASE WHEN [num_of_reads] = 0
				THEN 0 
				ELSE CAST((([num_of_bytes_read] / [num_of_reads]) /1024) AS VARCHAR(10))
			END,
		[Avg KB / Write] =
			CASE WHEN [io_stall_write_ms] = 0
				THEN 0 
				ELSE CAST((([num_of_bytes_written] / [num_of_writes]) /1024) AS VARCHAR(10))
			END,
		[Avg KB / Transfer] =
			CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
				THEN 0 
				ELSE
					CAST(((([num_of_bytes_read] + [num_of_bytes_written]) / ([num_of_reads] + [num_of_writes])) / 1024) AS VARCHAR(10))
			END,
		cast(LTRIM(RTRIM(LEFT([mf].[physical_name], 2))) AS VARCHAR(2)) AS [Drive],
		cast(LTRIM(RTRIM([mf].[physical_name])) AS VARCHAR(10)) as [File Path]
	FROM
		sys.dm_io_virtual_file_stats (NULL,NULL) AS [vfs]
	JOIN sys.master_files AS [mf]
		ON [vfs].[database_id] = [mf].[database_id]
		AND [vfs].[file_id] = [mf].[file_id]
	ORDER BY [Total Write Latency (MS)] DESC'

end

