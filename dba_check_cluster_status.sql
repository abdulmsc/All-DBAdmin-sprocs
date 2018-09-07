/****** Object:  StoredProcedure [dba].[usp_check_cluster_status]    Script Date: 07/09/2018 11:21:17 ******/
--#####################################################################
--
-- Author	: Haden Kingsland
-- Date		: 07/09/2018
-- Version	: 01:00
--
-- Desc		: To check for cluster failovers and email notification
--			  of such should it occur.
--
-- Modification History
-- ====================
--
--###################################################################
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
-- select * from dbadmin.dba.CLUSTERFAILOVERMONITOR;
-- 	exec [dba].[usp_check_cluster_status]
--
/********************************************************************************************************************/
-- Useage...
--
-- #######################################################################################################
--
-- STEP 1 -- You MUST create this table in each DBAdmin database on ALL clusters
--
-- #######################################################################################################

--use [dbadmin]

----truncate table dbadmin.dba.CLUSTERFAILOVERMONITOR 

--create table dbadmin.dba.CLUSTERFAILOVERMONITOR
--(
--ACTIVE_NODE varchar(30)
--)

-- #######################################################################################################
--
-- STEP 2 -- Insert the current cluster node into the table to seed the monitoring
--
-- #######################################################################################################
--
--insert into dbadmin.dba.CLUSTERFAILOVERMONITOR(ACTIVE_NODE)
--SELECT convert(varchar(30),SERVERPROPERTY('ComputerNamePhysicalNetBIOS'))

----insert into dbadmin.dba.CLUSTERFAILOVERMONITOR
----values
----(
----'myclusternode'
----)
--
-- select * from dbadmin.dba.CLUSTERFAILOVERMONITOR;
--
-- #######################################################################################################
--
-- STEP 3 -- then create the stored procedure within the DBADMIN database in each clustered instance
-- 
-- This can then be run from the SQL Agent every 1 minute to report on whether a cluster has failed over.
--
-- exec [dba].[usp_check_cluster_status] 'yourname@youremail.com'
--
-- #######################################################################################################

CREATE procedure [dba].[dba_check_cluster_status]
@mailrecipients varchar(200)
AS
BEGIN

Declare @var1 varchar(30),
		@var2 varchar(30),
		@message_body varchar(200),
		@subject_line varchar(200),
		@MailProfileName VARCHAR(50);

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'

	SELECT @var1= ACTIVE_NODE FROM dbadmin.dba.CLUSTERFAILOVERMONITOR

	CREATE TABLE PHYSICALHOSTNAME
	(
	VALUE VARCHAR(30),
	CURRENT_ACTIVE_NODE VARCHAR(30)
	)

	INSERT INTO PHYSICALHOSTNAME
	-- get currently active node from the registry
	exec master..xp_regread 'HKEY_LOCAL_Machine',
	'SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\',
	'ComputerName'


	SELECT @VAR2=CURRENT_ACTIVE_NODE FROM PHYSICALHOSTNAME

	set @message_body = 'Cluster failover has occured for instance ' + @@SERVERNAME + '. Below given are the previous and current active nodes.'
	set @subject_line = 'This is a Cluster FAILOVER notification email for... ' + @@SERVERNAME 

	if @VAR1<>@VAR2 -- check to see if the nodes are different, in which case a failover would have occured

	Begin

		EXEC msdb..sp_send_dbmail 
		@profile_name = @MailProfileName,
		@recipients=@mailrecipients,
		@subject=@subject_line,
		@body=@message_body,
		@QUERY='SET NOCOUNT ON;
		SELECT ACTIVE_NODE FROM dbadmin.dba.CLUSTERFAILOVERMONITOR;
		SELECT CURRENT_ACTIVE_NODE FROM PHYSICALHOSTNAME;
		SET NOCOUNT oFF'

		update dbadmin.dba.CLUSTERFAILOVERMONITOR set ACTIVE_NODE=@VAR2

	end

	DROP TABLE PHYSICALHOSTNAME;

end;


