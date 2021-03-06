USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_VLF_TXLOG_Check]    Script Date: 07/09/2018 10:30:51 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 28/08/20011
-- Version	: 01:00
--
-- Desc		: This procedure checks the transaction log of each database on the server and
--			  emails a report if any contain more than a specified number of virtual log files
--            (as defined in the @MaxVLFs variable). 
--            Excessive VLFs can result in poor performance.
--
-- Modification History
-- ====================
--
-- 07/09/2018	Haden Kingsland		Changed to allow an input parameter for email address
--									Changed to take both SQL Server 2016 and SQL Server 2017 into account
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
--  exec dbadmin.dba.usp_VLF_TXLOG_Check 'yourname@youremail.com'
--

ALTER procedure [dba].[usp_VLF_TXLOG_Check]
@EmailRecipients as varchar(200)

as

declare @SQLCmd as varchar (40),
		@DBName as varchar (100),
		@DBID as int,
		@MaxVLFs as smallint,
		@VLFCount as int,
		@EmailSubject as varchar (255),
		@EmailBody as varchar (max),
		@MailProfileName VARCHAR(50),
		@ver varchar(15);

SELECT @MailProfileName = name
	FROM msdb.dbo.sysmail_profile WITH (NOLOCK)
	WHERE name like '%DBA%'

set @EmailSubject = 'Excessive VLFs found for databases within ' + @@servername;
set @EmailBody = 'Transaction log files with excessive VLFs have been found. ';
set @MaxVLFs = 50;

/* threshold for number of VLFs */

set @ver = ''

		SELECT @ver = CASE WHEN @@VERSION LIKE '%8.0%'	THEN 'SQL2000' 
						   WHEN @@VERSION LIKE '%9.0%'	THEN 'SQL2005'
						   WHEN @@VERSION LIKE '%10.0%' THEN 'SQL2008' 
						   WHEN @@VERSION LIKE '%10.5%' THEN 'SQL2008R2' 
						   WHEN @@VERSION LIKE '%11.0%' THEN 'SQL2012' 
						   WHEN @@VERSION LIKE '%12.0%' THEN 'SQL2014'
						   WHEN @@VERSION LIKE '%13.0%' THEN 'SQL2016'
						   WHEN @@VERSION LIKE '%14.0%' THEN 'SQL2017'
		END;

declare DBNameCursor cursor
    for select database_id
        from   sys.databases
        where  state = 0;
        
/* online databases only */

	IF LTRIM(RTRIM(@ver)) not in ('SQL2012','SQL2014','SQL2016','SQL2017') -- before version 2012 and 2014
		BEGIN
			declare @LogInfo table (
				FileId      tinyint        ,
				FileSize    bigint         ,
				StartOffset bigint         ,
				FSeqNo      int            ,
				Status      tinyint        ,
				Parity      tinyint        ,
				CreateLSN   numeric (25, 0))
		END
	ELSE
		BEGIN
			declare @LogInfo_2012 table (
				RecoveryUnitId tinyint,
				FileId      tinyint        ,
				FileSize    bigint         ,
				StartOffset bigint         ,
				FSeqNo      int            ,
				Status      tinyint        ,
				Parity      tinyint        ,
				CreateLSN   numeric (25, 0))
		END

if OBJECT_ID('tempdb..##ManyVLFsFound') is not null
    drop table ##ManyVLFsFound;
    
create table ##ManyVLFsFound
(
    dbname    varchar (100),
    NumOfVLFs int          
);

open DBNameCursor;

fetch next 
from DBNameCursor 
into @DBID;

while @@fetch_status = 0
    begin
        
        set @SQLCmd = 'DBCC LOGINFO (' + convert (varchar (5), @DBID) + ') WITH NO_INFOMSGS'
		
		IF LTRIM(RTRIM(@ver)) not in ('SQL2012','SQL2014','SQL2016','SQL2017')
			BEGIN
				insert into @LogInfo
				        execute (@SQLCmd);
				        
				select @VLFCount = COUNT(*)
				from   @LogInfo;
			END
		ELSE
			BEGIN
				insert into @LogInfo_2012
				        execute (@SQLCmd);
				        
				select @VLFCount = COUNT(*)
				from   @LogInfo_2012;
			END

        if @VLFCount > @MaxVLFs
            begin
                select @DBName = name
                from   sys.databases
                where  database_id = @DBID;
                insert  into ##ManyVLFsFound
                values (@DBName, @VLFCount);
            end
            
        --delete @LogInfo;
        
        fetch next 
        from DBNameCursor 
        into @DBID;
        
    end
    
close DBNameCursor;

deallocate DBNameCursor;

IF (select COUNT(*)
    from   ##ManyVLFsFound) > 0
    
    begin
    
        execute msdb.dbo.sp_send_dbmail
        @profile_name = @MailProfileName,
        @recipients = @EmailRecipients, 
        @subject = @EmailSubject, 
        @body = @EmailBody, 
        @query = 'SELECT NumOfVLFs, DBName FROM ##ManyVLFsFound';
        
    end
    
drop table ##ManyVLFsFound;

