
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