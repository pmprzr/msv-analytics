import os
from urllib.parse import quote_plus
from sqlalchemy import create_engine, text

pw = quote_plus(os.environ["MSSQL_SA_PASSWORD"])
engine = create_engine(
    f"mssql+pyodbc://sa:{pw}@localhost:1433/msv_dwh"
    "?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes"
)

with engine.connect() as conn:
    print(conn.execute(text("SELECT @@VERSION")).scalar())