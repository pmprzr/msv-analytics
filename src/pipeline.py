"""Die komplette Pipeline in einem Befehl (Full Rebuild):

    python src/pipeline.py                  # alles: Datenbank, Extract, Staging, DWH, Checks
    python src/pipeline.py --skip-extract   # vorhandene Rohdaten in data/raw/ wiederverwenden
    python src/pipeline.py --seasons 2025 2026
"""
import argparse

import pyodbc

import extract
import load_staging
from config import SQL_DIR
from db import run_file, run_sql, wait_for_sql_server

TOTAL_STEPS = 7


def step(number: int, text: str) -> None:
    print(f"\n[{number}/{TOTAL_STEPS}] {text}")


def main() -> None:
    parser = argparse.ArgumentParser(description="MSV Analytics: komplette Pipeline")
    parser.add_argument("--skip-extract", action="store_true",
                        help="API nicht neu abrufen, vorhandene Dateien in data/raw/ nutzen")
    parser.add_argument("--seasons", nargs="*", type=int, help="Startjahre, z. B. 2025 2026")
    args = parser.parse_args()

    try:
        step(1, "Warte auf SQL Server ...")
        wait_for_sql_server()

        step(2, "Datenbank und Tabellen anlegen (sql/00, sql/01)")
        run_file(SQL_DIR / "00_create_database.sql", database="master", show_results=False)
        run_file(SQL_DIR / "01_create_tables.sql", show_results=False)

        step(3, "Ladeprozeduren und Views anlegen (sql/02, sql/03)")
        run_file(SQL_DIR / "02_load_dwh.sql", show_results=False)
        run_file(SQL_DIR / "03_views.sql", show_results=False)

        if args.skip_extract:
            step(4, "Extract uebersprungen (--skip-extract)")
        else:
            step(4, "Extract: Spieldaten von OpenLigaDB laden")
            extract.main(args.seasons)

        step(5, "Staging: JSON -> stg.match / stg.goal")
        load_staging.main()

        step(6, "Data Warehouse laden: EXEC dwh.usp_load_dwh")
        run_sql("EXEC dwh.usp_load_dwh;", show_results=False)

        step(7, "Datenqualitaets-Checks (sql/04_checks.sql)")
        run_file(SQL_DIR / "04_checks.sql")
    except pyodbc.Error as exc:
        raise SystemExit(f"\nDatenbankfehler:\n{exc}") from exc

    print("\nFertig. Verbinde Power BI mit localhost,1433 / Datenbank msv_dwh.")


if __name__ == "__main__":
    main()
