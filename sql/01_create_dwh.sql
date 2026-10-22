USE msv_dwh;
GO

-- Neu aufbaubar: erst Fakten, dann Dimensionen
DROP TABLE IF EXISTS dwh.fact_goal;
DROP TABLE IF EXISTS dwh.fact_team_match;
DROP TABLE IF EXISTS dwh.dim_team;
DROP TABLE IF EXISTS dwh.dim_season;
DROP TABLE IF EXISTS dwh.dim_date;
GO

CREATE TABLE dwh.dim_date (
    date_key      INT          NOT NULL PRIMARY KEY,  -- yyyymmdd
    full_date     DATE         NOT NULL UNIQUE,
    year_number   SMALLINT     NOT NULL,
    month_number  TINYINT      NOT NULL,
    month_name    NVARCHAR(10) NOT NULL,
    day_of_month  TINYINT      NOT NULL,
    iso_weekday   TINYINT      NOT NULL,              -- 1 = Montag ... 7 = Sonntag
    weekday_name  NVARCHAR(12) NOT NULL,
    is_weekend    BIT          NOT NULL
);

CREATE TABLE dwh.dim_season (
    season_key       INT          NOT NULL PRIMARY KEY, -- Startjahr, z. B. 2025
    season_label     NVARCHAR(9)  NOT NULL,             -- z. B. 2025/26
    league_shortcut  NVARCHAR(10) NOT NULL,
    matches_total    INT          NOT NULL,
    matches_finished INT          NOT NULL,
    season_status    NVARCHAR(20) NOT NULL              -- abgeschlossen / laufend / unvollständig
);

CREATE TABLE dwh.dim_team (
    team_key      INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    team_id       INT           NOT NULL UNIQUE,        -- Business Key aus OpenLigaDB
    team_name     NVARCHAR(100) NOT NULL,
    is_focus_team BIT           NOT NULL DEFAULT 0      -- 1 = MSV Duisburg
);

CREATE TABLE dwh.fact_team_match (
    match_id               INT          NOT NULL,       -- degenerierte Dimension
    team_key               INT          NOT NULL REFERENCES dwh.dim_team(team_key),
    opponent_key           INT          NOT NULL REFERENCES dwh.dim_team(team_key),
    season_key             INT          NOT NULL REFERENCES dwh.dim_season(season_key),
    date_key               INT          NOT NULL REFERENCES dwh.dim_date(date_key),
    matchday               TINYINT      NOT NULL,
    match_datetime         DATETIME2(0) NOT NULL,
    is_home                BIT          NOT NULL,
    is_finished            BIT          NOT NULL,
    goals_for              TINYINT      NULL,
    goals_against          TINYINT      NULL,
    halftime_goals_for     TINYINT      NULL,
    halftime_goals_against TINYINT      NULL,
    points                 TINYINT      NULL,
    result_code            CHAR(1)      NULL,           -- S / U / N
    CONSTRAINT pk_fact_team_match PRIMARY KEY (match_id, team_key)
);

CREATE TABLE dwh.fact_goal (
    goal_id            INT           NOT NULL PRIMARY KEY,
    match_id           INT           NOT NULL,
    season_key         INT           NOT NULL REFERENCES dwh.dim_season(season_key),
    date_key           INT           NOT NULL REFERENCES dwh.dim_date(date_key),
    scoring_team_key   INT           NOT NULL REFERENCES dwh.dim_team(team_key),
    conceding_team_key INT           NOT NULL REFERENCES dwh.dim_team(team_key),
    scorer_name        NVARCHAR(100) NULL,
    match_minute       SMALLINT      NULL,
    is_home_team       BIT           NOT NULL,
    is_penalty         BIT           NOT NULL,
    is_own_goal        BIT           NOT NULL,
    is_overtime        BIT           NOT NULL
);
GO