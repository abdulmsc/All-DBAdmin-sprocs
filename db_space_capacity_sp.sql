USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dbo].[db_space_capacity_sp]    Script Date: 07/09/2018 10:57:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--#############################################################
--
-- Author	: Haden Kingsland
-- Date		: 31/11/2009
-- Version	: 01:00
--
-- Desc		: To obtain disk space and capacity
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
/********************************************************************************************************************/


ALTER PROCEDURE [dbo].[db_space_capacity_sp]
@beginDt datetime, @endDt datetime
AS

SET NOCOUNT ON

;WITH 
avg_db_space (server_name, dbname, physical_name, avg_growth_mb)
AS
(
  SELECT server_name, dbname, physical_name, ROUND(AVG(daily_growth_mb),2)
  FROM db_space_change_vw
  WHERE dt BETWEEN @beginDt AND @endDt
  GROUP BY server_name, dbname, physical_name 
  
),
begin_db_space (server_name, dbname, physical_name, begin_dt, begin_size_mb, begin_free_mb, begin_percent_free)
AS
(
	SELECT server_name, dbname, physical_name, dt, size_mb, free_mb, percent_free
	FROM dbo.db_space_change_vw
	WHERE dt = @beginDt
)
SELECT e.server_name, e.dbname, e.physical_name, begin_dt, e.dt AS end_dt, begin_size_mb,
e.size_mb AS end_size_mb, begin_free_mb, e.free_mb AS end_free_mb, begin_percent_free,
e.percent_free AS end_percent_free, (e.size_mb - e.free_mb) AS allocated_mb, avg_growth_mb, 
CASE
	WHEN avg_growth_mb > 0 THEN 
		CAST(ROUND(e.free_mb / avg_growth_mb,2) AS numeric(18,2))
	ELSE
		NULL
END AS days_remaining
FROM db_space_change_vw e
JOIN avg_db_space a
ON e.server_name = a.server_name
AND e.dbname = a.dbname
AND e.physical_name = a.physical_name
JOIN begin_db_space b
ON e.server_name = b.server_name
AND e.dbname = b.dbname
AND e.physical_name = b.physical_name
WHERE e.dt = @endDt
ORDER BY e.server_name, e.dbname, e.physical_name

