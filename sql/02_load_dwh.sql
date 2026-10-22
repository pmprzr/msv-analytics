-- ============================================================================
-- 02_load_dwh.sql  (Datenbank: msv_dwh)
-- Alle Ladeprozeduren: stg (Staging) -> dwh (Sternschema).
-- Die Hauptprozedur dwh.usp_load_dwh ruft die anderen in der richtigen Reihenfolge
-- auf, in einer Transaktion: entweder wird alles geladen oder (bei Fehler) nichts.
--
--   usp_load_dim_date         Kalender 2020-2030 (einmalig)
--   usp_load_dim_season       Saisons inkl. Status (abgeschlossen / laufend / unvollständig)
--   usp_load_dim_team         Teams (aktuellster Name je team_id)
--   usp_load_fact_team_match  zwei Zeilen pro Spiel (eine je Team-Sicht)
--   usp_load_fact_goal        eine Zeile pro Tor
--   usp_load_dwh              Hauptprozedur
--
-- Alle Prozeduren lesen aus stg.v_match_valid (nur Spiele mit zwei echten Teams).
-- ============================================================================

CREATE OR ALTER PROCEDURE dwh.usp_load_dim_date
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dwh.dim_date) RETURN;  -- nur beim ersten Mal befuellen

    ;WITH n AS (
        SELECT 0 AS i
        UNION ALL
        SELECT i + 1 FROM n WHERE i < 4017          -- 2020-01-01 bis 2030-12-31
    ),
    d AS (
        SELECT DATEADD(DAY, i, CAST('2020-01-01' AS DATE)) AS full_date FROM n
    )
    INSERT INTO dwh.dim_date
        (date_key, full_date, year_number, month_number, month_name,
         day_of_month, iso_weekday, weekday_name, is_weekend)
    SELECT
        YEAR(full_date) * 10000 + MONTH(full_date) * 100 + DAY(full_date),
        full_date,
        YEAR(full_date),
        MONTH(full_date),
        CHOOSE(MONTH(full_date), N'Januar', N'Februar', N'März', N'April', N'Mai', N'Juni',
               N'Juli', N'August', N'September', N'Oktober', N'November', N'Dezember'),
        DAY(full_date),
        w.iso,
        CHOOSE(w.iso, N'Montag', N'Dienstag', N'Mittwoch', N'Donnerstag',
               N'Freitag', N'Samstag', N'Sonntag'),
        CASE WHEN w.iso >= 6 THEN 1 ELSE 0 END
    FROM d
    CROSS APPLY (SELECT (DATEDIFF(DAY, '19000101', d.full_date) % 7) + 1 AS iso) AS w  -- 1900-01-01 war ein Montag
    OPTION (MAXRECURSION 0);
END;
GO

CREATE OR ALTER PROCEDURE dwh.usp_load_dim_season
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH teams AS (
        SELECT league_season, team1_id AS team_id FROM stg.v_match_valid
        UNION
        SELECT league_season, team2_id FROM stg.v_match_valid
    ),
    team_cnt AS (
        SELECT league_season, COUNT(*) AS n_teams
        FROM teams
        GROUP BY league_season
    ),
    m AS (
        SELECT league_shortcut, league_season,
               COUNT(*) AS matches_total,
               SUM(CASE WHEN is_finished = 1 THEN 1 ELSE 0 END) AS matches_finished,
               SUM(CASE WHEN is_finished = 0 AND match_datetime > SYSDATETIME() THEN 1 ELSE 0 END) AS matches_upcoming
        FROM stg.v_match_valid
        GROUP BY league_shortcut, league_season
    )
    MERGE dwh.dim_season AS tgt
    USING (
        SELECT CAST(m.league_season AS INT) AS season_key,
               CONCAT(m.league_season, N'/', RIGHT(CAST(m.league_season + 1 AS NVARCHAR(4)), 2)) AS season_label,
               m.league_shortcut,
               m.matches_total,
               m.matches_finished,
               CASE WHEN m.matches_total < c.n_teams * (c.n_teams - 1) THEN N'unvollständig'
                    WHEN m.matches_finished = m.matches_total          THEN N'abgeschlossen'
                    WHEN m.matches_upcoming > 0                        THEN N'laufend'
                    ELSE N'unvollständig' END AS season_status
        FROM m
        JOIN team_cnt AS c ON c.league_season = m.league_season
    ) AS src
        ON tgt.season_key = src.season_key
    WHEN MATCHED THEN UPDATE SET
        tgt.season_label     = src.season_label,
        tgt.league_shortcut  = src.league_shortcut,
        tgt.matches_total    = src.matches_total,
        tgt.matches_finished = src.matches_finished,
        tgt.season_status    = src.season_status
    WHEN NOT MATCHED THEN INSERT
        (season_key, season_label, league_shortcut, matches_total, matches_finished, season_status)
        VALUES (src.season_key, src.season_label, src.league_shortcut,
                src.matches_total, src.matches_finished, src.season_status);
