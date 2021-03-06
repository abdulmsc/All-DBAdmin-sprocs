USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[check_server_disk_space]    Script Date: 07/09/2018 08:25:55 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ###################################################################################
--
-- Author:			Haden Kingsland
--
-- Date:			2nd October 2012
--
-- Description :	To use OLE object calls and xp_fixeddrives to return information 
--					regarding the drive allocated to a particular server. It then stores 
--					this information within the dba.drivespace table within the DBAdmin
--					database for that instance.
--
--
--exec dba.check_server_disk_space
--
-- You WILL need to create this table prior to running this procedure
--
--create table dbadmin.dba.drivespace
--(
--    drive		char (1), --	primary key,
--    FreeSpace	int			null,
--    TotalSize	int			null,
--    percentfree int			null,
--    metricdate	datetime,
--    servername	varchar(50)
--);

-- drop table dbadmin.dba.drivespace
-- truncate table dbadmin.dba.drivespace
-- select * from DBAdmin.dba.drivespace order by drive asc

--select MAX(percentfree), * 
--from DBAdmin.dba.drivespace
----where  DATEdiff(mi, metricdate, GetDate()) > 20 -- return results for 'n' minutes ago
--where  DATEdiff(dd, metricdate, GetDate()) > 1 -- return results for the previous day
--group by percentfree, drive, 
--totalsize,freespace,
--metricdate,
--servername
--order by drive asc
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

ALTER procedure [dba].[check_server_disk_space]

AS

BEGIN

declare @hr as int,
		@fso as int,
		@drive as char (1),
		@odrive as int,
		@TotalSize as varchar (20),
		@freespace as int,
		@percentused as int,
		@OLEAUTOMATION_ORIG_ON varchar(1),
		@MB as numeric;

---------------------
-- Initialize variables
---------------------

set @OLEAUTOMATION_ORIG_ON = ''

--------------------------------------------------------------------------------------------------------------------
-- Check whether Ole Automation is turned off via Surface Area Configuration (2005) / Instance Facets (2008)
-- This is best practice !!!!! If it is already turned on, LEAVE it on !!

-- turn on advanced options
	EXEC sp_configure 'show advanced options', 1 reconfigure 
	RECONFIGURE  

	CREATE TABLE #advance_opt 
	(
	name VARCHAR(50),
	min int, 
	max int, 
	conf int, 
	run int
	)
		INSERT #advance_opt
		EXEC sp_configure 'Ole Automation Procedures' -- this will show whether xp_cmdshell is turned on or not
				
	IF (select conf from #advance_opt) = 0 -- check if Ole Automation is turned on or off, if off, then turn it on
		BEGIN

			set @OLEAUTOMATION_ORIG_ON = 'N' -- make a note that it is NOT supposed to be on all the time
			
			--turn on Ole Automation to allow OLE commands to be run
			EXEC sp_configure 'Ole Automation Procedures', 1 
			RECONFIGURE
		END
	ELSE
		BEGIN
		 -- make a note that Ole Automation was already turned on, so not to turn it off later by mistake
			set @OLEAUTOMATION_ORIG_ON = 'Y'
		END

-- drop the temporary table to tidy up after ourselves.

	IF EXISTS (
	select * from tempdb.sys.objects
	where name like '%advance_opt%'
	)
		BEGIN
			drop table #advance_opt
		END	
--------------------------------------------------------------------------------------------------------------------
set @MB = 1048576; -- values are in kb's, so divide by 1024 and then 1024 again (1048576)

create table #drives
(
    drive		char (1)	primary key,
    FreeSpace	int			null,
    TotalSize	int			null,
    percentfree int			null,
    metricdate	datetime,
    servername	varchar(80)
);

insert #drives (drive, FreeSpace)
execute master.dbo.xp_fixeddrives

execute @hr = sp_OACreate 'Scripting.FileSystemObject', @fso output

if @hr <> 0
    execute sp_OAGetErrorInfo @fso

declare drivesize_cursor cursor local fast_forward
    for select   drive,
				 freespace
        from     #drives
        order by drive

open drivesize_cursor

fetch next from drivesize_cursor 
into @drive, 
@freespace

while @@FETCH_STATUS = 0
    begin
        execute @hr = sp_OAMethod @fso, 'GetDrive', @odrive output, @drive
        
        if @hr <> 0
            execute sp_OAGetErrorInfo @fso
            
        execute @hr = sp_OAGetProperty @odrive, 'TotalSize', @TotalSize output
        
        if @hr <> 0
            execute sp_OAGetErrorInfo @odrive
            
        update  #drives
            set TotalSize = convert(numeric,@TotalSize) / @MB,
            percentfree = (@freespace*100)/(@TotalSize / @MB),
            metricdate = GETDATE(),
            servername = LTRIM(left(@@SERVERNAME,(len(@@SERVERNAME))-(charindex('\',reverse(@@SERVERNAME)))))
        where   drive = @drive
        
        INSERT INTO DBAdmin.dba.drivespace
        select * from #drives where drive = @drive
           --([drive]
           --,[FreeSpace]
           --,[TotalSize]
           --,[percentfree])
			--VALUES
           --(<drive, char(1),>
           --,<FreeSpace, int,>
           --,<TotalSize, int,>
           --,<percentfree, int,>)

        fetch next from drivesize_cursor 
        into @drive, 
        @freespace
        
    end

close drivesize_cursor
deallocate drivesize_cursor

execute @hr = sp_OADestroy @fso

if @hr <> 0
    execute sp_OAGetErrorInfo @fso

--select   drive,
--         TotalSize as 'Total(MB)',
--         FreeSpace as 'Free(MB)',
--         --round(convert(decimal(4,2),(Freespace*100/TotalSize)),1) as '% Free',
--         (Freespace*100/TotalSize) as '% Free'
--from     #drives
--where (Freespace*100/TotalSize) <= 40
--order by drive;

drop table #drives

----------------------------------------------------------------------------------------------------------------------		
-- turn off advanced options

	IF @OLEAUTOMATION_ORIG_ON = 'N'  -- if Ole Automation was NOT originally turned on, then turn it off 
	BEGIN

		--  turn off Ole Automation if it was not already turned on
		EXEC sp_configure 'Ole Automation Procedures', 0  reconfigure
		RECONFIGURE

		EXEC sp_configure 'show advanced options', 0 reconfigure
		RECONFIGURE
		
	END
-----------------------------------------------------------------------------------------------------------------------
					
END;

--select ltrim(rtrim(@@SERVERNAME))

--select LTRIM(left(@@SERVERNAME,(len(@@SERVERNAME))-(charindex('\',reverse(@@SERVERNAME)))))

