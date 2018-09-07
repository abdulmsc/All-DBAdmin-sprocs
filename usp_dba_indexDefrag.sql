USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_dba_indexDefrag]    Script Date: 07/09/2018 10:09:25 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--#######################################################################################################
--
-- Date			: 28/09/2011
-- DBA			: Haden Kingsland
-- Description	: To rebuild/re-organise all indexes dependant upon a fragmentation level of < or > a given
--				  percentage, passed in as a parameter at runtime.	
--
--	Name:       usp_dba_indexDefrag
-- 
-- Acknowledgements:
--------------------
--
-- This script has been taken from the original written by Michelle Ufford from http://sqlfool.com. I have
-- simply enhanced it to better suit my purposes. Please use this script at your own risk, as I take no
-- responsibility for it's use elsewhere in environments that are NOT under my control.
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
--  Modification History...
--
------------------------------------------------------------------------------
--    Date        Initials	Version Description
--    ----------------------------------------------------------------------------
--    2007-12-18  MFU         1.0     Initial Release
--    2008-10-17  MFU         1.1     Added @defragDelay, CIX_temp_indexDefragList
--    2008-11-17  MFU         1.2     Added page_count to log table
--                                    , added @printFragmentation option
--    2009-03-17  MFU         2.0     Provided support for centralized execution
--                                    , consolidated Enterprise & Standard versions
--                                    , added @debugMode, @maxDopRestriction
--                                    , modified LOB and partition logic  
--    2009-06-18  MFU         3.0     Fixed bug in LOB logic, added @scanMode option
--                                    , added support for stat rebuilds (@rebuildStats)
--                                    , support model and msdb defrag
--                                    , added columns to the dba_indexDefragLog table
--                                    , modified logging to show "in progress" defrags
--                                    , added defrag exclusion list (scheduling)
--    2009-08-28  MFU         3.1     Fixed read_only bug for database lists
--    2010-04-20  MFU         4.0     Added time limit option
--                                    , added static table with rescan logic
--                                    , added parameters for page count & SORT_IN_TEMPDB
--                                    , added try/catch logic and additional debug options
--                                    , added options for defrag prioritization
--                                    , fixed bug for indexes with allow_page_lock = off
--                                    , added option to exclude right-most partition
--                                    , removed @rebuildStats option
--                                    , refer to http://sqlfool.com for full release notes
                                    
--	28/09/2011	HJK			5.0		Enhanced SQL Server Version check, to see if it is 
--									Developer, Standard or Enterprise.
                                    
--    11/10/2011	HJK			5.1		Enhanced the script to allow indexes with LOB's to be
--									rebuilt offline rather than just re-organised. Also to 
--									allow indexes with multiple partitions to be re-organised
--									or rebuilt with partition=ALL.
									
--	28/02/2012	HJK			5.2		To allow one or more databases to be ignored from the index rebuild process
	
--									1) To return all databases, the @database parameter MUST BE NULL, 
--									and the @ignoredatabases MUST BE SPACES.
--									2) To ignore a given database(s), the @database parameter MUST BE NULL, and 
--									the @ignoredatabases MUST NOT BE SPACES. It must contain either a single 'dbname' .
--									or a list of names, thus... 'db1,db2,db3'. This will ignore these databases from the run.
--									3) To process only a single database, the @database parameter MUST NOT BE NULL and the 
--									@ignoredatabases MUST BE SPACES.
        
--									Example values for these parameters...
        
--									set @database = 'PMDB' 
--									or
--									set @database = NULL
									
--									set @ignoredatabases = ''
--									or
--									set @ignoredatabases = 'BESMgmt,CFS'								
									
--	01/02/2012	HJK			6.0		Enhanced error trapping, to catch certain errors and 
--									force a re-organisation over a rebuild when these
--									errors are trapped.
									
--	21/11/2012	HJK			6.1		Further enhanced to cater for new capabilities in
--									SQL Server 2012, as LOBs can be rebuilt online. The
--									caveat to this being that the "text, ntext and image" 
--									data types are not supported, as these are on the deprication
--									path for forthcoming releases.
									
--	18/12/2013	HJK			7.0		LOB check enhancements to correct issue with the @ver variable!
	
