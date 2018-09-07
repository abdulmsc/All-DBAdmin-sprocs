
--
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
--


SET ARITHABORT ON ;
SET QUOTED_IDENTIFIER ON ;

Exec DBAdmin.dba.usp_dba_indexDefrag
              @executeSQL           = 1 --0 = do it otherwise just analyse it
            , @printCommands        = 1
            , @debugMode            = 1
            , @printFragmentation   = 1
            , @forceRescan          = 1
            , @scanMode				= 'DETAILED'
            , @database				= NULL
            , @ignoredatabases		= 'ReportServer,ReportServerTempDB'
            , @maxDopRestriction    = 1
            , @minPageCount         = 500
            , @maxPageCount         = Null
            , @sortInTempDB			= 1 -- much more effecient to sort in TEMPDB if on faster disks
            , @minFragmentation     = 1
            , @rebuildThreshold     = 30
            , @defragDelay          = '00:00:05'
            , @defragOrderColumn    = 'page_count'
            , @defragSortOrder      = 'DESC'
            , @excludeMaxPartition  = 1
            , @timeLimit            = 240 --  4 hours.
            , @onlineRebuild        = 0  -- 1 = online rebuild; 0 = offline rebuild; only in Enterprise 
            , @comp					= 'N' -- N or P or R or C or CA specifies the level of data compression, if any, for the indexes 
										  -- during the rebuilds
			, @resume				= 0;  -- 1 for Yes | 0 for No