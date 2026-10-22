"""Tests fuer die Transformationslogik (ohne Datenbank, ohne Internet).

Ausfuehren:  pip install pytest   und dann   pytest
"""
import pandas as pd

from transform import dedupe_matches, flatten, result_points, to_frames


def make_match(match_id=1, team1=(107, "MSV Duisburg"), team2=(184, "VfB Stuttgart II"),
               last_update="2025-08-02T19:13:17.817", results=None, goals=None, finished=True):
    return {
        "matchID": match_id,
        "matchDateTime": "2025-08-02T16:30:00",
        "leagueSeason": 2025,
        "leagueShortcut": "bl3",
        "group": {"groupOrderID": 1},
        "team1": {"teamId": team1[0], "teamName": team1[1]},
        "team2": {"teamId": team2[0], "teamName": team2[1]},
        "lastUpdateDateTime": last_update,
        "matchIsFinished": finished,
        "matchResults": results if results is not None else [
            {"resultOrderID": 1, "resultTypeID": 1, "pointsTeam1": 0, "pointsTeam2": 0},
            {"resultOrderID": 2, "resultTypeID": 2, "pointsTeam1": 2, "pointsTeam2": 1},
        ],
        "goals": goals if goals is not None else [],
        "location": None,
        "numberOfViewers": None,
    }


def test_result_points_halftime_and_final():
    assert result_points(make_match()) == (0, 0, 2, 1)


def test_result_points_without_final_result():
    only_halftime = [{"resultOrderID": 1, "resultTypeID": 1, "pointsTeam1": 1, "pointsTeam2": 0}]
    assert result_points(make_match(results=only_halftime, finished=False)) == (1, 0, None, None)


def test_result_points_without_any_result():
    assert result_points(make_match(results=[])) == (None, None, None, None)


def test_unknown_scorer_becomes_none():
    goal = {"goalID": 10, "scoreTeam1": 1, "scoreTeam2": 0, "matchMinute": None,
            "goalGetterID": 0, "goalGetterName": "", "scoringTeamId": 107,
            "isPenalty": False, "isOwnGoal": False, "isOvertime": False}
    _, goal_rows = flatten([make_match(goals=[goal])])
    assert goal_rows[0]["scorer_id"] is None
    assert goal_rows[0]["scorer_name"] is None
    assert goal_rows[0]["match_minute"] is None


def test_mixed_timestamp_formats_are_parsed():
    # Regression: die API liefert Zeitstempel mal mit, mal ohne Millisekunden.
    matches = [
        make_match(match_id=1, last_update="2025-08-02T19:13:17.817"),
        make_match(match_id=2, last_update="2025-08-02T19:13:17"),
    ]
    df_match, _ = to_frames(matches)
    assert pd.api.types.is_datetime64_any_dtype(df_match["last_update"])
    assert df_match["last_update"].notna().all()


def test_dedupe_keeps_latest_version():
    old = make_match(match_id=5, last_update="2025-08-01T10:00:00")
    new = make_match(match_id=5, last_update="2025-08-02T10:00:00",
                     results=[{"resultOrderID": 2, "resultTypeID": 2, "pointsTeam1": 3, "pointsTeam2": 3}])
    kept = dedupe_matches([old, new])
    assert len(kept) == 1
    assert kept[0]["lastUpdateDateTime"] == "2025-08-02T10:00:00"


def test_placeholder_match_is_kept_in_staging():
    # Platzhalter (team_id 0) werden NICHT im Python entfernt, sondern in stg.v_match_valid.
    placeholder = make_match(match_id=67822, team1=(0, None), team2=(0, None))
    df_match, _ = to_frames([placeholder])
    assert len(df_match) == 1
    assert df_match.loc[0, "team1_id"] == 0
    assert pd.isna(df_match.loc[0, "team1_name"])


def test_empty_input_gives_empty_frames_with_columns():
    df_match, df_goal = to_frames([])
    assert df_match.empty and df_goal.empty
    assert "match_id" in df_match.columns and "goal_id" in df_goal.columns