--	10/07/2014	HJK			7.1		Added the data compression rebuild option with the new SQL 2014 options!
--									DATA_COMPRESSION = { NONE | ROW | PAGE | COLUMNSTORE | COLUMNSTORE_ARCHIVE
	
--	25/01/2016	HJK			7.2		Added SQL 2014 enhancements to allow for partitions to be re-built 
--									online for Enterprise version.
--									http://blogs.msdn.com/b/sqlgardner/archive/2015/02/02/index-rebuild-enhancements-with-newer-sql-versions.aspx

--	03/01/2018				8.0		Updated to cater for SQL2016 and SQL2017 versions. 
--									I have decided to include the SQL 2017 resumable online index rebuild functionality BUT ONLY if a specific
--									database and table are passed in. Please be aware that pausing a resumable online index rebuild WILL kill the
--									SPID of the SQL Agent job that it is running under.
--									To find details of any rebuilds you may have paused use the following query...
--									SELECT total_execution_time, percent_complete, name,state_desc,last_pause_time,page_count
--									FROM sys.index_resumable_operations;
--									https://www.mssqltips.com/sqlservertip/4987/sql-server-2017-resumable-online-index-rebuilds/
--
/*********************************************************************************************************************************************************/
--	
-- input parameters...
--
ALTER PROCEDURE [dba].[usp_dba_indexDefrag]

    /* Declare Parameters */
      @minFragmentation     FLOAT           = 10.0  
        /* in percent, will not defrag if fragmentation less than specified */
    , @rebuildThreshold     FLOAT           --= 30.0  -- defaulted to 10%, but will be overwritten by parameter passed in
        /* in percent, greater than @rebuildThreshold will result in rebuild instead of reorg */
    , @executeSQL           BIT             = 1     /* 1 = execute; 0 = print command only */
    , @defragOrderColumn    NVARCHAR(20)    = 'fragmentation'
        /* Valid options are: range_scan_count, fragmentation, page_count */
    , @defragSortOrder      NVARCHAR(4)     = 'DESC'
        /* Valid options are: ASC, DESC */
    , @timeLimit            INT            -- = 240 /* defaulted to 4 hours */
        /* Optional time limitation; expressed in minutes */
    , @DATABASE             VARCHAR(128)    = Null
        /* Option to specify a database name; null will return all */
	, @ignoredatabases		varchar(400) = '' -- spaces or a list of databases to ignore from the rebuild process
    , @tableName            VARCHAR(4000)   = Null  -- databaseName.schema.tableName
        /* Option to specify a table name; null will return all */
    , @forceRescan          BIT             = 0
        /* Whether or not to force a rescan of indexes; 1 = force, 0 = use existing scan, if available */
    , @scanMode             VARCHAR(10)     -- = N'LIMITED'
        /* Options are LIMITED, SAMPLED, and DETAILED */
    , @minPageCount         INT            -- = 8 
        /*  MS recommends > 1 extent (8 pages) */
    , @maxPageCount         INT             = Null
        /* NULL = no limit */
    , @excludeMaxPartition  BIT             = 0
        /* 1 = exclude right-most populated partition; 0 = do not exclude; see notes for caveats */
    , @onlineRebuild        BIT             --= 0     
        /* 1 = online rebuild; 0 = offline rebuild; only in Enterprise */
    , @sortInTempDB         BIT             = 1
        /* 1 = perform sort operation in TempDB; 0 = perform sort operation in the index's database */
    , @maxDopRestriction    TINYINT         = Null
        /* Option to restrict the number of processors for the operation; only in Enterprise */
    , @printCommands        BIT             = 0     
        /* 1 = print commands; 0 = do not print commands */
    , @printFragmentation   BIT             = 0
        /* 1 = print fragmentation prior to defrag; 
           0 = do not print */
    , @defragDelay          CHAR(8)         = '00:00:05'
        /* time to wait between defrag commands */
    , @debugMode            BIT             = 0
        /* display some useful comments to help determine if/where issues occur */
    ,@comp				    VARCHAR(2)		= N
	/* 'R'	= ROW / 'P' = PAGE / 'C' = COLUMNSTORE / 'CA' = COLUMNSTORE_ARCHIVE / anything else = NONE! (also the default) */
	,@resume				BIT				= 0 
		/* 1 = Yes resumable index rebuild | 0 = No resumable index rebuild */
 
AS
/*##############################################################################################################
    Notes:
 
    CAUTION: TRANSACTION LOG SIZE SHOULD BE MONITORED CLOSELY WHEN DEFRAGMENTING.
             DO NOT RUN UNATTENDED ON LARGE DATABASES DURING BUSINESS HOURS.
 
      @minFragmentation     defaulted to 1%, will not defrag if fragmentation 
                            is less than that
 
      @rebuildThreshold     defaulted to 30% as recommended by Microsoft in BOL;
                            greater than 30% will result in rebuild instead
 
      @executeSQL           1 = execute the SQL generated by this proc; 
                            0 = print command only
 
      @defragOrderColumn    Defines how to prioritize the order of defrags.  Only
                            used if @executeSQL = 1.  
                            Valid options are: 
                            range_scan_count = count of range and table scans on the
                                               index; in general, this is what benefits 
                                               the most from defragmentation
                            fragmentation    = amount of fragmentation in the index;
                                               the higher the number, the worse it is
                            page_count       = number of pages in the index; affects
                                               how long it takes to defrag an index
 
      @defragSortOrder      The sort order of the ORDER BY clause.
                            Valid options are ASC (ascending) or DESC (descending).
 
      @timeLimit            Optional, limits how much time can be spent performing 
                            index defrags; expressed in minutes.
 
                            NOTE: The time limit is checked BEFORE an index defrag
                                  is begun, thus a long index defrag can exceed the
                                  time limitation.
 
      @database             Optional, specify specific database name to defrag;
                            If not specified, all non-system databases will
                            be defragged.
 
      @tableName            Specify if you only want to defrag indexes for a 
                            specific table, format = databaseName.schema.tableName;
                            if not specified, all tables will be defragged.
 
      @forceRescan          Whether or not to force a rescan of indexes.  If set
                            to 0, a rescan will not occur until all indexes have
                            been defragged.  This can span multiple executions.
                            1 = force a rescan
                            0 = use previous scan, if there are indexes left to defrag
 
      @scanMode             Specifies which scan mode to use to determine
                            fragmentation levels.  Options are:
                            LIMITED - scans the parent level; quickest mode,
                                      recommended for most cases.
                            SAMPLED - samples 1% of all data pages; if less than
                                      10k pages, performs a DETAILED scan.
                            DETAILED - scans all data pages.  Use great care with
                                       this mode, as it can cause performance issues.
 
      @minPageCount         Specifies how many pages must exist in an index in order 
                            to be considered for a defrag.  Defaulted to 8 pages, as 
                            Microsoft recommends only defragging indexes with more 
                            than 1 extent (8 pages).  
 
                            NOTE: The @minPageCount will restrict the indexes that
                            are stored in dba_indexDefragStatus table.
 
      @maxPageCount         Specifies the maximum number of pages that can exist in 
                            an index and still be considered for a defrag.  Useful
                            for scheduling small indexes during business hours and
                            large indexes for non-business hours.
 
                            NOTE: The @maxPageCount will restrict the indexes that
                            are defragged during the current operation; it will not
                            prevent indexes from being stored in the 
                            dba_indexDefragStatus table.  This way, a single scan
                            can support multiple page count thresholds.
 
      @excludeMaxPartition  If an index is partitioned, this option specifies whether
                            to exclude the right-most populated partition.  Typically,
                            this is the partition that is currently being written to in
                            a sliding-window scenario.  Enabling this feature may reduce
                            contention.  This may not be applicable in other types of 
                            partitioning scenarios.  Non-partitioned indexes are 
                            unaffected by this option.
                            1 = exclude right-most populated partition
                            0 = do not exclude
 
      @onlineRebuild        1 = online rebuild; 
                            0 = offline rebuild
 
      @sortInTempDB         Specifies whether to defrag the index in TEMPDB or in the
                            database the index belongs to.  Enabling this option may
                            result in faster defrags and prevent database file size 
                            inflation.
                            1 = perform sort operation in TempDB
                            0 = perform sort operation in the index's database 
 
      @maxDopRestriction    Option to specify a processor limit for index rebuilds
 
      @printCommands        1 = print commands to screen; 
                            0 = do not print commands
 
      @printFragmentation   1 = print fragmentation to screen;
                            0 = do not print fragmentation
 
      @defragDelay          Time to wait between defrag commands; gives the
                            server a little time to catch up 
 
      @debugMode            1 = display debug comments; helps with troubleshooting
                            0 = do not display debug comments
                            
      @comp					Level of compression to use during the index rebuilds
							'R'	= ROW / 'P' = PAGE / 'C' = COLUMNSTORE / 'CA' = COLUMNSTORE_ARCHIVE / anything else = NONE! (also the default)

	  @resume				1 = Yes
							0 = No
 
    Called by:  SQL Agent Job or DBA
    
--#######################################################################################################
SQL Agent job definition for running this procedure
--#######################################################################################################

Example SQL Agent Job Step 1
-----------------------------
 
SET ARITHABORT ON ;
SET QUOTED_IDENTIFIER ON ;

Exec DBAdmin.dba.usp_dba_indexDefrag
              @executeSQL           = 1 --0 = do it otherwise just analyse it
            , @printCommands        = 1
            , @debugMode            = 1
            , @printFragmentation   = 1
            , @forceRescan          = 1
            , @scanMode				= 'LIMITED'
            , @database				= NULL
            , @ignoredatabases		= 'ReportServer,ReportServerTempDB'
            , @maxDopRestriction    = 1
            , @minPageCount         = 1000
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


-- 16-12-2013
Example SQL Agent Job Step 1 with @ignoredatabases parameter specified!!!!
---------------------------------------------------------------------------
 -- Run this for the 2016 and 2017 compatible versions
 ---------------------------------------------------------

SET ARITHABORT ON ;
SET QUOTED_IDENTIFIER ON ;

Exec DBAdmin.dba.usp_dba_indexDefrag
              @executeSQL           = 1 --0 = do it otherwise just analyse it
            , @printCommands        = 1
            , @debugMode            = 1
            , @printFragmentation   = 1
            , @forceRescan          = 1
            , @scanMode				= 'LIMITED'
            , @database				= NULL
            , @ignoredatabases		= 'ReportServer,ReportServerTempDB'
            , @maxDopRestriction    = 1
            , @minPageCount         = 1000
            , @maxPageCount         = Null
            , @sortInTempDB			= 1 -- much more effecient to sort in TEMPDB if on faster disks
            , @minFragmentation     = 1
            , @rebuildThreshold     = 5.0
            , @defragDelay          = '00:00:05'
            , @defragOrderColumn    = 'page_count'
            , @defragSortOrder      = 'DESC'
            , @excludeMaxPartition  = 1
            , @timeLimit            = 240 --  4 hours.
            , @onlineRebuild        = 0;  -- 1 = online rebuild; 0 = offline rebuild; only in Enterprise 
            , @comp					= 'N' -- N or P or R or C or CA specifies the level of data compression, if any, for the indexes 
										  -- during the rebuilds
			, @resume				= 0   -- 1 for Yes | 0 for No


#########################################################################################################
This step is required to recalculate all optimizer statistics after the index rebuild job has completed.
---------------------------------------------------------------------------------------------------------

SQL Agent Job Step 2
--------------------
 
Also to be run in conjunction with a statistics update job step, in the context
of the "MASTER" database, thus...

DECLARE @SQL VARCHAR(1000), @DB SYSNAME, @database_name VARCHAR(30)= NULL;
SET @database_name = NULL; -- NULL -- or a valid database name to explicitly run on single database, in the format of 'Ola'

IF @database_name IS NULL
    BEGIN
        DECLARE database_cursor CURSOR FORWARD_ONLY STATIC
        FOR SELECT [name]
            FROM master.sys.databases
            WHERE database_id NOT IN(1, 2, 3, 4) -- ignore system databases as they are so small, not really worth doing
            AND ([name] NOT LIKE '%ReportS%' -- ignore reportserver databases
                 AND name NOT LIKE '%VANDBA%' -- ignore the DBA specific databases
                 AND name NOT LIKE '%distribution%') -- ignore the distribution database, as this is handled by itself
            AND is_read_only != 1 -- database is NOT READ ONLY
            AND state = 0 -- online databases only!
            ORDER BY [name];
        OPEN database_cursor;
        FETCH NEXT FROM database_cursor INTO @DB;
        WHILE @@FETCH_STATUS = 0
            BEGIN
                SELECT @SQL = 'USE ['+@DB+']'+CHAR(13)+'EXEC sp_updatestats'+CHAR(13);
                PRINT @SQL;
                EXEC (@sql);
                FETCH NEXT FROM database_cursor INTO @DB;
            END;
        CLOSE database_cursor;
        DEALLOCATE database_cursor;
    END;
    ELSE
IF @database_name IS NOT NULL
    BEGIN
        SET @SQL = 'USE ['+@database_name+']'+CHAR(13)+'EXEC sp_updatestats'+CHAR(13);
        PRINT @SQL;
        EXEC (@sql);
    END;


#######################################################################################################
---------------------------------------------------------------------------------
You will need the below tables to exist within the DBAdmin database in order
to record the status of the index process
---------------------------------------------------------------------------------

Create table [dbo].[dba_indexDefragExclusion]
###########################################
USE [DBAdmin]
GO

SET QUOTED_IDENTIFIER ON
GO
print 'creating CREATE TABLE [dbo].[dba_indexDefragExclusion]'
CREATE TABLE [dbo].[dba_indexDefragExclusion](
	[databaseID] [int] NOT NULL,
	[databaseName] [nvarchar](128) NOT NULL,
	[objectID] [int] NOT NULL,
	[objectName] [nvarchar](128) NOT NULL,
	[indexID] [int] NOT NULL,
	[indexName] [nvarchar](128) NOT NULL,
	[exclusionMask] [int] NOT NULL,
 CONSTRAINT [PK_indexDefragExclusion_v40] PRIMARY KEY CLUSTERED 
(
	[databaseID] ASC,
	[objectID] ASC,
	[indexID] ASC
)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [DATA]
) ON [DATA]
GO
---
USE [DBAdmin]
GO

Create table [dbo].[dba_indexDefragLog]
--###########################################
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO
print 'CREATE TABLE [dbo].[dba_indexDefragLog]'
CREATE TABLE [dbo].[dba_indexDefragLog](
	[indexDefrag_id] [int] IDENTITY(1,1) NOT NULL,
	[databaseID] [int] NOT NULL,
	[databaseName] [nvarchar](128) NOT NULL,
	[objectID] [int] NOT NULL,
	[objectName] [nvarchar](128) NOT NULL,
	[indexID] [int] NOT NULL,
	[indexName] [nvarchar](128) NOT NULL,
	[partitionNumber] [smallint] NOT NULL,
	[fragmentation] [float] NOT NULL,
	[page_count] [int] NOT NULL,
	[dateTimeStart] [datetime] NOT NULL,
	[dateTimeEnd] [datetime] NULL,
	[durationSeconds] [int] NULL,
	[sqlStatement] [varchar](4000) NULL,
	[errorMessage] [varchar](1000) NULL,
 CONSTRAINT [PK_indexDefragLog_v40] PRIMARY KEY CLUSTERED 
(
	[indexDefrag_id] ASC
)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [DATA]
) ON [DATA]

SET ANSI_PADDING OFF
GO

-----
USE [DBAdmin]
GO

Create table [dbo].[dba_indexDefragStatus]
###########################################
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO
print 'CREATE TABLE [dbo].[dba_indexDefragStatus]'
CREATE TABLE [dbo].[dba_indexDefragStatus](
	[databaseID] [int] NOT NULL,
	[databaseName] [nvarchar](128) NULL,
	[objectID] [int] NOT NULL,
	[indexID] [int] NOT NULL,
	[partitionNumber] [smallint] NOT NULL,
	[fragmentation] [float] NULL,
	[page_count] [int] NULL,
	[range_scan_count] [bigint] NULL,
	[schemaName] [nvarchar](128) NULL,
	[objectName] [nvarchar](128) NULL,
	[indexName] [nvarchar](128) NULL,
	[scanDate] [datetime] NULL,
	[defragDate] [datetime] NULL,
	[printStatus] [bit] NULL,
	[exclusionMask] [int] NULL,
 CONSTRAINT [PK_indexDefragStatus_v40] PRIMARY KEY CLUSTERED 
(
	[databaseID] ASC,
	[objectID] ASC,
	[indexID] ASC,
	[partitionNumber] ASC
)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [DATA]
) ON [DATA]
GO

ALTER TABLE [dbo].[dba_indexDefragStatus] ADD  CONSTRAINT [DF__dba_index__print__5BAD9CC8]  DEFAULT ((0)) FOR [printStatus]
ALTER TABLE [dbo].[dba_indexDefragStatus] ADD  CONSTRAINT [DF__dba_index__exclu__5CA1C101]  DEFAULT ((0)) FOR [exclusionMask]
GO

-----
USE [DBAdmin]
GO

Create table [dbo].[dba_indexDefragStatus_Archive]
#################################################

SET QUOTED_IDENTIFIER ON
GO
print 'CREATE TABLE [dbo].[dba_indexDefragStatus_Archive]'
CREATE TABLE [dbo].[dba_indexDefragStatus_Archive](
	[databaseID] [int] NOT NULL,
	[databaseName] [nvarchar](128) NULL,
	[objectID] [int] NOT NULL,
	[indexID] [int] NOT NULL,
	[partitionNumber] [smallint] NOT NULL,
	[fragmentation] [float] NULL,
	[page_count] [int] NULL,
	[range_scan_count] [bigint] NULL,
	[schemaName] [nvarchar](128) NULL,
	[objectName] [nvarchar](128) NULL,
	[indexName] [nvarchar](128) NULL,
	[scanDate] [datetime] NOT NULL,
	[defragDate] [datetime] NULL,
	[printStatus] [bit] NULL,
	[exclusionMask] [int] NULL,
 CONSTRAINT [PK_indexDefragStatus_Archive_v40] PRIMARY KEY CLUSTERED 
(
	[databaseID] ASC,
	[objectID] ASC,
	[indexID] ASC,
	[partitionNumber] ASC,
	[scanDate] ASC
)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [DATA]
) ON [DATA]

GO

###########################################################################################################*/
																
SET NOCOUNT ON;
SET XACT_Abort ON;
SET Quoted_Identifier ON;

--#########################################################################################
--
-- DEBUG START.......
--
-- Uncomment this section to test the procedure from within SSMS...
--
--#########################################################################################

    /* Declare Parameters */
--declare @minFragmentation     FLOAT           = 10.0  
--        /* in percent, will not defrag if fragmentation less than specified */
--    , @rebuildThreshold     FLOAT           = 30.0  -- defaulted to 10%, but will be overwritten by parameter passed in
--        /* in percent, greater than @rebuildThreshold will result in rebuild instead of reorg */
--    , @executeSQL           BIT             = 1     /* 1 = execute; 0 = print command only */
--    , @defragOrderColumn    NVARCHAR(20)    = 'range_scan_count'
--        /* Valid options are: range_scan_count, fragmentation, page_count */
--    , @defragSortOrder      NVARCHAR(4)     = 'DESC'
--        /* Valid options are: ASC, DESC */
--    , @timeLimit            INT             = 240 /* defaulted to 4 hours */
--        /* Optional time limitation; expressed in minutes */
--    , @DATABASE             VARCHAR(128)    = Null
--        /* Option to specify a database name; null will return all */
--	, @ignoredatabases		varchar(400) = '' -- spaces or a list of databases to ignore from the rebuild process
--    , @tableName            VARCHAR(4000)   = Null  -- databaseName.schema.tableName
--        /* Option to specify a table name; null will return all */
--    , @forceRescan          BIT             = 0
--        /* Whether or not to force a rescan of indexes; 1 = force, 0 = use existing scan, if available */
--    , @scanMode             VARCHAR(10)     = N'LIMITED'
--        /* Options are LIMITED, SAMPLED, and DETAILED */
--    , @minPageCount         INT             = 8 
--        /*  MS recommends > 1 extent (8 pages) */
--    , @maxPageCount         INT             = Null
--        /* NULL = no limit */
--    , @excludeMaxPartition  BIT             = 0
--        /* 1 = exclude right-most populated partition; 0 = do not exclude; see notes for caveats */
--    , @onlineRebuild        BIT             --= 0     
--        /* 1 = online rebuild; 0 = offline rebuild; only in Enterprise */
--    , @sortInTempDB         BIT             = 1
--        /* 1 = perform sort operation in TempDB; 0 = perform sort operation in the index's database */
--    , @maxDopRestriction    TINYINT         = Null
--        /* Option to restrict the number of processors for the operation; only in Enterprise */
--    , @printCommands        BIT             = 0     
--        /* 1 = print commands; 0 = do not print commands */
--    , @printFragmentation   BIT             = 0
--        /* 1 = print fragmentation prior to defrag; 
--           0 = do not print */
--    , @defragDelay          CHAR(8)         = '00:00:05'
--        /* time to wait between defrag commands */
--    , @debugMode            BIT             = 0
--        /* display some useful comments to help determine if/where issues occur */


--set @executeSQL           	= 1 --0 = do it otherwise just analyse it
--set @printCommands       	= 1
--set @debugMode            	= 1
--set @printFragmentation   	= 1
--set @forceRescan          	= 1
--set @scanMode				= 'LIMITED'
--set @maxDopRestriction    	= 1
--set @minPageCount         	= 1000
--set @database				=  NULL -- if a valid database name ('TK_Abergele'), will only process that databaseif @ignoredatabases is spaces
--set @ignoredatabases 		= 'ReportServer,ReportServerTempDB' -- if not spaces, will ignore the databases in this list if the @database parameter is NULL
--set @maxPageCount         	= Null
--set @sortInTempDB			= 1 -- much more effecient to sort in TEMPDB
--set @minFragmentation     	= 10
--set @rebuildThreshold     	= 30
--set @defragDelay          	= '00:00:05'
--set @defragOrderColumn    	= 'page_count'
--set @defragSortOrder      	= 'DESC'
--set @excludeMaxPartition  	= 1
--set @timeLimit            	= 360 --  6 hours.
--set @onlineRebuild        	= 0;    -- 1 = online rebuild; 0 = offline rebuild; only in Enterprise 

--#########################################################################################
--
-- DEBUG END .......
--
-- Uncomment this section to test the procedure from within SSMS...
--
--#########################################################################################

BEGIN
 
    BEGIN Try
 
        /* Just a little validation... */
        IF @minFragmentation IS Null 
            Or @minFragmentation Not Between 0.00 And 100.0
                SET @minFragmentation = 1.0;
 
        IF @rebuildThreshold IS Null
            Or @rebuildThreshold Not Between 0.00 And 100.0
                SET @rebuildThreshold = 30.0;
 
        IF @defragDelay Not Like '00:[0-5][0-9]:[0-5][0-9]'
            SET @defragDelay = '00:00:05';
 
        IF @defragOrderColumn IS Null
            Or @defragOrderColumn Not In ('range_scan_count', 'fragmentation', 'page_count')
                SET @defragOrderColumn = 'range_scan_count';
 
        IF @defragSortOrder IS Null
            Or @defragSortOrder Not In ('ASC', 'DESC')
                SET @defragSortOrder = 'DESC';
 
        IF @scanMode Not In ('LIMITED', 'SAMPLED', 'DETAILED')
            SET @scanMode = 'LIMITED';
 
        IF @debugMode IS Null
            SET @debugMode = 0;
 
        IF @forceRescan IS Null
            SET @forceRescan = 0;
 
        IF @sortInTempDB IS Null
            SET @sortInTempDB = 1;
 
 
        IF @debugMode = 1 RAISERROR('Undusting the cogs and starting up...', 0, 42) WITH NoWait;
 
        /* Declare our variables */
        DECLARE   @objectID                 INT
                , @databaseID               INT
                , @databaseName             NVARCHAR(128)
                , @indexID                  INT
                , @partitionCount           BIGINT
                , @schemaName               NVARCHAR(128)
                , @objectName               NVARCHAR(128)
                , @indexName                NVARCHAR(128)
                , @partitionNumber          SMALLINT
                , @fragmentation            FLOAT
                , @pageCount                INT
                , @sqlCommand               NVARCHAR(4000)
                , @rebuildCommand           NVARCHAR(200)
                , @dateTimeStart            DATETIME
                , @dateTimeEnd              DATETIME
                , @containsLOB              BIT
                , @editionCheck             BIT
                , @debugMessage             NVARCHAR(4000)
                , @updateSQL                NVARCHAR(4000)
                , @partitionSQL             NVARCHAR(4000)
                , @partitionSQL_Param       NVARCHAR(1000)
                , @LOB_SQL                  NVARCHAR(4000)
                , @LOB_SQL_Param            NVARCHAR(1000)
                , @indexDefrag_id           INT
                , @startDateTime            DATETIME
                , @endDateTime              DATETIME
                , @getIndexSQL              NVARCHAR(4000)
                , @getIndexSQL_Param        NVARCHAR(4000)
                , @allowPageLockSQL         NVARCHAR(4000)
                , @allowPageLockSQL_Param   NVARCHAR(4000)
                , @allowPageLocks           INT
                , @excludeMaxPartitionSQL   NVARCHAR(4000)
                , @stats					nvarchar(4000)
                , @level					varchar(2)
                , @compression				varchar(20)
                , @ERR_MESSAGE				varchar(300)
                , @ver						varchar(15)
			    , @ERR_NUM					int;
 
        -- Initialize our variables 
        SELECT @startDateTime = GETDATE()
            , @endDateTime = DATEADD(MINUTE, @timeLimit, GETDATE());
        
        -- get SQL Server release as this reflects what can and cannot be rebuilt online.
        
		SELECT @ver = CASE WHEN @@VERSION LIKE '%8.0%'	THEN 'SQL2000' 
						   WHEN @@VERSION LIKE '%9.0%'	THEN 'SQL2005'
						   WHEN @@VERSION LIKE '%10.0%' THEN 'SQL2008' 
						   WHEN @@VERSION LIKE '%10.5%' THEN 'SQL2008R2' 
						   WHEN @@VERSION LIKE '%11.0%' THEN 'SQL2012' 
						   WHEN @@VERSION LIKE '%12.0%' THEN 'SQL2014'
						   WHEN @@VERSION LIKE '%13.0%' THEN 'SQL2016'
						   WHEN @@VERSION LIKE '%14.0%' THEN 'SQL2017'
		END;

        -- Create our temporary tables
        CREATE TABLE #databaseList
        (
              databaseID        INT
            , databaseName      VARCHAR(128)
            , scanStatus        BIT
        );
 
        CREATE TABLE #processor 
        (
              [INDEX]           INT
            , Name              VARCHAR(128)
            , Internal_Value    INT
            , Character_Value   INT
        );
 
        CREATE TABLE #maxPartitionList
        (
              databaseID        INT
            , objectID          INT
            , indexID           INT
            , maxPartition      INT
        );
 
        IF @debugMode = 1 RAISERROR('Beginning validation...', 0, 42) WITH NoWait;
 
        /* Make sure we're not exceeding the number of processors we have available */
        INSERT INTO #processor
        EXECUTE XP_MSVER 'ProcessorCount';
 
        IF @maxDopRestriction IS Not Null And @maxDopRestriction > (SELECT Internal_Value FROM #processor)
            SELECT @maxDopRestriction = Internal_Value
            FROM #processor;
  
	-- 28/09/2011 -- Enhanced SQL Server Version check, to see if it is Developer, Standard or Enterprise.
 
 	SELECT @level =	CASE 
 		WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Enterprise%'	THEN 'EE' 
 		WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Developer%'		THEN 'DE' 
		WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Standard%'		THEN 'SE'
		WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Web%'			THEN 'WE' 
		WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Express%'		THEN 'EX'
		WHEN convert(varchar(30),serverproperty('Edition'))  LIKE '%Business%'		THEN 'BI' 
		ELSE 'UNKNOWN'
	END;
 --
 -- set the level of data compression based upon passed in values
 --
	SELECT @compression = CASE
		WHEN @comp = 'R'			THEN 'ROW'
		WHEN @comp = 'P'			THEN 'PAGE'
		WHEN @comp = 'C'			THEN 'COLUMNSTORE'
		WHEN @comp = 'CA'			THEN 'COLUMNSTORE_ARCHIVE'
		ELSE 'NONE'
	END;
	
--	SELECT @level =	CASE 
--		WHEN @@VERSION LIKE '%Enterprise%' THEN 'EE' 
--		WHEN @@VERSION LIKE '%Developer%' THEN 'DE' 
--	WHEN @@VERSION LIKE '%Standard%' THEN 'SE' 
--END;
			
	IF @level = 'EE' 
	or @level = 'DE'
		begin
			SET @editionCheck = 1 -- supports online rebuilds
		END
	ELSE
		BEGIN
			SET @editionCheck = 0; -- does not support online rebuilds
		END
 
        /* Output the parameters we're working with */
        IF @debugMode = 1 
        BEGIN
 
            SELECT @debugMessage = 'Your selected parameters are... 
            Defrag indexes with fragmentation greater than ' + CAST(@minFragmentation AS VARCHAR(10)) + ';
            Rebuild indexes with fragmentation greater than ' + CAST(@rebuildThreshold AS VARCHAR(10)) + ';
            You' + CASE WHEN @executeSQL = 1 THEN ' DO' ELSE ' DO NOT' END + ' want the commands to be executed automatically; 
            You want to defrag indexes in ' + @defragSortOrder + ' order of the ' + UPPER(@defragOrderColumn) + ' value;
            You have' + CASE WHEN @timeLimit IS Null THEN ' not specified a time limit;' ELSE ' specified a time limit of ' 
                + CAST(@timeLimit AS VARCHAR(10)) END + ' minutes;
            ' + CASE WHEN @DATABASE IS Null THEN 'ALL databases' ELSE 'The ' + @DATABASE + ' database' END + ' will be defragged;
            ' + CASE WHEN @tableName IS Null THEN 'ALL tables' ELSE 'The ' + @tableName + ' table' END + ' will be defragged;
            We' + CASE WHEN Exists(SELECT TOP 1 * FROM dbadmin.dbo.dba_indexDefragStatus WHERE defragDate IS Null)
                And @forceRescan <> 1 THEN ' WILL NOT' ELSE ' WILL' END + ' be rescanning indexes;
            The scan will be performed in ' + @scanMode + ' mode;
            You want to limit defrags to indexes with' + CASE WHEN @maxPageCount IS Null THEN ' more than ' 
                + CAST(@minPageCount AS VARCHAR(10)) ELSE
                ' between ' + CAST(@minPageCount AS VARCHAR(10))
                + ' and ' + CAST(@maxPageCount AS VARCHAR(10)) END + ' pages;
            Indexes will be defragged' + CASE WHEN @editionCheck = 0 Or @onlineRebuild = 0 THEN ' OFFLINE;' ELSE ' ONLINE;' END + '
            Indexes will be sorted in' + CASE WHEN @sortInTempDB = 0 THEN ' the DATABASE' ELSE ' TEMPDB;' END + '
            Defrag operations will utilize ' + CASE WHEN @editionCheck = 0 Or @maxDopRestriction IS Null 
                THEN 'system defaults for processors;' 
                ELSE CAST(@maxDopRestriction AS VARCHAR(2)) + ' processors;' END + '
            You' + CASE WHEN @printCommands = 1 THEN ' DO' ELSE ' DO NOT' END + ' want to print the ALTER INDEX commands; 
            You' + CASE WHEN @printFragmentation = 1 THEN ' DO' ELSE ' DO NOT' END + ' want to output fragmentation levels; 
            You want to wait ' + @defragDelay + ' (hh:mm:ss) between defragging indexes;
            You want to run in' + CASE WHEN @debugMode = 1 THEN ' DEBUG' ELSE ' SILENT' END + ' mode.
            Your data compression mode is...' + @compression +
            'You are choosing to ignore the following databases... ' + ISNULL(@ignoredatabases,'NONE')
            
            RAISERROR(@debugMessage, 0, 42) WITH NoWait;
 
        END;
 
        IF @debugMode = 1 RAISERROR('Grabbing a list of our databases...', 0, 42) WITH NoWait;
 
 		-- Initialize the @ignoredatabases parameter if passed in with a value to ensure a comma at the start and end.
		-- This is required to allow the CHARINDEX function to work correctly in the statement that follows.
 
		IF @ignoredatabases <> ''
		BEGIN
			SET @ignoredatabases = ',' + @ignoredatabases + ','
		END;
 
 -- 16-12-2013
 -- DEBUG for @ignoredatabases
 --
 --declare @database varchar(50)
 --declare @ignoredatabases varchar(400)
 
 --set @ignoredatabases = 'LOREVDA'
 --set @database = NULL -- 'ReportServer'
 
 --		IF @ignoredatabases <> ''
	--	BEGIN
	--		SET @ignoredatabases = ',' + @ignoredatabases + ','
	--	END;
 
 --        SELECT database_id
 --           , name
 --           , 0 -- not scanned yet for fragmentation
 --       FROM sys.databases
 --       WHERE (name = IsNull(@DATABASE, name)
 --           And [name] Not In ('master', 'tempdb', 'msdb','model')-- exclude system databases
 --           And [STATE] = 0 -- state must be ONLINE
 --           And is_read_only = 0  -- cannot be read_only
	--		and not (CHARINDEX(',' + name + ',' , @ignoredatabases) > 0))
 
 
        /* Retrieve the list of databases to investigate. If @DATABASE is NULL, all databases will be returned */
        INSERT INTO #databaseList
        SELECT database_id
            , name
            , 0 -- not scanned yet for fragmentation
        FROM sys.databases
        WHERE (name = IsNull(@DATABASE, name)
            And [name] Not In ('master', 'tempdb', 'msdb','model')-- exclude system databases
            And [STATE] = 0 -- state must be ONLINE
            And is_read_only = 0  -- cannot be read_only
            -- 16-12-2013
            -- check whether databases are in the list of those passed in to allow 
            -- for databases to be ignored or a single database to be processed
            and not (CHARINDEX(',' + name + ',' , @ignoredatabases) > 0)) 
 
        /* Check to see if we have indexes in need of defrag; otherwise, re-scan the database(s) */
        IF Not Exists(SELECT TOP 1 * FROM dbadmin.dbo.dba_indexDefragStatus WHERE defragDate IS Null)
            Or @forceRescan = 1
        BEGIN
 
            /* Truncate our list of indexes to prepare for a new scan */
            TRUNCATE TABLE dbadmin.dbo.dba_indexDefragStatus;
 
            IF @debugMode = 1 RAISERROR('Looping through our list of databases and checking for fragmentation...', 0, 42) WITH NoWait;
 
            /* Loop through our list of databases */
            WHILE (SELECT COUNT(*) FROM #databaseList WHERE scanStatus = 0) > 0
            BEGIN
 
                SELECT TOP 1 @databaseID = databaseID
                FROM #databaseList
                WHERE scanStatus = 0;
 
                SELECT @debugMessage = '  working on [' + DB_NAME(@databaseID) + ']...';
 
                IF @debugMode = 1
                    RAISERROR(@debugMessage, 0, 42) WITH NoWait;
 
               /* Determine which indexes to defrag using our user-defined parameters */
                INSERT INTO [DBAdmin].[dbo].[dba_indexDefragStatus]
                (
                      databaseID
                    , databaseName
                    , objectID
                    , indexID
                    , partitionNumber
                    , fragmentation
                    , page_count
                    , range_scan_count
                    , scanDate
                )
                SELECT
                      ps.database_id AS 'databaseID'
                    , QUOTENAME(DB_NAME(ps.database_id)) AS 'databaseName'
                    , ps.OBJECT_ID AS 'objectID'
                    , ps.index_id AS 'indexID'
                    , ps.partition_number AS 'partitionNumber'
                    , SUM(ps.avg_fragmentation_in_percent) AS 'fragmentation'
                    , SUM(ps.page_count) AS 'page_count'
                    , os.range_scan_count
                    , GETDATE() AS 'scanDate'
                FROM sys.dm_db_index_physical_stats(@databaseID, OBJECT_ID(@tableName), Null , Null, @scanMode) AS ps
                Join sys.dm_db_index_operational_stats(@databaseID, OBJECT_ID(@tableName), Null , Null) AS os
                    ON ps.database_id = os.database_id
                    And ps.OBJECT_ID = os.OBJECT_ID
                    and ps.index_id = os.index_id
                    And ps.partition_number = os.partition_number
                WHERE avg_fragmentation_in_percent >= @minFragmentation 
                    And ps.index_id > 0 -- ignore heaps
                    And ps.page_count > @minPageCount 
                    And ps.index_level = 0 -- leaf-level nodes only, supports @scanMode
                GROUP BY ps.database_id 
                    , QUOTENAME(DB_NAME(ps.database_id)) 
                    , ps.OBJECT_ID 
                    , ps.index_id 
                    , ps.partition_number 
                    , os.range_scan_count
                OPTION (MaxDop 2);
 
                /* Do we want to exclude right-most populated partition of our partitioned indexes? */
                IF @excludeMaxPartition = 1
                BEGIN
 
                    SET @excludeMaxPartitionSQL = '
                        Select ' + CAST(@databaseID AS VARCHAR(10)) + ' As [databaseID]
                            , [object_id]
                            , index_id
                            , Max(partition_number) As [maxPartition]
                        From [' + DB_NAME(@databaseID) + '].sys.partitions
                        Where partition_number > 1
                            And [rows] > 0
                        Group By object_id
                            , index_id;';
 
                    INSERT INTO #maxPartitionList
                    EXECUTE SP_EXECUTESQL @excludeMaxPartitionSQL;
 
                END;
 
                /* Keep track of which databases have already been scanned */
                UPDATE #databaseList
                SET scanStatus = 1
                WHERE databaseID = @databaseID;
 
            END
 
            /* We don't want to defrag the right-most populated partition, so
               delete any records for partitioned indexes where partition = Max(partition) */
            IF @excludeMaxPartition = 1
            BEGIN
 
                DELETE ids
                FROM dbadmin.dbo.dba_indexDefragStatus AS ids
                Join #maxPartitionList AS mpl
                    ON ids.databaseID = mpl.databaseID
                    And ids.objectID = mpl.objectID
                    And ids.indexID = mpl.indexID
                    And ids.partitionNumber = mpl.maxPartition;
 
            END;
 
            /* Update our exclusion mask for any index that has a restriction on the days it can be defragged */
            UPDATE ids
            SET ids.exclusionMask = ide.exclusionMask
            FROM dbadmin.dbo.dba_indexDefragStatus AS ids
            Join dbadmin.dbo.dba_indexDefragExclusion AS ide
                ON ids.databaseID = ide.databaseID
                And ids.objectID = ide.objectID
                And ids.indexID = ide.indexID;
 
        END
 
        SELECT @debugMessage = 'Looping through our list... there are ' + CAST(COUNT(*) AS VARCHAR(10)) + ' indexes to defrag!'
        FROM dbadmin.dbo.dba_indexDefragStatus
        WHERE defragDate IS Null
            And page_count Between @minPageCount And IsNull(@maxPageCount, page_count);
 
        IF @debugMode = 1 RAISERROR(@debugMessage, 0, 42) WITH NoWait;
 
        /* Begin our loop for defragging */
        WHILE (SELECT COUNT(*) 
               FROM dbadmin.dbo.dba_indexDefragStatus 
               WHERE (
                           (@executeSQL = 1 And defragDate IS Null) 
                        Or (@executeSQL = 0 And defragDate IS Null And printStatus = 0)
                     )
                And exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0
                And page_count Between @minPageCount And IsNull(@maxPageCount, page_count)) > 0
        BEGIN
 
            /* Check to see if we need to exit our loop because of our time limit */        
            IF IsNull(@endDateTime, GETDATE()) < GETDATE()
            BEGIN
                RAISERROR('Our time limit has been exceeded!', 11, 42) WITH NoWait;
            END;
 
            IF @debugMode = 1 RAISERROR('  Picking an index to beat into shape...', 0, 42) WITH NoWait;
 
            /* Grab the index with the highest priority, based on the values submitted; 
               Look at the exclusion mask to ensure it can be defragged today */
            SET @getIndexSQL = N'
            Select Top 1 
                  @objectID_Out         = objectID
                , @indexID_Out          = indexID
                , @databaseID_Out       = databaseID
                , @databaseName_Out     = databaseName
                , @fragmentation_Out    = fragmentation
                , @partitionNumber_Out  = partitionNumber
                , @pageCount_Out        = page_count
            From dbadmin.dbo.dba_indexDefragStatus
            Where defragDate Is Null ' 
                + CASE WHEN @executeSQL = 0 THEN 'And printStatus = 0' ELSE '' END + '
                And exclusionMask & Power(2, DatePart(weekday, GetDate())-1) = 0
                And page_count Between @p_minPageCount and IsNull(@p_maxPageCount, page_count)
            Order By + ' + @defragOrderColumn + ' ' + @defragSortOrder;
 
            SET @getIndexSQL_Param = N'@objectID_Out        int OutPut
                                     , @indexID_Out         int OutPut
                                     , @databaseID_Out      int OutPut
                                     , @databaseName_Out    nvarchar(128) OutPut
                                     , @fragmentation_Out   int OutPut
                                     , @partitionNumber_Out int OutPut
                                     , @pageCount_Out       int OutPut
                                     , @p_minPageCount      int
                                     , @p_maxPageCount      int';
 
            EXECUTE SP_EXECUTESQL @getIndexSQL
                , @getIndexSQL_Param
                , @p_minPageCount       = @minPageCount
                , @p_maxPageCount       = @maxPageCount
                , @objectID_Out         = @objectID OUTPUT
                , @indexID_Out          = @indexID OUTPUT
                , @databaseID_Out       = @databaseID OUTPUT
                , @databaseName_Out     = @databaseName OUTPUT
                , @fragmentation_Out    = @fragmentation OUTPUT
                , @partitionNumber_Out  = @partitionNumber OUTPUT
                , @pageCount_Out        = @pageCount OUTPUT;
 
            IF @debugMode = 1 RAISERROR('  Looking up the specifics for our index...', 0, 42) WITH NoWait;
 
            /* Look up index information */
            SELECT @updateSQL = N'Update ids
                Set schemaName = QuoteName(s.name)
                    , objectName = QuoteName(o.name)
                    , indexName = QuoteName(i.name)
                From dbadmin.dbo.dba_indexDefragStatus As ids
                Inner Join ' + @databaseName + '.sys.objects As o
                    On ids.objectID = o.object_id
                Inner Join ' + @databaseName + '.sys.indexes As i
                    On o.object_id = i.object_id
                    And ids.indexID = i.index_id
                Inner Join ' + @databaseName + '.sys.schemas As s
                    On o.schema_id = s.schema_id
                Where o.object_id = ' + CAST(@objectID AS VARCHAR(10)) + '
                    And i.index_id = ' + CAST(@indexID AS VARCHAR(10)) + '
                    And i.type > 0
                    And ids.databaseID = ' + CAST(@databaseID AS VARCHAR(10));
 
            EXECUTE SP_EXECUTESQL @updateSQL;
 
            /* Grab our object names */
            SELECT @objectName  = objectName
                , @schemaName   = schemaName
                , @indexName    = indexName
            FROM dbadmin.dbo.dba_indexDefragStatus
            WHERE objectID = @objectID
                And indexID = @indexID
                And databaseID = @databaseID;
 
            IF @debugMode = 1 RAISERROR('  Grabbing the partition count...', 0, 42) WITH NoWait;
 
            /* Determine if the index is partitioned */
            SELECT @partitionSQL = 'Select @partitionCount_OUT = Count(*)
                                        From ' + @databaseName + '.sys.partitions
                                        Where object_id = ' + CAST(@objectID AS VARCHAR(10)) + '
                                            And index_id = ' + CAST(@indexID AS VARCHAR(10)) + ';'
                , @partitionSQL_Param = '@partitionCount_OUT int OutPut';
 
            EXECUTE SP_EXECUTESQL @partitionSQL, @partitionSQL_Param, @partitionCount_OUT = @partitionCount OUTPUT;
 
            IF @debugMode = 1 RAISERROR('  Seeing if there are any LOBs to be handled...', 0, 42) WITH NoWait;
 
-- Version 6.1 enhancements
--
--#####################################################################################################
--
-- DEBUG Section.......................
--
--#####################################################################################################

-- Manipulate LOB's
 
--declare @ver varchar(10)
--select @ver = 'SQL 2012'
---- show LOB objects in a database
--Select Count(*), o.name, c.name, c.user_type_id, t.name, o.object_id, c.object_id
--From sys.columns c
--join sys.objects o
--on o.object_id = c.object_id 
--join sys.types t
--on t.user_type_id = c.user_type_id
---- Mark as contains LOBS if it is any lob type and any version below SQL 2012, as you cannot rebuild
---- any LOBS online for these versions
--Where ((c.system_type_id In (34, 35, 99) or c.max_length = -1) and @ver != 'SQL 2012')
---- or if image, text or ntext and SQL 2012, as you cannot rebuild these online in 2012, but can 
---- now rebuild varbinary(max), varchar(max), nvarchar(max), xml types online.
--or (c.system_type_id In (34, 35, 99) and @ver = 'SQL 2012')
--group by o.name,c.name,c.user_type_id, t.name, o.object_id, c.object_id
 
--declare @LOB_SQL NVARCHAR(4000)
--declare @LOB_SQL_Param nvarchar(1000)
--declare @ver varchar(10)

----declare @databasename varchar(20)
----, @partitionSQL             NVARCHAR(4000)
----, @partitionSQL_Param       NVARCHAR(1000)
----, @containsLOB              BIT

--set @ver = 'SQL 2008'
--set @ver = '[' + @ver +']'

--print @ver
--Select object_name(object_id), st.name, *
--From DBAdmin.sys.columns c With (NOLOCK) 
--inner join dbadmin.sys.types st
--on st.system_type_id = c.system_type_id
----Where [object_id] = 21575115
--where ((c.system_type_id In (34, 35, 99) or c.max_length = -1)
--and @ver != 'SQL 2012')
--or (c.system_type_id In (34, 35, 99) and @ver ='SQL 2012');

--set @databaseName = 'SPHCWebCatalogue'

 
--            /* Determine if the table contains LOBs */
--            SELECT @LOB_SQL = ' Select @containsLOB_OUT = Count(*)
--                                From ' + @databaseName + '.sys.columns c With (NOLOCK) 
--                                Where [object_id] = ' + CAST('21575115' AS VARCHAR(10)) + '
--                                and ((system_type_id In (34, 35, 99) or max_length = -1)
--                                and ' + @ver + ' != ''SQL 2012'')
--                                or (c.system_type_id In (34, 35, 99) and ' + @ver + ' =''SQL 2012'')
--                                ;'
--                                /*  system_type_id --> 34 = image, 35 = text, 99 = ntext
--                                    max_length = -1 --> varbinary(max), varchar(max), nvarchar(max), xml */
             
--   --         select @LOB_SQL_Param = '@containsLOB_OUT int OutPut';
--			--EXECUTE SP_EXECUTESQL @LOB_SQL, @LOB_SQL_Param, @containsLOB_OUT = @containsLOB OUTPUT;
			
----print @containsLOB
--print @LOB_SQL
 
-- select count(*) from information_schema.columns
--    where DATA_TYPE in('text','ntext','xml','image','varbinary')
--    or  (DATA_TYPE in('varchar','nvarchar')
--    and CHARACTER_MAXIMUM_LENGTH = -1)
--    order by DATA_TYPE
 
---- declare @from varchar(20)
-- declare @database varchar(30)
-- declare @ver varchar(15)
--set @ver = 'SQL2008'
----set @database = 'SPHCWebCatalogue'
----set @from = @database + '..sys.columns' 
--set @ver = '' + @ver + ''

--print @ver

--Select * -- count(*)
--From sys.columns WITH (NOLOCK)
--Where [object_id] = CAST(object_id AS VARCHAR(10))
--and ((system_type_id In (34, 35, 99) 
--or max_length = -1)and @ver != 'SQL 2012') -- mark as containing LOB's if contain LOB data type and not 2012 as no LOB's can be built online!
--or (system_type_id In (34, 35, 99) and @ver ='SQL 2012') -- or mark as containing LOB's if an image, text or ntext data type and using SQL 2012

 
--Select *
--From  sys.indexes
--Where object_id = CAST(object_ID AS VARCHAR(10))
--    And index_id = CAST(index_id AS VARCHAR(10))
--    And Allow_Page_Locks = 0;
    
-- Select  Count(*)
--From NetPerfMon.sys.columns c With (NoLock) 
--Where [object_id] = 21575115
--and ((system_type_id In (34, 35, 99) or max_length = -1)
--and @ver  != 'SQL 2012')
--or (c.system_type_id In (34, 35, 99) and @ver ='SQL 2012')
--;
--#####################################################################################################
--
-- Check to see if the object in question contains LOBs... This has been enhanced for SQL Server 2012.
--
--#####################################################################################################
--
-- V7.0 -- 18th December 2013... LOB check enhancements -- HJK
--
-- Mark as contains LOBS if it is any lob type and any version below SQL 2012, as you cannot rebuild
-- any LOBS online for these versions
-- or if image, text or ntext and SQL 2012, as you cannot rebuild these online in 2012, but can 
-- now rebuild varbinary(max), varchar(max), nvarchar(max), xml types online.
--
-- system_type_id  --> 34 = image, 35 = text, 99 = ntext
-- max_length = -1 --> varbinary(max), varchar(max), nvarchar(max), xml 
--
-- ######################################################################################################################
-- Pre 2012 version checks for rebuilding indexes that contain LOB's
-- ######################################################################################################################
--
            --IF @debugMode = 1 RAISERROR('  Seeing if there are any LOBs to be handled...', 0, 42) WITH NoWait;
 
            /* Determine if the table contains LOBs */
            --SELECT @LOB_SQL = ' Select @containsLOB_OUT = Count(*)
            --                    From ' + @databaseName + '.sys.columns With (NoLock) 
            --                    Where [object_id] = ' + CAST(@objectID AS VARCHAR(10)) + '
            --                       And (system_type_id In (34, 35, 99)
            --                                Or max_length = -1);'
            --                    /*  system_type_id --> 34 = image, 35 = text, 99 = ntext
            --                        max_length = -1 --> varbinary(max), varchar(max), nvarchar(max), xml */
            --        , @LOB_SQL_Param = '@containsLOB_OUT int OutPut';
 
            --EXECUTE SP_EXECUTESQL @LOB_SQL, @LOB_SQL_Param, @containsLOB_OUT = @containsLOB OUTPUT;
            
-- ######################################################################################################################

			--PRINT @VER
			
			--PRINT 'Hello, I am here at the LOB bit....'
			
            /* Determine if the table contains LOBs */
            SELECT @LOB_SQL = N' Select @containsLOB_OUT = Count(*) From ' 
								+ @databaseName  
                                + '.sys.columns With (NoLock) Where [object_id] = ' 
                                + CAST(@objectID AS VARCHAR(10)) 
-- mark as containing LOB's if the column has a LOB data type and the database is NOT 2012 as no LOB's can be built online!
-- or mark as containing LOB's if an image, text or ntext data type and using SQL 2012 as these cannot be built online under 2012 :)
                                --+ ' and ((system_type_id In (34, 35, 99) or max_length = -1) and ' 
                                --+ '''' + @ver + '''' + ' != ''SQL2012'') or (system_type_id in (34, 35, 99) and ' 
                                --+ '''' + @ver + '''' + ' = ''SQL2012'');',
                                --@LOB_SQL_Param = N'@containsLOB_OUT int OutPut';      
								-- section updated on 03/01/2018 to allow for newer versions of SQL Server
								 + ' and ((system_type_id In (34, 35, 99) or max_length = -1) and ' 
                                + '''' + @ver + '''' + ' not in (''SQL2012'',''SQL2014'',''SQL2016'',''SQL2017'')) 
								or (system_type_id in (34, 35, 99) and ' 
                                + '''' + @ver + '''' + ' in (''SQL2012'',''SQL2014'',''SQL2016'',''SQL2017''));',
                                @LOB_SQL_Param = N'@containsLOB_OUT int OutPut';                      
                                
  
            EXECUTE SP_EXECUTESQL @LOB_SQL, @LOB_SQL_Param, @containsLOB_OUT = @containsLOB OUTPUT;
 
            IF @debugMode = 1 RAISERROR('  Checking for indexes that do not allow page locks...', 0, 42) WITH NoWait;
 
            /* Determine if page locks are allowed; for those indexes, we need to always rebuild */
            SELECT @allowPageLockSQL = N'Select @allowPageLocks_OUT = Count(*)
                                        From ' + @databaseName + '.sys.indexes
                                        Where object_id = ' + CAST(@objectID AS VARCHAR(10)) + '
                                            And index_id = ' + CAST(@indexID AS VARCHAR(10)) + '
                                            And Allow_Page_Locks = 0;',
                                            @allowPageLockSQL_Param = N'@allowPageLocks_OUT int OutPut';
 
            EXECUTE SP_EXECUTESQL @allowPageLockSQL, @allowPageLockSQL_Param, @allowPageLocks_OUT = @allowPageLocks OUTPUT;
 
            IF @debugMode = 1 RAISERROR('  Building our SQL statements...', 0, 42) WITH NoWait;
 
-- Version 5.1 enhancements
---------------------------------------------------------------------------------------------------------------------------------
-- If there's NOT a lot of fragmentation we should reorganize
-- This is regardless of SQL Version. This is also regardless of whether there are LOB's or not,
-- as a re-organise will take care of LOB objects.
---------------------------------------------------------------------------------------------------------------------------------

            IF (@fragmentation < @rebuildThreshold)
            --or (@containsLOB >= 1 and @editionCheck = 0) -- contains LOBS and in Standard Edition
            --or @partitionCount > 1) -- more than 1 partition regardless of version
                --And @allowPageLocks = 0
            BEGIN
 
                SET @sqlCommand = N'Alter Index ' + @indexName  + N' On ' + @databaseName + N'.' 
                                    + @schemaName  + N'.' + @objectName  + N' ReOrganize';
 
                -- If the index is partitioned, we should 
                IF @partitionCount > 1
					BEGIN
					
						IF @ver not in ('SQL2014','SQL2016','SQL2017') -- != 'SQL 2014'
							BEGIN
								set @sqlCommand = @sqlCommand + N' PARTITION = ALL'
							END
						ELSE
							BEGIN
								SET @sqlCommand = @sqlCommand + N' Partition = ' + RTRIM(LTRIM(CAST(@partitionNumber AS NVARCHAR(5))));
							END

					END
 
            END
  
  -- REBUILD section
  ---------------------------------------------------------------------------------------------------------------------------------
  -- If the index is heavily fragmented or if the index does not allow page locks, then rebuild it...
  ---------------------------------------------------------------------------------------------------------------------------------

            ELSE IF (@fragmentation >= @rebuildThreshold 
            or @allowPageLocks <> 0)
            --and IsNull(@containsLOB, 0) != 1 
            --and @partitionCount <= 1
            
            BEGIN
            
   ---------------------------------------------------------------------------------------------------------------------------------
  -- If you are running EE, and there are no LOB's and there is less than 1 partition, then you can rebuild online...
  -- OR... if you are running SQL 2014 and above, and the partition count > 1 and the version is EE you can also rebuild online
  ---------------------------------------------------------------------------------------------------------------------------------
                IF ((@onlineRebuild = 1  -- user set option to rebuild online
                and @editionCheck = 1) -- can only happen if editioncheck = 1 as this is Enterprise Edition
				--and IsNull(@containsLOB, 0) != 1 -- and there can be no LOB's to rebuild online
				and IsNull(@containsLOB, 0) < 1 -- and there can be no LOB's to rebuild online
				and @partitionCount <= 1
				)
				-- section updated on 03/01/2018 to allow for newer versions of SQL Server
				or (
				@partitionCount > 1			-- you can rebuild individual partitions online with SQL 2014 and above Enterprise Edition
				and @ver in ('SQL2014','SQL2016','SQL2017')
				and @editionCheck = 1		-- can only happen if editioncheck = 1 as this is Enterprise Edition
				and @onlineRebuild = 1		-- user set option to rebuild online
				)
						SET @rebuildCommand = N' Rebuild With (Online = On';
  ---------------------------------------------------------------------------------------------------------------------------------
  -- ...otherwise, if there are LOB's regardless of SQL version, or if there is more than 1 partition (you cannot rebuild multiple
  -- partitions online), or if we are running Standard Edition, then you can only rebuild offline...
  ---------------------------------------------------------------------------------------------------------------------------------
  -- Updated for SQL Server 2014 as you can now rebuild paritions online in this version
  ---------------------------------------------------------------------------------------------------------------------------------
                ELSE
				-- section updated on 03/01/2018 to allow for newer versions of SQL Server
					IF (@partitionCount > 1
					and @ver in ('SQL2014','SQL2016','SQL2017') -- can rebuild partitions online in versions above SQL Server 2014 CTP1
					and @onlineRebuild = 1			-- user set option to rebuild online must be set!
					and @editionCheck = 1)			-- Enterprise Edition only!
					and IsNull(@containsLOB, 0) < 1 -- no lobs -- worked out earlier in the procedure to allow 2012/2014 options
						BEGIN
							SET @rebuildCommand = N' Rebuild PARTITION = ALL With (Online = On';
						END
						ELSE IF @partitionCount > 1 -- regardless of SQL version (STD or EE)
							 and @ver not in ('SQL2014','SQL2016','SQL2017') --!= '2014' cannot rebuild paritions online prior to SQL 2014
							 and IsNull(@containsLOB, 0) < 1 -- no lobs
								BEGIN
									SET @rebuildCommand = N' Rebuild PARTITION = ALL With (Online = Off';
								END
							ELSE -- partitioncount <= 1 regardless of version
								BEGIN
									SET @rebuildCommand = N' Rebuild With (Online = Off';
								END
 
				-- always make sure that we rebuild all new indexes with a fill factor of 80%, as this helps to reduce page splits and
				-- ultimately fragmentation
 
 				SET @rebuildCommand = @rebuildCommand + N', PAD_INDEX = ON, FILLFACTOR = 80, STATISTICS_NORECOMPUTE  = OFF'
 
                /* Set sort operation preferences */
                IF @sortInTempDB = 1 
                    SET @rebuildCommand = @rebuildCommand + N', Sort_In_TempDB = On';
                ELSE
                    SET @rebuildCommand = @rebuildCommand + N', Sort_In_TempDB = Off';
                  
                -- Add the data compression to the end of the rebuild statement, whether required or not!!!!
				-- DATA_COMPRESSION = { NONE | ROW | PAGE | COLUMNSTORE | COLUMNSTORE_ARCHIVE
  
				set @rebuildCommand = @rebuildCommand + N', DATA_COMPRESSION = ' + @compression;

                /* Set processor restriction options; requires Enterprise Edition */
                IF @maxDopRestriction IS Not Null And @editionCheck = 1
                    SET @rebuildCommand = @rebuildCommand + N', MaxDop = ' + CAST(@maxDopRestriction AS VARCHAR(2)) + N')';
                ELSE
                    SET @rebuildCommand = @rebuildCommand + N')';

-------------------------------------------------------------
-- SQL 2017 resumable index rebuild section added 03/01/2017
-------------------------------------------------------------
				If @ver =  'SQL2017' and 
				(
					(@tablename != '' or @tablename is not NULL) and
					(@databasename != '' or @databasename is not NULL) and
					@onlinerebuild = 1 and
					@resume = 1 and
					@editionCheck = 1 -- Enterprise only as online rebuilds required!
				)
						BEGIN
							SET @rebuildCommand = @rebuildCommand + N', RESUMABLE = ON'
						END
-----------------------------------------------
-- Build the final rebuild/re-organise command
-----------------------------------------------
 
                SET @sqlCommand = N'Alter Index ' +  @indexName + N' On ' + @databaseName  + N'.'
                                + @schemaName  + N'.'  + @objectName  + @rebuildCommand;
	
            END
            ELSE
                /* Print an error message if any indexes happen to not meet the criteria above */
                IF @printCommands = 1 Or @debugMode = 1
					BEGIN
						RAISERROR('We are unable to defrag this index.', 0, 42) WITH NoWait;
					END

            /* Are we executing the SQL?  If so, do it */
            IF @executeSQL = 1
            BEGIN
 
                SET @debugMessage = 'Executing: ' + @sqlCommand;
 
                /* Print the commands we're executing if specified to do so */
                IF @printCommands = 1 Or @debugMode = 1
                    RAISERROR(@debugMessage, 0, 42) WITH NoWait;
 
                /* Grab the time for logging purposes */
                SET @dateTimeStart  = GETDATE();
 
                /* Log our actions */
                INSERT INTO [DBAdmin].[dbo].[dba_indexDefragLog]
                (
                      databaseID
                    , databaseName
                    , objectID
                    , objectName
                    , indexID
                    , indexName
                    , partitionNumber
                    , fragmentation
                    , page_count
                    , dateTimeStart
                    , sqlStatement
                )
                SELECT
                      @databaseID
                    , @databaseName
                    , @objectID
                    , @objectName
                    , @indexID
                    , @indexName
                    , @partitionNumber
                    , @fragmentation
                    , @pageCount
                    , @dateTimeStart
                    , @sqlCommand;
 
                SET @indexDefrag_id = SCOPE_IDENTITY();
 
				select * from [DBAdmin].[dbo].[dba_indexDefragLog]
 
 --exec sp_help '[dbo].[dba_indexDefragLog]'
 
                /* Wrap our execution attempt in a try/catch and log any errors that occur */
                BEGIN Try
 
                    /* Execute our defrag! */
                    --############################################
                    -- print @sqlCommand;
                    -- Comment out if debug needed!!
                    --############################################
                    EXECUTE SP_EXECUTESQL @sqlCommand;
                    SET @dateTimeEnd = GETDATE();

                    /* Update our log with our completion time */
                    UPDATE dbadmin.dbo.dba_indexDefragLog
                    SET dateTimeEnd = @dateTimeEnd
                        , durationSeconds = DATEDIFF(SECOND, @dateTimeStart, @dateTimeEnd)
                    WHERE indexDefrag_id = @indexDefrag_id;
 
                END Try
                
                BEGIN Catch
 
					SELECT @ERR_MESSAGE = ERROR_MESSAGE(), @ERR_NUM = ERROR_NUMBER();

--	
-- Version 6.0 -- 01/02/2012
--				
---------------------------------------------------------------------------------------------------------------------------------
-- 	If one of the following error codes are thrown, then perform an index re-organize rather than a rebuild.
--  Codes can be obtained from sys.sysmessages.

-- 2725 -- An online operation cannot be performed because the index contains column of data type text, ntext, image, varchar(max), 
-- nvarchar(max), varbinary(max), xml, or large CLR type. For a non-clustered index, the column could be an in	
		
-- 1105 --Could not allocate space for object in database because the filegroup is full. Create disk space by deleting unneeded files, 
--dropping objects in the filegroup, adding additional files to the filegroup, or setting autogrowth on

-- 1101 -- Could not allocate a new page for database because of insufficient disk space in filegroup. Create the necessary 
-- space by dropping objects in the filegroup, adding additional files to the filegroup, or setting autogrowth on for existing files.
---------------------------------------------------------------------------------------------------------------------------------
	
 					IF @ERR_NUM in (2725,1101,1105) 

						BEGIN	
							SET @sqlCommand = N'Alter Index ' + @indexName  + N' On ' + @databaseName + N'.' 
								+ @schemaName  + N'.' + @objectName  + N' ReOrganize';

							IF @partitionCount > 1
								set @sqlCommand = @sqlCommand + N' PARTITION = ALL'
							
							/* Execute our defrag! */
							EXECUTE SP_EXECUTESQL @sqlCommand;
							SET @dateTimeEnd = GETDATE();

							/* Update our log with our completion time */
							UPDATE dbadmin.dbo.dba_indexDefragLog
							SET dateTimeEnd = @dateTimeEnd
								, durationSeconds = DATEDIFF(SECOND, @dateTimeStart, @dateTimeEnd)
							WHERE indexDefrag_id = @indexDefrag_id;
						END
						ELSE 
							BEGIN 
								IF @ERR_NUM NOT IN (2725,1101,1105) 

									BEGIN				 
										/* Update our log with our error message */
										UPDATE dbadmin.dbo.dba_indexDefragLog
										SET dateTimeEnd = GETDATE()
											, durationSeconds = -1
											, errorMessage = Error_Message()
										WHERE indexDefrag_id = @indexDefrag_id;
					 
										IF @debugMode = 1 
											RAISERROR('  An error has occurred executing this command! 
											Please review the dba_indexDefragLog table for details.'
												, 0, 42) WITH NoWait;
									END	
								END
                END Catch
 
                /* Just a little breather for the server */
                WAITFOR Delay @defragDelay;
 
                UPDATE dbadmin.dbo.dba_indexDefragStatus
                SET defragDate = GETDATE()
                    , printStatus = 1
                WHERE databaseID       = @databaseID
                  And objectID         = @objectID
                  And indexID          = @indexID
                  And partitionNumber  = @partitionNumber;
 
            END
            ELSE
            /* Looks like we're not executing, just printing the commands */
            BEGIN
                IF @debugMode = 1 RAISERROR('  Printing SQL statements...', 0, 42) WITH NoWait;
 
                IF @printCommands = 1 Or @debugMode = 1 
                    PRINT IsNull(@sqlCommand, 'error!');
 
                UPDATE dbadmin.dbo.dba_indexDefragStatus
                SET printStatus = 1
                WHERE databaseID       = @databaseID
                  And objectID         = @objectID
                  And indexID          = @indexID
                  And partitionNumber  = @partitionNumber;
            END
 
        END
 
        /* Do we want to output our fragmentation results? */
        IF @printFragmentation = 1
        BEGIN
 
            IF @debugMode = 1 RAISERROR('  Displaying a summary of our action...', 0, 42) WITH NoWait;
 
            SELECT databaseID
                , databaseName
                , objectID
                , objectName
                , indexID
                , indexName
                , partitionNumber
                , fragmentation
                , page_count
                , range_scan_count
            FROM dbadmin.dbo.dba_indexDefragStatus
            WHERE defragDate >= @startDateTime
            ORDER BY defragDate;
 
        END;

 
    END Try
    BEGIN Catch
 
        SET @debugMessage = Error_Message() + ' (Line Number: ' + CAST(Error_Line() AS VARCHAR(30)) + ')';
        PRINT @debugMessage;
 
    END Catch;
 
    /* When everything is said and done, make sure to get rid of our temp table */
    DROP TABLE #databaseList;
    DROP TABLE #processor;
    DROP TABLE #maxPartitionList;
 
    IF @debugMode = 1 RAISERROR('ALL COMPLETED! Your indexes are now a lot better than before!!!! :)', 0, 42) WITH NoWait;
 
        SET NOCOUNT OFF;
    -- ##############################################################################
    -- Comment out RETURN 0 if you are running this for DEBUG within SSMS
    -- ##############################################################################
   RETURN 0
    -- ##############################################################################
END