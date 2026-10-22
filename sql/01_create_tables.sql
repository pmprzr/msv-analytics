-- ============================================================================
-- 01_create_tables.sql  (Datenbank: msv_dwh)
-- Legt Schemata und Tabellen an. ACHTUNG: Bestehende Tabellen werden geloescht
-- und neu erstellt (Full Rebuild). Die Daten kommen danach per Pipeline wieder.
--
--   stg = Staging: Rohdaten 1:1 aus der API, kaum bearbeitet
--   dwh = Data Warehouse: Sternschema fuer die Auswertung (Power BI)
-- ============================================================================

IF SCHEMA_ID(N'stg') IS NULL EXEC(N'CREATE SCHEMA stg');
IF SCHEMA_ID(N'dwh') IS NULL EXEC(N'CREATE SCHEMA dwh');
GO

-- Alles in der richtigen Reihenfolge loeschen (erst Fakten, dann Dimensionen)
DROP TABLE IF EXISTS dwh.fact_goal;
DROP TABLE IF EXISTS dwh.fact_team_match;
DROP TABLE IF EXISTS dwh.dim_team;
DROP TABLE IF EXISTS dwh.dim_season;
DROP TABLE IF EXISTS dwh.dim_date;
DROP TABLE IF EXISTS stg.goal;
DROP TABLE IF EXISTS stg.match;
GO

-- ---------------------------------------------------------------------------
-- Staging
-- ---------------------------------------------------------------------------
CREATE TABLE stg.match (
    match_id              INT           NOT NULL,
    league_shortcut       NVARCHAR(10)  NULL,
    league_season         INT           NOT NULL,
    matchday              INT           NULL,
    match_datetime        DATETIME2     NULL,
    is_finished           BIT           NOT NULL,
    team1_id              INT           NULL,
    team1_name            NVARCHAR(200) NULL,
    team2_id              INT           NULL,
    team2_name            NVARCHAR(200) NULL,
    halftime_goals_team1  INT           NULL,
    halftime_goals_team2  INT           NULL,
    final_goals_team1     INT           NULL,
    final_goals_team2     INT           NULL,
    stadium               NVARCHAR(200) NULL,
    number_of_viewers     INT           NULL,
    last_update           DATETIME2     NULL,
    load_ts               DATETIME2     NOT NULL
);

CREATE TABLE stg.goal (
    goal_id          INT           NOT NULL,
    match_id         INT           NOT NULL,
    score_team1      INT           NULL,
    score_team2      INT           NULL,
    match_minute     INT           NULL,
    scorer_id        INT           NULL,
    scorer_name      NVARCHAR(200) NULL,
    scoring_team_id  INT           NULL,
    is_penalty       BIT           NULL,
    is_own_goal      BIT           NULL,
    is_overtime      BIT           NULL,
    load_ts          DATETIME2     NOT NULL
);
GO

-- Geschaeftsregel: nur Spiele mit zwei echten, verschiedenen Teams gelangen ins DWH.
-- (Die API enthaelt vereinzelt Platzhalter-Spiele mit team_id = 0 und ohne Namen.)
-- stg.match bleibt unveraendert; abgelehnte Spiele zeigt sql/04_checks.sql.
CREATE OR ALTER VIEW stg.v_match_valid AS
SELECT *
FROM stg.match
WHERE team1_id > 0
  AND team2_id > 0
  AND team1_id <> team2_id
  AND match_datetime IS NOT NULL
  AND matchday IS NOT NULL;
GO

-- ---------------------------------------------------------------------------
-- Data Warehouse: Sternschema
-- ---------------------------------------------------------------------------
CREATE TABLE dwh.dim_date (
    date_key      INT          NOT NULL PRIMARY KEY,   -- yyyymmdd
    full_date     DATE         NOT NULL UNIQUE,
    year_number   SMALLINT     NOT NULL,
    month_number  TINYINT      NOT NULL,
    month_name    NVARCHAR(10) NOT NULL,
    day_of_month  TINYINT      NOT NULL,
    iso_weekday   TINYINT      NOT NULL,               -- 1 = Montag ... 7 = Sonntag
    weekday_name  NVARCHAR(12) NOT NULL,
    is_weekend    BIT          NOT NULL
);

CREATE TABLE dwh.dim_season (
    season_key        INT          NOT NULL PRIMARY KEY,  -- Startjahr, z. B. 2025
    season_label      NVARCHAR(9)  NOT NULL,              -- z. B. 2025/26
    league_shortcut   NVARCHAR(10) NOT NULL,
    matches_total     INT          NOT NULL,
    matches_finished  INT          NOT NULL,
    season_status     NVARCHAR(20) NOT NULL               -- abgeschlossen / laufend / unvollständig
);

CREATE TABLE dwh.dim_team (
    team_key       INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    team_id        INT           NOT NULL UNIQUE,         -- Business Key aus OpenLigaDB
    team_name      NVARCHAR(200) NOT NULL,
    is_focus_team  BIT           NOT NULL DEFAULT 0       -- 1 = MSV Duisburg
);

-- Grain: eine Zeile pro Team und Spiel (jedes Spiel erscheint zweimal, je Team-Sicht)
CREATE TABLE dwh.fact_team_match (
    match_id                INT          NOT NULL,        -- degenerierte Dimension
    team_key                INT          NOT NULL REFERENCES dwh.dim_team(team_key),
    opponent_key            INT          NOT NULL REFERENCES dwh.dim_team(team_key),
    season_key              INT          NOT NULL REFERENCES dwh.dim_season(season_key),
    date_key                INT          NOT NULL REFERENCES dwh.dim_date(date_key),
    matchday                TINYINT      NOT NULL,
    match_datetime          DATETIME2(0) NOT NULL,
    is_home                 BIT          NOT NULL,
    is_finished             BIT          NOT NULL,
    goals_for               TINYINT      NULL,
    goals_against           TINYINT      NULL,
    halftime_goals_for      TINYINT      NULL,
    halftime_goals_against  TINYINT      NULL,
    points                  TINYINT      NULL,
    result_code             CHAR(1)      NULL,            -- S = Sieg, U = Unentschieden, N = Niederlage
    CONSTRAINT pk_fact_team_match PRIMARY KEY (match_id, team_key)
);

-- Grain: eine Zeile pro Tor
CREATE TABLE dwh.fact_goal (
    goal_id             INT           NOT NULL PRIMARY KEY,
    match_id            INT           NOT NULL,
    season_key          INT           NOT NULL REFERENCES dwh.dim_season(season_key),
    date_key            INT           NOT NULL REFERENCES dwh.dim_date(date_key),
    scoring_team_key    INT           NOT NULL REFERENCES dwh.dim_team(team_key),
    conceding_team_key  INT           NOT NULL REFERENCES dwh.dim_team(team_key),
    scorer_name         NVARCHAR(200) NULL,
    match_minute        SMALLINT      NULL,
    is_home_team        BIT           NOT NULL,           -- 1 = Torschuetze spielt zuhause
    is_penalty          BIT           NOT NULL,
    is_own_goal         BIT           NOT NULL,
    is_overtime         BIT           NOT NULL            -- Nachspielzeit
);
GO
