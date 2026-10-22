"""Extract: laedt die Spieldaten der 3. Liga pro Saison von OpenLigaDB nach data/raw/.

    python src/extract.py            # alle Standard-Saisons
    python src/extract.py 2025 2026  # nur bestimmte Saisons
"""
import argparse
import json
import time

import requests

from config import API_BASE_URL, DEFAULT_SEASONS, LEAGUE, MSV_TEAM_ID, RAW_DIR


def fetch_season(season: int, retries: int = 3) -> list[dict]:
    url = f"{API_BASE_URL}/{LEAGUE}/{season}"
    for attempt in range(1, retries + 1):
        try:
            response = requests.get(url, timeout=60)
            response.raise_for_status()
            return response.json()
        except requests.RequestException:
            if attempt == retries:
                raise
            time.sleep(2 * attempt)
    return []


def main(seasons=None) -> None:
    seasons = list(seasons) if seasons else DEFAULT_SEASONS
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    for season in seasons:
        matches = fetch_season(season)
        if not matches:
            print(f"Saison {season}: keine Daten von der API erhalten, uebersprungen")
            continue

        path = RAW_DIR / f"{LEAGUE}_{season}.json"
        path.write_text(json.dumps(matches, ensure_ascii=False), encoding="utf-8")

        msv = [
            m for m in matches
            if MSV_TEAM_ID in ((m.get("team1") or {}).get("teamId"), (m.get("team2") or {}).get("teamId"))
        ]
        print(f"Saison {season}: {len(matches)} Spiele gesamt, {len(msv)} mit MSV -> {path.name}")
        time.sleep(0.5)  # die kostenlose API nicht unnoetig belasten


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Laedt Rohdaten von OpenLigaDB.")
    parser.add_argument("seasons", nargs="*", type=int, help="Startjahre, z. B. 2025")
    main(parser.parse_args().seasons)
