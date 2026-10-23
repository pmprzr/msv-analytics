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
-- Tabellenplatz nach jedem Spieltag (kumulierte Punkte je Team und Saison, danach RANK)
-- Hinweis: Spieltag = matchday der Quelle. Verlegte Spiele zaehlen zu ihrem urspruenglichen Spieltag.
CREATE OR ALTER VIEW dwh.v_rank_by_matchday AS
WITH cum AS (
    SELECT f.season_key,
           f.team_key,
           f.matchday,
           SUM(CAST(f.points AS INT))
               OVER (PARTITION BY f.season_key, f.team_key
                     ORDER BY f.matchday ROWS UNBOUNDED PRECEDING) AS points_cum,
           SUM(CAST(f.goals_for AS INT) - CAST(f.goals_against AS INT))
               OVER (PARTITION BY f.season_key, f.team_key
                     ORDER BY f.matchday ROWS UNBOUNDED PRECEDING) AS goal_diff_cum,
           SUM(CAST(f.goals_for AS INT))
               OVER (PARTITION BY f.season_key, f.team_key
                     ORDER BY f.matchday ROWS UNBOUNDED PRECEDING) AS goals_for_cum
    FROM dwh.fact_team_match AS f
    WHERE f.is_finished = 1
      AND f.points IS NOT NULL
)
SELECT season_key,
       team_key,
       matchday,
       points_cum,
       goal_diff_cum,
       goals_for_cum,
       RANK() OVER (PARTITION BY season_key, matchday
                    ORDER BY points_cum DESC, goal_diff_cum DESC, goals_for_cum DESC) AS table_rank
FROM cum;
GO