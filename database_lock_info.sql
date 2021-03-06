USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[database_lock_info]    Script Date: 07/09/2018 08:33:34 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dba].[database_lock_info]
(
@dbname sysname = NULL,
@spid int = NULL
)

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 21/02/2008
-- Version	: 01:00
--
-- Desc		: To show detailed lock info for a given database / users / object
--		  Installed under the master database of an instance
--
-- Modification History
-- ====================
--
--
--
-- Examples
-- ========
-- To see all the locks:
-- EXEC [dba].[database_lock_info]
--
-- To see all the locks in a particular database, say 'pubs':
-- EXEC [dba].[database_lock_info] pubs
--
-- To see all the locks held by a particular spid, say 53:
-- EXEC [dba].[database_lock_info] @spid = 53
--
-- To see all the locks held by a particular spid (23), in a particular database (pubs):
-- EXEC [dba].[database_lock_info] pubs, 23
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


AS

BEGIN
SET NOCOUNT ON
CREATE TABLE #lock
(
	spid int,
	dbid int,
	ObjId int,
	IndId int,
	Type char(5),
	Resource char(20),
	Mode char(10),
	Status char(10)
)

INSERT INTO #lock EXEC sp_lock

IF @dbname IS NULL
BEGIN
	IF @spid IS NULL
	BEGIN
		SELECT a.spid AS SPID, 
		(SELECT DISTINCT program_name FROM master..sysprocesses WHERE spid = a.spid) AS [Program 

Name],
		db_name(dbid) AS [Database Name], ISNULL(object_name(ObjId),'') AS [Object Name],IndId, 

Type, Resource, Mode, Status
		FROM #lock a
	END
	ELSE
	BEGIN
		SELECT a.spid AS SPID, 
		(SELECT DISTINCT program_name FROM master..sysprocesses WHERE spid = a.spid) AS [Program 

Name],	
		db_name(dbid) AS [Database Name], ISNULL(object_name(ObjId),'') AS [Object Name],IndId, 

Type, Resource, Mode, Status
		FROM #lock a
		WHERE spid = @spid
	END
END
ELSE
BEGIN
	IF @spid IS NULL 
	BEGIN
		SELECT a.spid AS SPID,
		(SELECT DISTINCT program_name FROM master..sysprocesses WHERE spid = a.spid) AS [Program 

Name],		
		ISNULL(object_name(a.ObjId),'') AS [Object Name],a.IndId, 
		ISNULL((SELECT name FROM sysindexes WHERE id = a.objid and indid = a.indid ),'') AS 

[Index Name],
		a.Type, a.Resource, a.Mode, a.Status
		FROM #lock a
		WHERE dbid = db_id(@dbname)
	END
	ELSE
	BEGIN
		SELECT a.spid AS SPID,
		(SELECT DISTINCT program_name FROM master..sysprocesses WHERE spid = a.spid) AS [Program 

Name],
		ISNULL(object_name(a.ObjId),'') AS [Object Name],a.IndId, 
		ISNULL((SELECT name FROM sysindexes WHERE id = a.objid and indid = a.indid ),'') AS 

[Index Name],
		a.Type, a.Resource, a.Mode, a.Status
		FROM #lock a
		WHERE dbid = db_id(@dbname) AND spid = @spid			
	END
END

DROP TABLE #lock

END

