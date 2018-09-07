
USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_quick_check_for_failed_agent_jobs]    Script Date: 07/09/2018 11:21:17 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dba].[usp_quick_check_for_latest_backups]

--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 07/09/2018
-- Version	: 01:00
--
-- Desc		: To quickly show the details of the latest backups
--			  of all types for all databases (not copy only)
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
--
-- 	exec [dba].[usp_quick_check_for_latest_backups]
--
/********************************************************************************************************************/
AS

BEGIN

SELECT DatabaseName = x.database_name, 
       LastBackupFileName = x.physical_device_name,
       CASE x.[type]
           WHEN 'D'
           THEN 'FULL'
           WHEN 'I'
           THEN 'Differential'
           WHEN 'L'
           THEN 'Transaction Log'
           ELSE 'Not Known'
       END AS [Backup Type], 
       CAST((CAST(DATEDIFF(s, x.backup_start_date, x.backup_finish_date) AS INT)) / 3600 AS VARCHAR)+' hours, '+CAST((CAST(DATEDIFF(s, x.backup_start_date, x.backup_finish_date) AS INT)) / 60 AS VARCHAR)+' minutes, '+CAST((CAST(DATEDIFF(s, x.backup_start_date, x.backup_finish_date) AS INT)) % 60 AS VARCHAR)+' seconds' AS [Total Time], 
       x.backup_size / 1024 / 1024 AS BackupSizeMB, 
       SUBSTRING(x.physical_device_name, 1,
                                         CASE CHARINDEX(REVERSE('\'), REVERSE(x.physical_device_name))
                                             WHEN 0
                                             THEN 0
                                             ELSE LEN(x.physical_device_name)-(CHARINDEX(REVERSE('\'), REVERSE(x.physical_device_name))+(LEN('\')-1))+1
                                         END) AS 'path', 
       LastBackupDatetime = x.backup_start_date
FROM
(
    SELECT bs.database_name, 
           bs.backup_start_date, 
           bs.backup_finish_date, 
           bmf.physical_device_name, 
           bs.backup_size, 
           bs.[type], 
           Ordinal = ROW_NUMBER() OVER(PARTITION BY bs.database_name ORDER BY bs.backup_start_date DESC)
    FROM msdb.dbo.backupmediafamily bmf
         JOIN msdb.dbo.backupmediaset bms ON bmf.media_set_id = bms.media_set_id
         JOIN msdb.dbo.backupset bs ON bms.media_set_id = bs.media_set_id
    WHERE bs.[type] IN('D') -- for FULL backups
         AND bs.is_copy_only = 0
) x
WHERE x.Ordinal = 1
UNION
SELECT DatabaseName = x.database_name, 
       LastBackupFileName = x.physical_device_name,
       CASE x.[type]
           WHEN 'D'
           THEN 'FULL'
           WHEN 'I'
           THEN 'Differential'
           WHEN 'L'
           THEN 'Transaction Log'
           ELSE 'Not Known'
       END AS [Backup Type], 
       CAST((CAST(DATEDIFF(s, x.backup_start_date, x.backup_finish_date) AS INT)) / 3600 AS VARCHAR)+' hours, '+CAST((CAST(DATEDIFF(s, x.backup_start_date, x.backup_finish_date) AS INT)) / 60 AS VARCHAR)+' minutes, '+CAST((CAST(DATEDIFF(s, x.backup_start_date, x.backup_finish_date) AS INT)) % 60 AS VARCHAR)+' seconds' AS [Total Time], 
       x.backup_size / 1024 / 1024 AS BackupSizeMB, 
       SUBSTRING(x.physical_device_name, 1,
                                         CASE CHARINDEX(REVERSE('\'), REVERSE(x.physical_device_name))
                                             WHEN 0
                                             THEN 0
                                             ELSE LEN(x.physical_device_name)-(CHARINDEX(REVERSE('\'), REVERSE(x.physical_device_name))+(LEN('\')-1))+1
                                         END) AS 'path', 
       LastBackupDatetime = x.backup_start_date
FROM
(
    SELECT bs.database_name, 
           bs.backup_start_date, 
           bs.backup_finish_date, 
           bmf.physical_device_name, 
           bs.backup_size, 
           bs.[type], 
           Ordinal = ROW_NUMBER() OVER(PARTITION BY bs.database_name ORDER BY bs.backup_start_date DESC)
    FROM msdb.dbo.backupmediafamily bmf
         JOIN msdb.dbo.backupmediaset bms ON bmf.media_set_id = bms.media_set_id
         JOIN msdb.dbo.backupset bs ON bms.media_set_id = bs.media_set_id
    WHERE bs.[type] IN('I') -- for differential backups
         AND bs.is_copy_only = 0
) x
WHERE x.Ordinal = 1
UNION
SELECT DatabaseName = x.database_name, 
       LastBackupFileName = x.physical_device_name,
       CASE x.[type]
           WHEN 'D'
           THEN 'FULL'
           WHEN 'I'
           THEN 'Differential'
           WHEN 'L'
           THEN 'Transaction Log'
           ELSE 'Not Known'
       END AS [Backup Type], 
       CAST((CAST(DATEDIFF(s, x.backup_start_date, x.backup_finish_date) AS INT)) / 3600 AS VARCHAR)+' hours, '+CAST((CAST(DATEDIFF(s, x.backup_start_date, x.backup_finish_date) AS INT)) / 60 AS VARCHAR)+' minutes, '+CAST((CAST(DATEDIFF(s, x.backup_start_date, x.backup_finish_date) AS INT)) % 60 AS VARCHAR)+' seconds' AS [Total Time], 
       x.backup_size / 1024 / 1024 AS BackupSizeMB, 
       SUBSTRING(x.physical_device_name, 1,
                                         CASE CHARINDEX(REVERSE('\'), REVERSE(x.physical_device_name))
                                             WHEN 0
                                             THEN 0
                                             ELSE LEN(x.physical_device_name)-(CHARINDEX(REVERSE('\'), REVERSE(x.physical_device_name))+(LEN('\')-1))+1
                                         END) AS 'path', 
       LastBackupDatetime = x.backup_start_date
FROM
(
    SELECT bs.database_name, 
           bs.backup_start_date, 
           bs.backup_finish_date, 
           bmf.physical_device_name, 
           bs.backup_size, 
           bs.[type], 
           Ordinal = ROW_NUMBER() OVER(PARTITION BY bs.database_name ORDER BY bs.backup_start_date DESC)
    FROM msdb.dbo.backupmediafamily bmf
         JOIN msdb.dbo.backupmediaset bms ON bmf.media_set_id = bms.media_set_id
         JOIN msdb.dbo.backupset bs ON bms.media_set_id = bs.media_set_id
    WHERE bs.[type] IN('L') -- for transaction log backups
         AND bs.is_copy_only = 0
) x
WHERE x.Ordinal = 1
ORDER BY DatabaseName, 
         LastBackupDatetime;

END;