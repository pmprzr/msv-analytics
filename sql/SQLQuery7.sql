USE msv_dwh;
GO

CREATE OR ALTER PROCEDURE dwh.usp_load_dim_team
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH t AS (
        SELECT team1_id AS team_id, team1_name AS team_name, match_datetime
        FROM stg.match WHERE team1_id IS NOT NULL
        UNION ALL
        SELECT team2_id, team2_name, match_datetime
        FROM stg.match WHERE team2_id IS NOT NULL
    ),
    latest AS (  -- aktuellster Name, Zeilen mit leerem Namen kommen zuletzt
        SELECT team_id, team_name,
               ROW_NUMBER() OVER (
                   PARTITION BY team_id
                   ORDER BY CASE WHEN NULLIF(LTRIM(RTRIM(team_name)), N'') IS NULL THEN 1 ELSE 0 END,
                            match_datetime DESC
               ) AS rn
        FROM t
    )
    MERGE dwh.dim_team AS tgt
    USING (
        SELECT team_id,
               COALESCE(NULLIF(LTRIM(RTRIM(team_name)), N''),
                        CONCAT(N'Unbekannt (', team_id, N')')) AS team_name
        FROM latest
        WHERE rn = 1
    ) AS src
        ON tgt.team_id = src.team_id
    WHEN MATCHED AND tgt.team_name <> src.team_name THEN
        UPDATE SET tgt.team_name = src.team_name
    WHEN NOT MATCHED THEN
        INSERT (team_id, team_name, is_focus_team)
        VALUES (src.team_id, src.team_name, CASE WHEN src.team_id = 107 THEN 1 ELSE 0 END);
END;
GO

EXEC dwh.usp_load_dwh;




USE msv_dwh;

-- A: kommt eine match_id mehrfach in stg.match vor?
SELECT match_id, COUNT(*) AS anzahl
FROM stg.match
GROUP BY match_id
HAVING COUNT(*) > 1;

-- B: spielt ein Team "gegen sich selbst"?
SELECT match_id, league_season, matchday, team1_id, team1_name, team2_id, team2_name
FROM stg.match
WHERE team1_id = team2_id;

-- C: das konkrete Spiel
SELECT match_id, league_season, matchday, match_datetime,
       team1_id, team1_name, team2_id, team2_name, last_update
FROM stg.match
WHERE match_id = 67822;