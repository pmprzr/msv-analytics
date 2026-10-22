-- Erstelle Datenbank -- 
CREATE DATABASE msv_dwh;
GO
USE msv_dwh;
GO
CREATE SCHEMA stg;
GO
CREATE SCHEMA dwh;
GO

-------------------------------------------------------
-- Überprüfung für initiale Datenimports über Python --
-------------------------------------------------------
USE msv_dwh;
-- Spiele pro Saison
SELECT league_season, COUNT(*) AS matches
FROM stg.match GROUP BY league_season ORDER BY league_season;

-- MSV-Spiele pro Saison
SELECT league_season, COUNT(*) AS msv_matches
FROM stg.match
WHERE team1_id = 107 OR team2_id = 107
GROUP BY league_season ORDER BY league_season;

-- Datenqualitaet: wie oft fehlen Zuschauer, Minute, Schuetze?
SELECT COUNT(*) AS matches, COUNT(number_of_viewers) AS with_viewers FROM stg.match;
SELECT COUNT(*) AS goals, COUNT(match_minute) AS with_minute, COUNT(scorer_name) AS with_scorer FROM stg.goal;



-- Datawarehouse erstelle und befüllen  --
EXEC dwh.usp_load_dwh;


USE msv_dwh;

SELECT league_season, matchday, match_id,
       team1_id, team1_name, team2_id, team2_name
FROM stg.match
WHERE team1_name IS NULL OR team2_name IS NULL
   OR team1_id   IS NULL OR team2_id   IS NULL
ORDER BY league_season, matchday;


