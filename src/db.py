"""Datenbankzugriff: Verbindungen und Ausfuehren von .sql-Dateien.

Kann auch direkt benutzt werden, um eine SQL-Datei auszufuehren:
    python src/db.py sql/04_checks.sql
"""
import argparse
import re
import time
from pathlib import Path

from config import (DB_HOST, DB_NAME, DB_PORT, DB_USER, ODBC_DRIVER, ROOT,
                    get_password)

# "GO" steht allein in einer Zeile und trennt Batches (wie in SSMS).
# pyodbc kennt GO nicht, deshalb schneiden wir die Dateien selbst auf.
_GO = re.compile(r"^\s*GO\s*$", re.IGNORECASE | re.MULTILINE)


def odbc_connection_string(database: str = DB_NAME) -> str:
    password = get_password().replace("}", "}}")  # Sonderzeichen sicher quoten
    return (
        f"DRIVER={{{ODBC_DRIVER}}};SERVER={DB_HOST},{DB_PORT};DATABASE={database};"
        f"UID={DB_USER};PWD={{{password}}};TrustServerCertificate=yes;"
    )


def connect(database: str = DB_NAME):
    """pyodbc-Verbindung im Autocommit-Modus (noetig z. B. fuer CREATE DATABASE)."""
    import pyodbc

    return pyodbc.connect(odbc_connection_string(database), autocommit=True, timeout=10)


def get_engine(database: str = DB_NAME):
    """SQLAlchemy-Engine fuer pandas.to_sql."""
    from sqlalchemy import create_engine
    from sqlalchemy.engine import URL

    url = URL.create("mssql+pyodbc", query={"odbc_connect": odbc_connection_string(database)})
    return create_engine(url, fast_executemany=True)


def wait_for_sql_server(timeout_seconds: int = 90) -> None:
    """Wartet, bis der Container Verbindungen annimmt (nach 'docker compose up' dauert das kurz)."""
    import pyodbc

    deadline = time.time() + timeout_seconds
    last_error = None
    while time.time() < deadline:
        try:
            connect("master").close()
            return
        except pyodbc.Error as exc:
            if exc.args and str(exc.args[0]) == "28000":  # Login failed -> Warten hilft nicht
                raise SystemExit(
                    "Anmeldung an SQL Server fehlgeschlagen. Stimmt MSSQL_SA_PASSWORD in .env "
                    "mit dem Passwort ueberein, mit dem der Container erstmals gestartet wurde? "
                    "(Passwort aendern: 'docker compose down -v' und neu starten.)"
                ) from exc
            last_error = exc
            time.sleep(3)
    raise SystemExit(
        "SQL Server ist nicht erreichbar. Laeuft der Container? (docker compose up -d, "
        f"docker compose ps)\nLetzter Fehler: {last_error}"
    )


# --- SQL-Dateien ausfuehren ------------------------------------------------

def split_batches(sql_text: str) -> list[str]:
    return [b.strip() for b in _GO.split(sql_text) if b.strip()]


def _has_code(batch: str) -> bool:
    """False, wenn der Batch nur aus Kommentarzeilen besteht."""
    return any(line.strip() and not line.strip().startswith("--") for line in batch.splitlines())


def _batch_title(batch: str) -> str | None:
    first = batch.splitlines()[0].strip()
    return first.lstrip("- ").strip() if first.startswith("--") else None


def _format(value) -> str:
    return "NULL" if value is None else str(value)


def _print_result(title, columns, rows, max_rows: int = 40) -> None:
    table = [[_format(v) for v in row] for row in rows[:max_rows]]
    widths = [max([len(c)] + [len(r[i]) for r in table]) for i, c in enumerate(columns)]
    if title:
        print(f"\n  >> {title}")
    print("  " + " | ".join(c.ljust(w) for c, w in zip(columns, widths)))
    print("  " + "-+-".join("-" * w for w in widths))
    for row in table:
        print("  " + " | ".join(v.ljust(w) for v, w in zip(row, widths)))
    if len(rows) > max_rows:
        print(f"  ... {len(rows) - max_rows} weitere Zeilen")
    if not rows:
        print("  (keine Zeilen)")


def run_sql(sql_text: str, database: str = DB_NAME, show_results: bool = True) -> None:
    conn = connect(database)
    try:
        cursor = conn.cursor()
        for batch in split_batches(sql_text):
            if not _has_code(batch):
                continue
            cursor.execute(batch)
            title = _batch_title(batch)
            while True:
                if cursor.description is not None:
                    columns = [c[0] for c in cursor.description]
                    rows = cursor.fetchall()
                    if show_results:
                        _print_result(title, columns, rows)
                if not cursor.nextset():
                    break
    finally:
        conn.close()


def run_file(path: Path, database: str = DB_NAME, show_results: bool = True) -> None:
    run_sql(Path(path).read_text(encoding="utf-8"), database, show_results)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fuehrt eine SQL-Datei gegen die Datenbank aus.")
    parser.add_argument("file", help="z. B. sql/04_checks.sql")
    parser.add_argument("--database", default=DB_NAME)
    args = parser.parse_args()
    file_path = Path(args.file)
    if not file_path.is_absolute():
        file_path = ROOT / file_path
    run_file(file_path, args.database)
