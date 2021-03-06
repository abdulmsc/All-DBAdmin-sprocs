USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dbo].[vol_space_capacity_sp]    Script Date: 07/09/2018 10:59:37 ******/
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


ALTER PROCEDURE [dbo].[vol_space_capacity_sp]
@beginDt datetime, @endDt datetime
AS

SET NOCOUNT ON

;WITH 
avg_vol_space (server_name, vol_name, avg_growth_gb)
AS
(
  SELECT server_name, vol_name, ROUND(AVG(daily_growth_gb),2)
  FROM vol_space_change_vw
  WHERE dt BETWEEN @beginDt AND @endDt
  GROUP BY server_name, vol_name
  
),
begin_vol_space (server_name, vol_name, begin_dt, begin_size_gb, begin_free_gb, begin_percent_free)
AS
(
	SELECT v.server_name, v.vol_name, v.dt, v.size_gb, v.free_gb, v.percent_free
	FROM dbo.vol_space v
	JOIN (SELECT server_name, vol_name, min(dt) AS dt FROM dbo.vol_space 
			WHERE dt BETWEEN @beginDt AND @endDt GROUP BY server_name, vol_name) AS m
	ON v.server_name = m.server_name
	AND v.vol_name = m.vol_name
	AND v.dt = m.dt
)	
SELECT e.server_name, e.vol_name, begin_dt, e.dt AS end_dt, e.vol_lbl, begin_size_gb,
e.size_gb AS end_size_gb, begin_free_gb, e.free_gb AS end_free_gb, begin_percent_free,
e.percent_free AS end_percent_free, usable_size_gb, allocated_gb, avg_growth_gb, 
CASE
	WHEN avg_growth_gb > 0 THEN 
		CAST(ROUND((e.size_gb - e.allocated_gb)/ avg_growth_gb,2) AS numeric(18,2))
	ELSE
		NULL
END AS days_remaining
FROM vol_space_change_vw e
JOIN avg_vol_space a
ON e.server_name = a.server_name
AND e.vol_name = a.vol_name
JOIN begin_vol_space b
ON e.server_name = b.server_name
AND e.vol_name = b.vol_name
WHERE e.dt = @endDt
ORDER BY e.server_name, e.vol_name

