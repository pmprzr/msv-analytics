-- ============================================================================
-- 04_checks.sql  (Datenbank: msv_dwh)
-- Datenqualitaets-Checks und Abstimmung. Wird am Ende der Pipeline ausgefuehrt,
-- laesst sich aber auch einzeln starten: python src/db.py sql/04_checks.sql
-- Jeder Block beginnt mit einem Kommentar, der als Ueberschrift ausgegeben wird.
-- ============================================================================
GO

-- 1. Zeilen pro Tabelle
SELECT 'stg.match' AS tabelle, COUNT(*) AS zeilen FROM stg.match
UNION ALL SELECT 'stg.goal',             COUNT(*) FROM stg.goal
UNION ALL SELECT 'dwh.dim_date',         COUNT(*) FROM dwh.dim_date
UNION ALL SELECT 'dwh.dim_season',       COUNT(*) FROM dwh.dim_season
UNION ALL SELECT 'dwh.dim_team',         COUNT(*) FROM dwh.dim_team
UNION ALL SELECT 'dwh.fact_team_match',  COUNT(*) FROM dwh.fact_team_match
UNION ALL SELECT 'dwh.fact_goal',        COUNT(*) FROM dwh.fact_goal;
GO

-- 2. Saisons und ihr Status (unvollständig = weniger Spiele als n * (n - 1))
SELECT season_label, season_status, matches_total, matches_finished
FROM dwh.dim_season
ORDER BY season_key;
GO

-- 3. Abstimmung Staging <-> DWH (beide Differenzen muessen 0 sein)
SELECT
    (SELECT COUNT(*) FROM stg.v_match_valid) * 2
        - (SELECT COUNT(*) FROM dwh.fact_team_match) AS diff_team_match,
    (SELECT COUNT(*) FROM stg.goal AS g JOIN stg.v_match_valid AS m ON m.match_id = g.match_id)
        - (SELECT COUNT(*) FROM dwh.fact_goal)       AS diff_goal;
GO

-- 4. Bewusst abgelehnte Spiele (keine zwei echten Teams, kein Datum o. ae.)
SELECT m.match_id, m.league_season, m.matchday, m.match_datetime, m.team1_id, m.team2_id
FROM stg.match AS m
WHERE NOT EXISTS (SELECT 1 FROM stg.v_match_valid AS v WHERE v.match_id = m.match_id);
GO

-- 5. Spiele mit Datum ausserhalb ihrer Saison (Saison beginnt im Juli)
SELECT match_id, league_season, match_datetime
FROM stg.v_match_valid
WHERE YEAR(match_datetime) - CASE WHEN MONTH(match_datetime) < 7 THEN 1 ELSE 0 END <> league_season;
GO

-- 6. Beendete Spiele, bei denen Torliste und Endergebnis nicht zusammenpassen (je Saison)
SELECT x.league_season, COUNT(*) AS spiele_mit_abweichung
FROM (
    SELECT m.match_id, m.league_season,
           m.final_goals_team1 + m.final_goals_team2 AS tore_ergebnis,
           COUNT(g.goal_id)                           AS tore_detail
    FROM stg.v_match_valid AS m
    LEFT JOIN stg.goal AS g ON g.match_id = m.match_id
    WHERE m.is_finished = 1
    GROUP BY m.match_id, m.league_season, m.final_goals_team1, m.final_goals_team2
) AS x
WHERE x.tore_ergebnis <> x.tore_detail
GROUP BY x.league_season
ORDER BY x.league_season;
GO

-- 7. Tabelle 2025/26 (mit einer oeffentlichen Tabelle, z. B. kicker oder Wikipedia, abgleichen)
SELECT table_rank, team_name, played, wins, draws, losses, goals_for, goals_against, goal_diff, points
FROM dwh.v_season_table
WHERE season_key = 2025
ORDER BY table_rank;
GO

-- 8. MSV Duisburg: Heim vs. Auswaerts je Saison
SELECT s.season_label,
       CASE WHEN f.is_home = 1 THEN N'Heim' ELSE N'Auswärts' END AS ort,
       COUNT(*)                                  AS spiele,
       SUM(f.points)                             AS punkte,
       CAST(AVG(f.points * 1.0) AS DECIMAL(4,2)) AS punkte_pro_spiel
FROM dwh.fact_team_match AS f
JOIN dwh.dim_team   AS t ON t.team_key   = f.team_key
JOIN dwh.dim_season AS s ON s.season_key = f.season_key
WHERE t.is_focus_team = 1 AND f.is_finished = 1
GROUP BY s.season_label, f.is_home
ORDER BY s.season_label, f.is_home DESC;
GO
