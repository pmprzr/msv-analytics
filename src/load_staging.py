"""Load (Staging): liest data/raw/*.json und schreibt stg.match und stg.goal.

Die Staging-Tabellen werden in sql/01_create_tables.sql angelegt. Dieses Skript
leert sie bei jedem Lauf und befuellt sie neu (idempotent, in einer Transaktion).
"""
import json
import sys
from datetime import datetime

from sqlalchemy import text

from config import RAW_DIR
from db import get_engine
from transform import to_frames


def main() -> None:
    files = sorted(RAW_DIR.glob("*.json"))
    if not files:
        sys.exit(f"Keine Rohdaten in {RAW_DIR}. Erst 'python src/extract.py' ausfuehren.")

    matches: list[dict] = []
    for path in files:
        matches += json.loads(path.read_text(encoding="utf-8"))

    df_match, df_goal = to_frames(matches)
    load_ts = datetime.now()
    df_match["load_ts"] = load_ts
    df_goal["load_ts"] = load_ts

    engine = get_engine()
    with engine.begin() as conn:  # alles oder nichts
        conn.execute(text("DELETE FROM stg.goal"))
        conn.execute(text("DELETE FROM stg.match"))
        df_match.to_sql("match", conn, schema="stg", if_exists="append", index=False)
        df_goal.to_sql("goal", conn, schema="stg", if_exists="append", index=False)

    print(f"stg.match: {len(df_match)} Zeilen, stg.goal: {len(df_goal)} Zeilen")


if __name__ == "__main__":
    main()
