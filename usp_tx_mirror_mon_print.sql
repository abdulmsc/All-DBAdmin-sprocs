USE [DBAdmin]
GO
/****** Object:  StoredProcedure [dba].[usp_tx_mirror_mon_print]    Script Date: 07/09/2018 10:29:55 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- exec [dba].[usp_tx_mirror_mon_print]
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

ALTER procedure [dba].[usp_tx_mirror_mon_print]
as

BEGIN

create table #LogUsageInfo 
( db_name varchar(50), 
  log_size dec (8, 2), 
  log_used_percent dec (8, 2),
  status dec (7, 1) )

insert #LogUsageInfo  exec ('dbcc sqlperf(logspace) with no_infomsgs')

print '<--table MirrorTXInfo starts-->'

select 
--CONVERT(CHAR(20),GETDATE(),113) as "Time",
convert(varchar(20),d.name) as "DBName",
convert(varchar(5),li.log_used_percent) as "TX_Log_Used",
--convert(varchar(5),li.log_used_percent) + ' %' as "TX_Log_Used",
convert(varchar(15),convert(bigint,(f.size * 8)/1024))  as "Crnt_Phys_TXL_Size",
convert(varchar(15),convert(bigint,(f.maxsize/1024)*8))  as "Max_Phys_TXL_Size",
--convert(varchar(15),convert(bigint,(f.maxsize/1024)*8)) + ' Mb' as "Max_Phys_TXL_Size",
convert(varchar(15), f.name) as "Filename",
case m.mirroring_role 
when 1 then 'Principal' 
when 2 then 'Mirror' 
END as "Crnt_State",
convert(varchar(30),@@servername) as "Crnt_Node",
convert(varchar(30),m.mirroring_partner_instance) as "Partner_Node",
convert(varchar(20),m.mirroring_witness_state_desc) as "Witness_State",
convert(varchar(20),m.mirroring_state_desc) as "Mirror_State"
--convert(varchar(20),m.mirroring_witness_name) as "Witness Name"
into #DBInfo
from 
sys.databases d, 
sys.database_mirroring m,
#LogUsageInfo li,
sys.sysaltfiles f
where d.database_id = m.database_id
and db_id(li.db_name) = d.database_id
and db_id(li.db_name) = m.database_id
and f.dbid = d.database_id
and f.dbid = db_id(li.db_name)
and m.mirroring_state_desc is NOT NULL
and f.name like '%log%'
order by d.name asc

select dbname as 'DB', 
tx_log_used as '%_Used',
sum(convert(int, crnt_phys_txl_size)) as 'Cur_Size',
sum(convert(int, max_phys_txl_size))as 'Max_Size',
--filename
crnt_State as 'State',
crnt_node as 'Current_Node',
partner_node as 'Partner_Node',
witness_state as 'Witness_State ',
mirror_state 'Mirror_State'
from #DBInfo
group by dbname, tx_log_used,crnt_State,crnt_node,partner_node,witness_state,mirror_state

print '<--table MirrorTXInfo ends-->'
					
drop table #LogUsageInfo
drop table #dbinfo

END;

