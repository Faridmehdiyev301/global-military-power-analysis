"""
Global Firepower (globalfirepower.com) Military Strength Data Scraper
-----------------------------------------------------------------------
Scrapes the country listing page for all countries + PwrIndx ranking,
then visits each country's detail page to pull financial, geographic,
manpower, air/land/naval, energy, and infrastructure statistics.
Exports everything into a single Excel file matching the target schema.
"""

import re
import time
import logging
from dataclasses import dataclass, fields
from typing import Optional

import requests
from bs4 import BeautifulSoup
import pandas as pd

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger(__name__)

BASE_URL = "https://www.globalfirepower.com"
LISTING_URL = f"{BASE_URL}/countries-listing.php"
DETAIL_URL = f"{BASE_URL}/country-military-strength-detail.php?country_id={{country_id}}"
REQUEST_DELAY_SEC = 1.5  # be polite to the server
TIMEOUT_SEC = 15
OUTPUT_FILE = "military_clean_FINAL.xlsx"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    )
}

# Maps the visible label text on a country's detail page to our column name.
FIELD_MAP = {
    "Purchasing Power Parity": "FIN_PPP",
    "Foreign Exchange and Gold Reserves": "FIN_FX_GOLD",
    "Defense Budget": "FIN_DEFENSE_BUDGET",
    "External Debt": "FIN_EXTERNAL_DEBT",
    "Square Land Area": "GEO_LAND_AREA",
    "Coastline": "GEO_COASTLINE",
    "Shared Borders": "GEO_SHARED_BORDERS",
    "Waterways": "GEO_WATERWAYS",
    "Total Population": "MAN_POPULATION",
    "Available Manpower": "MAN_AVAILABLE",
    "Fit-for-Service": "MAN_FIT_FOR_SERVICE",
    "Reaching Military Age Annually": "MAN_MIL_AGE_ANNUAL",
    "Total Military Personnel": "MAN_TOTAL_PERSONNEL",
    "Active Personnel": "MAN_ACTIVE",
    "Reserve Personnel": "MAN_RESERVE",
    "Paramilitary": "MAN_PARAMILITARY",
    "Total Aircraft Strength": "AIR_AIRCRAFT_TOTAL",
    "Fighter Aircraft": "AIR_FIGHTERS",
    "Attack Aircraft": "AIR_ATTACK_TYPES",
    "Transport Aircraft": "AIR_TRANSPORTS",
    "Trainer Aircraft": "AIR_TRAINERS",
    "Special-Mission Aircraft": "AIR_SPECIAL_MISSION",
    "Tanker Fleet": "AIR_TANKER_FLEET",
    "Helicopter Fleet": "AIR_HELICOPTERS",
    "Attack Helicopters": "AIR_ATTACK_HELICOPTERS",
    "Tank Strength": "LAND_TANKS",
    "Armored Vehicle Strength": "LAND_VEHICLES",
    "Self-Propelled Artillery": "LAND_SELF_PROPELLED_ARTILLERY",
    "Towed Artillery": "LAND_TOWED_ARTILLERY",
    "Rocket Projectors": "LAND_MLRS",
    "Total Naval Fleet Strength": "NAVAL_TOTAL_ASSETS",
    "Aircraft Carriers": "NAVAL_AIRCRAFT_CARRIERS",
    "Helicopter Carriers": "NAVAL_HELICOPTER_CARRIERS",
    "Destroyers": "NAVAL_DESTROYERS",
    "Frigates": "NAVAL_FRIGATES",
    "Corvettes": "NAVAL_CORVETTES",
    "Submarines": "NAVAL_SUBMARINES",
    "Patrol Vessels": "NAVAL_PATROL_VESSELS",
    "Mine Warfare Vessels": "NAVAL_MINE_WARFARE",
    "Oil Production": "NRG_OIL_PRODUCTION",
    "Oil Consumption": "NRG_OIL_CONSUMPTION",
    "Proven Oil Reserves": "NRG_OIL_RESERVES",
    "Natural Gas Production": "NRG_GAS_PRODUCTION",
    "Natural Gas Consumption": "NRG_GAS_CONSUMPTION",
    "Proven Natural Gas Reserves": "NRG_GAS_RESERVES",
    "Coal Production": "NRG_COAL_PRODUCTION",
    "Coal Consumption": "NRG_COAL_CONSUMPTION",
    "Internet Users": "INFRA_INTERNET",
    "Labor Force": "INFRA_LABOR_FORCE",
    "Merchant Marine Strength": "INFRA_MERCHANT_FLEET",
    "Major Ports and Terminals": "INFRA_PORTS",
    "Serviceable Airports": "INFRA_AIRPORTS",
    "Roadway Coverage": "INFRA_ROADS",
    "Railway Coverage": "INFRA_RAILWAYS",
}


