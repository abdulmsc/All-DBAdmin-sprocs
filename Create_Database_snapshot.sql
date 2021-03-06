USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[Create_Database_snapshot]    Script Date: 07/09/2018 08:28:51 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 24/01/2008
-- Version	: 01:00
--
-- Desc		: To create a database snapshot of a given database
--			  exec dba.Create_Database_snapshot edm, edm_snap 
--	
-- Modification History
-- ====================
-- 
-- 23/06/2011			Haden Kingsland
-- 
-- Amended the script to use XML to output the snapshot command to overcome issues with the
-- print statement ... details follow ...
--
-- use the below XML command to output the contents of a variable into an xml string
-- so that it ignores the 4000 byte limit of the print statement.
-- You will obviously need to remove the <x> and </x> tags from the start and end
-- of the outputted string before you run it.
--
-- PRINT @command
-- select CONVERT(xml, '<x><![CDATA[ ' +@command + ']]></x>') --AS DataXML
--
--#############################################################

-- #####################
-- TO RUN INTERACTIVELY
-- #####################
-- If running interactively, or to debug the script, you must comment out the create procedure header
-- and parameter definitions, and uncomment out the DEBUG section of code.
-- #####################
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

ALTER PROCEDURE [dba].[Create_Database_snapshot]
    (
		@Masterdb VARCHAR(255), 
		@SnapshotName VARCHAR(255), 
		-- will execute the code to create the snapshot if '1', or output xml string of
		-- the @command string if '0'
		@Execute BIT = 1 
	) 
AS 

    SET NOCOUNT ON 
    DECLARE @NewLine CHAR(2) 
    DECLARE @Q CHAR(1) 
    DECLARE @fname VARCHAR(255) 
    DECLARE @extention VARCHAR(255) 
    DECLARE @Pfad VARCHAR(255) 
    DECLARE @DBname VARCHAR(255) 
    DECLARE @LogicName VARCHAR(255) 
    DECLARE @Command VARCHAR(MAX) 
    DECLARE @Command2 VARCHAR(MAX) 
    DECLARE @indexExt INT 
    DECLARE @indexPfad INT 
    DECLARE @lenFname INT 
    DECLARE @lenPfad INT 
    DECLARE @lenDB INT 
    DECLARE @lenExt INT 

-- #################
-- START OF DEBUG --
-- #################
--
--DECLARE @Masterdb VARCHAR(255), 
--		@SnapshotName VARCHAR(255), 
--		@Execute BIT
--
--
--SET @Masterdb =  DB_NAME(db_id())  --'Master'
--SET @snapshotname = @masterdb + '_snap_' + convert(char(8),getdate(),112)
--SET @execute = 1
--
-- ################
-- END OF DEBUG --
-- ################

    CREATE TABLE #Info
        (physical_name VARCHAR(255) not null, 
        logicname VARCHAR(255) not null) 

    SET @newLine = CHAR(13) + CHAR(10) 
    SET @Q = CHAR(39) 

    SET @command = 'INSERT INTO #info (physical_name, logicname) 
        SELECT s.physical_name,s.[name] AS LogicName 
        FROM '
            + Quotename(@masterdb) + '.sys.filegroups as g 
        INNER JOIN
        sys.master_files AS s ON 
            s.type = 0 
            AND s.database_id = db_id(' + @Q + @Masterdb + @Q + ') 
            AND s.drop_lsn is null 
            AND s.data_space_id = g.data_space_id 
        ORDER BY
            g.data_space_id' 
    EXECUTE (@Command) 

    SET @Command = 'CREATE DATABASE ' + @SnapshotName + @NewLine 
    SET @Command = @Command + 'ON' + @NewLine 

    DECLARE c CURSOR 
    READ_ONLY 
    FOR SELECT physical_name, logicname FROM #info 

    OPEN c 
    FETCH NEXT FROM c INTO @fname,@LogicName 
        WHILE (@@fetch_status <> -1) 
        BEGIN 
            IF (@@fetch_status <> -2) 
            BEGIN 
                SET @fname = REVERSE(@fname) 
                SET @lenFname = LEN(@fname) 
                SET @indexExt = CHARINDEX('.',@fname) -1 
                SET @indexPfad = CHARINDEX('\',@fname) - 1 
                SET @extention = REVERSE(SUBSTRING (@fname, 1, @indexExt)) 
                SET @lenExt = LEN(@extention) 
                SET @Pfad = LEFT (REVERSE(@fname), @lenFname - @indexPfad) 
                SET        @lenPfad = LEN(@Pfad) 
                SET @DBname = SUBSTRING(REVERSE(@fname), @lenPfad + 1, (@lenFname - @lenPfad - @lenExt) - 1) 
                SET @Command = @Command + '(Name = ' + @Q + @LogicName + @Q + ', Filename = ' + @Q 
                SET @Command = @Command + @Pfad + @SnapshotName + '_' + @DBname + '.' + 'ssh' + @Q + '),' + @NewLine 
            END 
        FETCH NEXT FROM c INTO @fname,@LogicName 
        END 
    CLOSE c 
    DEALLOCATE c 
    SET @Command = LEFT(@Command,LEN(@Command)-3) + @NewLine + 'AS SNAPSHOT OF ' + @masterdb 
        
    IF @Execute = 1 
    BEGIN 
    
        EXEC (@Command) 
        
    END 
    
    ELSE 
		BEGIN 
		
		-- SELECT @Command AS Command 
		-- use the below XML command to output the contents of a variable into an xml string
		-- so that it ignores the 4000 byte limit of the print statement.
		-- You will obviously need to remove the <x> and </x> tags from the start and end
		-- of the outputted string before you run it.

		select CONVERT(xml, '<x><![CDATA[ ' + @command + ']]></x>') --AS DataXML
	         
		END

DROP TABLE #Info

--declare @sql_txt varchar(max)
--set @sql_txt = '.........a very long string.........'
--print(@sql_txt)
--if (len(@sql_txt) > 8000)
--print(substring(@sql_txt, 8001, len(@sql_txt) - 8000))
--if (len(@sql_txt) > 16000)
--print(substring(@sql_txt, 16001, len(@sql_txt) - 16000))
--if (len(@sql_txt) > 24000)
--print(substring(@sql_txt, 24001, len(@sql_txt) - 24000))
--if (len(@sql_txt) > 32000)
--print(substring(@sql_txt, 32001, len(@sql_txt) - 32000))