END;
GO

CREATE OR ALTER PROCEDURE dwh.usp_load_dim_team
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH t AS (
        SELECT team1_id AS team_id, team1_name AS team_name, match_datetime FROM stg.v_match_valid
        UNION ALL
        SELECT team2_id, team2_name, match_datetime FROM stg.v_match_valid
    ),
    latest AS (  -- aktuellster Name je Team; Zeilen mit leerem Namen kommen zuletzt
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
        VALUES (src.team_id, src.team_name, CASE WHEN src.team_id = 107 THEN 1 ELSE 0 END);  -- 107 = MSV Duisburg
END;
GO

CREATE OR ALTER PROCEDURE dwh.usp_load_fact_team_match
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dwh.fact_team_match;

    INSERT INTO dwh.fact_team_match
        (match_id, team_key, opponent_key, season_key, date_key, matchday, match_datetime,
         is_home, is_finished, goals_for, goals_against,
         halftime_goals_for, halftime_goals_against, points, result_code)
    SELECT
        m.match_id,
        t.team_key,
        o.team_key,
        CAST(m.league_season AS INT),
        YEAR(m.match_datetime) * 10000 + MONTH(m.match_datetime) * 100 + DAY(m.match_datetime),
        CAST(m.matchday AS TINYINT),
        CAST(m.match_datetime AS DATETIME2(0)),
        p.is_home,
        m.is_finished,
        CAST(p.goals_for AS TINYINT),
        CAST(p.goals_against AS TINYINT),
        CAST(p.ht_for AS TINYINT),
        CAST(p.ht_against AS TINYINT),
        CASE WHEN m.is_finished = 0 OR p.goals_for IS NULL OR p.goals_against IS NULL THEN NULL
             WHEN p.goals_for > p.goals_against THEN 3
             WHEN p.goals_for = p.goals_against THEN 1
             ELSE 0 END,
        CASE WHEN m.is_finished = 0 OR p.goals_for IS NULL OR p.goals_against IS NULL THEN NULL
             WHEN p.goals_for > p.goals_against THEN 'S'
             WHEN p.goals_for = p.goals_against THEN 'U'
             ELSE 'N' END
    FROM stg.v_match_valid AS m
    CROSS APPLY (VALUES   -- jedes Spiel wird in zwei Team-Perspektiven aufgeteilt
        (m.team1_id, m.team2_id, 1, m.final_goals_team1, m.final_goals_team2,
         m.halftime_goals_team1, m.halftime_goals_team2),
        (m.team2_id, m.team1_id, 0, m.final_goals_team2, m.final_goals_team1,
         m.halftime_goals_team2, m.halftime_goals_team1)
    ) AS p (team_id, opp_id, is_home, goals_for, goals_against, ht_for, ht_against)
    JOIN dwh.dim_team AS t ON t.team_id = p.team_id
    JOIN dwh.dim_team AS o ON o.team_id = p.opp_id;
END;
GO

CREATE OR ALTER PROCEDURE dwh.usp_load_fact_goal
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dwh.fact_goal;

    INSERT INTO dwh.fact_goal
        (goal_id, match_id, season_key, date_key, scoring_team_key, conceding_team_key,
         scorer_name, match_minute, is_home_team, is_penalty, is_own_goal, is_overtime)
    SELECT
        g.goal_id,
        g.match_id,
        CAST(m.league_season AS INT),
        YEAR(m.match_datetime) * 10000 + MONTH(m.match_datetime) * 100 + DAY(m.match_datetime),
        st.team_key,
        ct.team_key,
        LEFT(g.scorer_name, 200),
        CAST(g.match_minute AS SMALLINT),
        CASE WHEN g.scoring_team_id = m.team1_id THEN 1 ELSE 0 END,
        ISNULL(g.is_penalty, 0),
        ISNULL(g.is_own_goal, 0),
        ISNULL(g.is_overtime, 0)
    FROM stg.goal AS g
    JOIN stg.v_match_valid AS m ON m.match_id = g.match_id
    JOIN dwh.dim_team AS st ON st.team_id = g.scoring_team_id
    JOIN dwh.dim_team AS ct
      ON ct.team_id = CASE WHEN g.scoring_team_id = m.team1_id THEN m.team2_id ELSE m.team1_id END;
END;
GO

-- Hauptprozedur: alles in einer Transaktion, bei Fehler Rollback
CREATE OR ALTER PROCEDURE dwh.usp_load_dwh
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dwh.usp_load_dim_date;
        EXEC dwh.usp_load_dim_season;
        EXEC dwh.usp_load_dim_team;
        EXEC dwh.usp_load_fact_team_match;
        EXEC dwh.usp_load_fact_goal;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