@dataclass
class CountryRecord:
    COUNTRY: str
    GFP_RANK: Optional[int] = None
    MILITARY_POWER_SCORE: Optional[float] = None
    REGION: Optional[str] = None


def get_session() -> requests.Session:
    session = requests.Session()
    session.headers.update(HEADERS)
    return session


def clean_number(raw_text: str) -> Optional[float]:
    """Turn '1,234,567' / '83%' / 'N/A' style text into a float, or None."""
    if not raw_text:
        return None
    text = raw_text.strip().replace(",", "").replace("%", "")
    if text in ("", "N/A", "-", "null"):
        return None
    match = re.search(r"-?\d+(\.\d+)?", text)
    return float(match.group()) if match else None


def fetch_country_listing(session: requests.Session) -> pd.DataFrame:
    """Scrape the main ranking table: country name, id, region, rank, PwrIndx score."""
    logger.info("Fetching country listing page...")
    response = session.get(LISTING_URL, timeout=TIMEOUT_SEC)
    response.raise_for_status()
    soup = BeautifulSoup(response.text, "html.parser")

    rows = []
    table = soup.select_one("table.pageTable, table#tableID, table")
    for row in table.select("tr")[1:]:  # skip header row
        cells = row.select("td")
        if len(cells) < 3:
            continue

        link = row.select_one("a[href*='country_id=']")
        country_id_match = re.search(r"country_id=(\d+)", link["href"]) if link else None

        rows.append({
            "COUNTRY": cells[1].get_text(strip=True),
            "GFP_RANK": clean_number(cells[0].get_text(strip=True)),
            "MILITARY_POWER_SCORE": clean_number(cells[2].get_text(strip=True)),
            "country_id": country_id_match.group(1) if country_id_match else None,
        })

    logger.info("Found %d countries in listing.", len(rows))
    return pd.DataFrame(rows)


def fetch_country_details(session: requests.Session, country_id: str) -> dict:
    """Scrape one country's detail page and map its stats to our schema."""
    url = DETAIL_URL.format(country_id=country_id)
    response = session.get(url, timeout=TIMEOUT_SEC)
    response.raise_for_status()
    soup = BeautifulSoup(response.text, "html.parser")

    data = {}
    for row in soup.select("tr"):
        cells = row.select("td")
        if len(cells) != 2:
            continue
        label = cells[0].get_text(strip=True)
        value = cells[1].get_text(strip=True)
        column = FIELD_MAP.get(label)
        if column:
            data[column] = clean_number(value)

    region_tag = soup.select_one(".region, [data-region]")
    if region_tag:
        data["REGION"] = region_tag.get_text(strip=True)

    return data


def scrape_all_countries() -> pd.DataFrame:
    session = get_session()
    listing_df = fetch_country_listing(session)

    all_records = []
    for i, row in listing_df.iterrows():
        country_id = row["country_id"]
        record = row.drop("country_id").to_dict()

        if country_id:
            logger.info("[%d/%d] Scraping details for %s", i + 1, len(listing_df), row["COUNTRY"])
            try:
                details = fetch_country_details(session, country_id)
                record.update(details)
            except requests.RequestException as exc:
                logger.warning("Failed to fetch %s: %s", row["COUNTRY"], exc)
            time.sleep(REQUEST_DELAY_SEC)

        all_records.append(record)

    return pd.DataFrame(all_records)


def save_to_excel(df: pd.DataFrame, path: str = OUTPUT_FILE) -> None:
    df.to_excel(path, index=False, sheet_name="Sheet1")
    logger.info("Saved %d rows to %s", len(df), path)


def main() -> None:
    df = scrape_all_countries()
    save_to_excel(df)


if __name__ == "__main__":
    main()
