"""Transform: macht aus den verschachtelten API-Antworten zwei flache Tabellen.

Die Datei kennt keine Datenbank und ist deshalb gut testbar (siehe tests/).
Bewusst keine fachliche Logik (Punkte, Heim/Auswaerts ...): die entsteht erst
im Data Warehouse (sql/02_load_dwh.sql). Das Staging bleibt nah an der Quelle.
"""
import pandas as pd

MATCH_COLUMNS = [
    "match_id", "league_shortcut", "league_season", "matchday", "match_datetime",
    "is_finished", "team1_id", "team1_name", "team2_id", "team2_name",
    "halftime_goals_team1", "halftime_goals_team2",
    "final_goals_team1", "final_goals_team2",
    "stadium", "number_of_viewers", "last_update",
]
GOAL_COLUMNS = [
    "goal_id", "match_id", "score_team1", "score_team2", "match_minute",
    "scorer_id", "scorer_name", "scoring_team_id",
    "is_penalty", "is_own_goal", "is_overtime",
]
_MATCH_INT_COLUMNS = [
    "match_id", "league_season", "matchday", "team1_id", "team2_id",
    "halftime_goals_team1", "halftime_goals_team2",
    "final_goals_team1", "final_goals_team2", "number_of_viewers",
]
_GOAL_INT_COLUMNS = [
    "goal_id", "match_id", "score_team1", "score_team2",
    "match_minute", "scorer_id", "scoring_team_id",
]


def result_points(match: dict) -> tuple:
    """Halbzeit- und Endstand (jeweils Team 1, Team 2). Fehlt ein Wert, ist er None."""
    results = match.get("matchResults") or []

    # Zuordnung ueber resultTypeID (1 = Halbzeit, 2 = Endergebnis nach 90 Minuten).
    # NICHT ueber resultOrderID: aeltere Saisons liefern das Endergebnis mit Order 1
    # und die Halbzeit mit Order 2, neuere Saisons umgekehrt.
    half = next((r for r in results if r.get("resultTypeID") == 1), None)
    final = next((r for r in results if r.get("resultTypeID") == 2), None)
    
    return (
        half["pointsTeam1"] if half else None,
        half["pointsTeam2"] if half else None,
        final["pointsTeam1"] if final else None,
        final["pointsTeam2"] if final else None,
    )


def dedupe_matches(matches: list[dict]) -> list[dict]:
    """Falls dasselbe Spiel mehrfach vorkommt, bleibt die zuletzt aktualisierte Version."""
    latest: dict = {}
    for match in matches:
        key = match["matchID"]
        stamp = match.get("lastUpdateDateTime") or ""
        if key not in latest or stamp >= (latest[key].get("lastUpdateDateTime") or ""):
            latest[key] = match
    return list(latest.values())


def flatten(matches: list[dict]) -> tuple[list[dict], list[dict]]:
    match_rows, goal_rows = [], []
    for m in matches:
        h1, h2, f1, f2 = result_points(m)
        team1, team2 = m.get("team1") or {}, m.get("team2") or {}
        location = m.get("location") or {}
        match_rows.append({
            "match_id": m["matchID"],
            "league_shortcut": m.get("leagueShortcut"),
            "league_season": m.get("leagueSeason"),
            "matchday": (m.get("group") or {}).get("groupOrderID"),
            "match_datetime": m.get("matchDateTime"),
            "is_finished": bool(m.get("matchIsFinished")),
            "team1_id": team1.get("teamId"),
            "team1_name": team1.get("teamName"),
            "team2_id": team2.get("teamId"),
            "team2_name": team2.get("teamName"),
            "halftime_goals_team1": h1,
            "halftime_goals_team2": h2,
            "final_goals_team1": f1,
            "final_goals_team2": f2,
            "stadium": location.get("locationStadium"),
            "number_of_viewers": m.get("numberOfViewers"),
            "last_update": m.get("lastUpdateDateTime"),
        })
        for g in m.get("goals") or []:
            goal_rows.append({
                "goal_id": g["goalID"],
                "match_id": m["matchID"],
                "score_team1": g.get("scoreTeam1"),
                "score_team2": g.get("scoreTeam2"),
                "match_minute": g.get("matchMinute"),
                "scorer_id": g.get("goalGetterID") or None,      # 0 = unbekannt
                "scorer_name": g.get("goalGetterName") or None,  # "" = unbekannt
                "scoring_team_id": g.get("scoringTeamId"),
                "is_penalty": bool(g.get("isPenalty")),
                "is_own_goal": bool(g.get("isOwnGoal")),
                "is_overtime": bool(g.get("isOvertime")),
            })
    return match_rows, goal_rows


def to_frames(matches: list[dict]) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Rohspiele -> (Spiele-Tabelle, Tore-Tabelle) mit sauberen Datentypen."""
    match_rows, goal_rows = flatten(dedupe_matches(matches))
    df_match = pd.DataFrame(match_rows, columns=MATCH_COLUMNS)
    df_goal = pd.DataFrame(goal_rows, columns=GOAL_COLUMNS)

    # Die API liefert Zeitstempel mal mit, mal ohne Millisekunden -> ISO8601 akzeptiert beides.
    df_match["match_datetime"] = pd.to_datetime(df_match["match_datetime"], format="ISO8601")
    df_match["last_update"] = pd.to_datetime(df_match["last_update"], format="ISO8601")

    for col in _MATCH_INT_COLUMNS:
        df_match[col] = df_match[col].astype("Int64")
    for col in _GOAL_INT_COLUMNS:
        df_goal[col] = df_goal[col].astype("Int64")

    df_goal = df_goal.drop_duplicates(subset="goal_id", keep="last")
    return df_match, df_goal
