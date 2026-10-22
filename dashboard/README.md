# Dashboard

Hier liegen die Power-BI-Datei (`.pbix`) und Screenshots der Berichtsseiten.

**Verbindung in Power BI Desktop:**
Daten abrufen → SQL Server → Server `localhost,1433`, Datenbank `msv_dwh`,
Datenkonnektivitätsmodus *Import*, Anmeldung mit Datenbank-Benutzer `sa` und dem Passwort aus `.env`.
Tabellen aus dem Schema `dwh` auswählen (`dim_*`, `fact_*`, `v_season_table`, `v_team_form`).

_Das Dashboard folgt: Saisonübersicht, Heim/Auswärts, Tore und Torminuten._
