-- ============================================================================
-- 03_views.sql  (Datenbank: msv_dwh)
-- Auswertungs-Views mit Window Functions. Power BI kann sie direkt nutzen.
-- ============================================================================

-- Tabelle je Saison (Platzierung nach Punkten, Tordifferenz, Toren - wie in der 3. Liga)
CREATE OR ALTER VIEW dwh.v_season_table AS
WITH agg AS (
    SELECT f.season_key,
           f.team_key,
           COUNT(*)                                          AS played,
           SUM(CASE WHEN f.result_code = 'S' THEN 1 ELSE 0 END) AS wins,
           SUM(CASE WHEN f.result_code = 'U' THEN 1 ELSE 0 END) AS draws,
           SUM(CASE WHEN f.result_code = 'N' THEN 1 ELSE 0 END) AS losses,
           SUM(f.goals_for)                                  AS goals_for,
           SUM(f.goals_against)                              AS goals_against,
           SUM(f.goals_for) - SUM(f.goals_against)           AS goal_diff,
           SUM(f.points)                                     AS points
    FROM dwh.fact_team_match AS f
    WHERE f.is_finished = 1
    GROUP BY f.season_key, f.team_key
)
SELECT a.season_key,
       s.season_label,
       s.season_status,
       a.team_key,
       t.team_name,
       RANK() OVER (PARTITION BY a.season_key
                    ORDER BY a.points DESC, a.goal_diff DESC, a.goals_for DESC) AS table_rank,
       a.played, a.wins, a.draws, a.losses,
       a.goals_for, a.goals_against, a.goal_diff, a.points
FROM agg AS a
JOIN dwh.dim_team   AS t ON t.team_key   = a.team_key
JOIN dwh.dim_season AS s ON s.season_key = a.season_key;
GO

-- Form: Punkte der letzten 5 Spiele (gleitend, je Team und Saison)
CREATE OR ALTER VIEW dwh.v_team_form AS
SELECT f.season_key,
       f.team_key,
       f.match_id,
       f.match_datetime,
       f.points,
       SUM(f.points) OVER (PARTITION BY f.season_key, f.team_key
                           ORDER BY f.match_datetime
                           ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS points_last5,
       COUNT(*)      OVER (PARTITION BY f.season_key, f.team_key
                           ORDER BY f.match_datetime
                           ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS matches_in_window
FROM dwh.fact_team_match AS f
WHERE f.is_finished = 1
  AND f.points IS NOT NULL;
GO
