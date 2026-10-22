"""Zentrale Einstellungen. Alles, was man ggf. anpassen moechte, steht hier."""
import os
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")

# --- Pfade ---------------------------------------------------------------
RAW_DIR = ROOT / "data" / "raw"
SQL_DIR = ROOT / "sql"

# --- Datenbank (SQL Server in Docker) ------------------------------------
DB_NAME = "msv_dwh"  # wird von sql/00_create_database.sql angelegt
DB_HOST = os.getenv("MSSQL_HOST", "localhost")
DB_PORT = os.getenv("MSSQL_PORT", "1433")
DB_USER = "sa"
ODBC_DRIVER = os.getenv("MSSQL_ODBC_DRIVER", "ODBC Driver 18 for SQL Server")

# --- Datenquelle (OpenLigaDB) --------------------------------------------
API_BASE_URL = "https://api.openligadb.de/getmatchdata"
LEAGUE = "bl3"  # 3. Liga
DEFAULT_SEASONS = list(range(2021, 2027))  # 2021 = Saison 2021/22
MSV_TEAM_ID = 107  # teamId des MSV Duisburg bei OpenLigaDB (auch in sql/02_load_dwh.sql)


def get_password() -> str:
    password = os.getenv("MSSQL_SA_PASSWORD")
    if not password:
        raise SystemExit(
            "MSSQL_SA_PASSWORD fehlt. Lege eine Datei .env an "
            "(Vorlage: .env.example) und trage dort das Passwort ein."
        )
    return password
