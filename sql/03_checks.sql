USE msv_dwh;

-- 1. Saisons und ihr Status (2022 sollte "unvollständig" sein)
SELECT * FROM dwh.dim_season ORDER BY season_key;

-- 2. Abstimmung Staging <-> DWH (Differenz muss 0 sein, sonst gingen Zeilen verloren)
SELECT
    (SELECT COUNT(*) FROM stg.match) * 2 - (SELECT COUNT(*) FROM dwh.fact_team_match) AS diff_team_match,
    (SELECT COUNT(*) FROM stg.goal)        - (SELECT COUNT(*) FROM dwh.fact_goal)       AS diff_goal;

-- 3. Datenqualität: Spiele, bei denen Torliste und Endergebnis nicht zusammenpassen
SELECT x.league_season, COUNT(*) AS spiele_mit_abweichung
FROM (
    SELECT m.match_id, m.league_season,
           m.final_goals_team1 + m.final_goals_team2 AS tore_ergebnis,
           COUNT(g.goal_id)                           AS tore_detail
    FROM stg.match AS m
    LEFT JOIN stg.goal AS g ON g.match_id = m.match_id
    WHERE m.is_finished = 1
    GROUP BY m.match_id, m.league_season, m.final_goals_team1, m.final_goals_team2
) AS x
WHERE x.tore_ergebnis <> x.tore_detail
GROUP BY x.league_season
ORDER BY x.league_season;

-- 4. Tabelle einer abgeschlossenen Saison (mit der echten Tabelle vergleichen!)
SELECT t.team_name,
       COUNT(*)                          AS spiele,
       SUM(f.points)                     AS punkte,
       SUM(f.goals_for)                  AS tore,
       SUM(f.goals_against)              AS gegentore
FROM dwh.fact_team_match AS f
JOIN dwh.dim_team AS t ON t.team_key = f.team_key
WHERE f.season_key = 2025 AND f.is_finished = 1
GROUP BY t.team_name
ORDER BY punkte DESC, SUM(f.goals_for) - SUM(f.goals_against) DESC;

-- 5. MSV: Heim vs. Auswärts
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