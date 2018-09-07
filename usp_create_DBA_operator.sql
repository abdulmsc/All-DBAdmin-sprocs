Use [DBAdmin]
GO
-- ##################################################################################
--
-- Author:			Haden Kingsland
--
-- Date:			8th July 2011
--
-- Description :	To create the DBA-Alerts operator
--
-- ###################################################################################

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
-- exec dbadmin.dba.usp_create_DBA_operator 'yourname@youremail.com'
--

create procedure [dba].[usp_create_DBA_operator]
@emailaddress varchar(200)

AS

BEGIN

/****** Object:  Operator [DBA-Alerts]    Script Date: 07/09/2018 12:05:22 ******/
EXEC msdb.dbo.sp_add_operator @name=N'DBA-Alerts', 
		@enabled=1, 
		@weekday_pager_start_time=90000, 
		@weekday_pager_end_time=180000, 
		@saturday_pager_start_time=90000, 
		@saturday_pager_end_time=180000, 
		@sunday_pager_start_time=90000, 
		@sunday_pager_end_time=180000, 
		@pager_days=0, 
		@email_address= @emailaddress, -- N'SQL-DBA-Alerts@cii.co.uk', 
		@category_name=N'[Uncategorized]'

END;


