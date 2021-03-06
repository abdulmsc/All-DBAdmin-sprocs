USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_quick_glance_db_health_status]    Script Date: 07/09/2018 11:21:17 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dba].[usp_quick_glance_db_health_status]

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 31/07/2018
-- Version	: 01:00
--
-- Desc		: To show the status of all databases at a glance
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
-- 0 = online, 1 = restoring, 2 = recovering, 
-- 3 = recovery pending, 4 = suspect, 5 = emergency, 
-- 6 = offline
-- run as below...
--
-- 	exec DBADmin.dba.usp_quick_glance_db_health_status
--
/********************************************************************************************************************/

AS
     BEGIN
         SELECT name, 
                CASE state
					WHEN 0
					THEN 'Online and all good with me!'
                    WHEN 1
                    THEN 'I am restoring'
                    WHEN 2
                    THEN 'I am in recovery -- please investigate'
                    WHEN 3
                    THEN 'I am trying to recover -- please investigate further'
                    WHEN 4
                    THEN 'I am in trouble and suspect, please help me!'
                    WHEN 5
                    THEN 'I am having an emergency -- please investigate'
                    WHEN 6
                    THEN 'I am offline, should I be?'
                    ELSE state_desc
                END AS 'Current state'
         FROM sys.databases
         ORDER BY state_desc ASC;
     END;


