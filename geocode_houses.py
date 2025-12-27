import os
import time
import csv
import re
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
from supabase import create_client
from dotenv import load_dotenv

# =========================
# Config
# =========================
load_dotenv()

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
CONTACT_EMAIL = "alessandra.serpes@gmail.com"

HEADERS = {
    # Use a real identifier per Nominatim policy
    "User-Agent": "chs-companion-geocoder/1.0 (contact: aserpes@wpi.edu)"
}

# Tune these:
BATCH_SIZE = 200          # rows pulled from Supabase each loop
MAX_WORKERS = 3           # 2–4 usually safe; higher triggers throttling
MIN_DELAY_S = 0.8         # global minimum delay between requests (polite pacing)
DEBUG_PRINT_QUERY = False # set True to print queries being sent

# =========================
# HTTP session + shared state
# =========================
session = requests.Session()

cache_lock = threading.Lock()
geocode_cache = {}  # address -> (lat, lon) or None

last_request_lock = threading.Lock()
last_request_time = 0.0

# =========================
# Address normalization helpers
# =========================
ZIP4_RE = re.compile(r"\b(\d{4})\b")  # e.g., 2116 -> 02116 (MA zips often lose leading 0)

def normalize_zip(addr: str) -> str:
    """
    Your dataset often drops leading 0 in MA zips (e.g., 2116 instead of 02116).
    This pads any standalone 4-digit token to 5 digits by prefixing 0.
    """
    return ZIP4_RE.sub(lambda m: "0" + m.group(1), addr)

def strip_unit(addr: str) -> str:
    """
    Remove unit/apartment tokens like:
      ', 610,'  ', 2,'  'APT 5'  '#12'  'UNIT 3'  'STE 200'
    Keeps main building address (street, city, state, zip).
    """
    a = " ".join(addr.replace("  ", " ").split())  # collapse whitespace
    parts = [p.strip() for p in a.split(",") if p.strip()]

    cleaned = []
    for p in parts:
        up = p.upper()

        # Drop bare unit tokens like "610", "3A", "12"
        if re.fullmatch(r"\d+[A-Z]?", up):
            continue

        # Drop common unit prefixes
        if up.startswith(("APT", "APARTMENT", "UNIT", "#", "STE", "SUITE", "FL", "FLOOR", "RM", "ROOM")):
            continue

        cleaned.append(p)

    return ", ".join(cleaned)

def build_query(row: dict) -> str:
    address = (row.get("address") or "").strip()
    if not address:
        return ""

    base = strip_unit(address)
    base = normalize_zip(base)

    if "USA" not in base.upper():
        base = f"{base}, USA"

    return base

# =========================
# Rate limiting + geocode
# =========================
def _global_throttle():
    """Enforce a minimum delay between requests across all threads."""
    global last_request_time
    with last_request_lock:
        now = time.time()
        wait = (last_request_time + MIN_DELAY_S) - now
        if wait > 0:
            time.sleep(wait)
        last_request_time = time.time()

def geocode_one(query: str, max_tries: int = 6):
    params = {
        "q": query,
        "format": "jsonv2",
        "limit": 1,
        "addressdetails": 0,
        "email": CONTACT_EMAIL,
    }

    backoff = 2.0
    for _ in range(max_tries):
        try:
            _global_throttle()

            if DEBUG_PRINT_QUERY:
                print("QUERY:", query)

            resp = session.get(NOMINATIM_URL, params=params, headers=HEADERS, timeout=30)

            # Throttled/overloaded -> backoff and retry
            if resp.status_code in (429, 503):
                time.sleep(backoff)
                backoff = min(backoff * 2, 60)
                continue

            # 403 usually means UA/email issue or blocked IP. Don't hammer.
            if resp.status_code == 403:
                raise Exception("403_forbidden_check_user_agent_or_blocked_ip")

            resp.raise_for_status()
            data = resp.json()
            if not data:
                return None

            return float(data[0]["lat"]), float(data[0]["lon"])

        except requests.exceptions.Timeout:
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)
        except requests.exceptions.RequestException:
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)

    return None

def geocode_address(row: dict):
    """
    Worker: returns (address, query, result or None, error_str or None)
    Uses an in-run cache to avoid duplicate geocodes.
    """
    address = row["address"]
    query = build_query(row)

    with cache_lock:
        if address in geocode_cache:
            return address, query, geocode_cache[address], None

    try:
        result = geocode_one(query)
        with cache_lock:
            geocode_cache[address] = result
        return address, query, result, None
    except Exception as e:
        return address, query, None, f"{type(e).__name__}: {e}"

# =========================
# Supabase fetch/update
# =========================
def fetch_batch(limit: int = BATCH_SIZE):
    """
    No OFFSET: always fetch the next chunk of remaining nulls.
    This is safer when you're updating rows as you go.
    """
    for attempt in range(1, 6):
        try:
            res = (
                supabase.table("houses")
                .select("address,lat,lon")
                .is_("lat", "null")
                .limit(limit)
                .execute()
            )
            return res.data or []
        except Exception as e:
            print(f"Supabase fetch failed (attempt {attempt}/5): {e}")
            time.sleep(min(10 * attempt, 60))
    return None

def update_house(address: str, lat: float, lon: float):
    supabase.table("houses").update({"lat": lat, "lon": lon}).eq("address", address).execute()

# =========================
# Main
# =========================
def main():
    failures_path = "geocode_failures.csv"
    wrote_header = os.path.exists(failures_path)

    total_updated = 0
    total_no_result = 0
    total_failed = 0

    with open(failures_path, "a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        if not wrote_header:
            writer.writerow(["address", "query", "reason"])

        while True:
            rows = fetch_batch()
            if rows is None:
                print("Giving up after repeated Supabase fetch failures.")
                return

            if not rows:
                break

            # Deduplicate within the batch by address
            seen = set()
            unique_rows = []
            for r in rows:
                a = r.get("address")
                if not a or a in seen:
                    continue
                seen.add(a)
                unique_rows.append(r)

            # Geocode concurrently (but still polite due to global throttle)
            results = []
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
                futures = [ex.submit(geocode_address, r) for r in unique_rows]
                for fut in as_completed(futures):
                    results.append(fut.result())

            # Update DB sequentially
            for address, query, result, err in results:
                if err is not None:
                    total_failed += 1
                    writer.writerow([address, query, f"error: {err}"])
                    print(f"FAILED: {address} ({query}) -> {err}")
                    continue

                if result is None:
                    total_no_result += 1
                    writer.writerow([address, query, "no_result"])
                    print(f"NO RESULT: {address} ({query})")
                    continue

                lat, lon = result
                try:
                    update_house(address, lat, lon)
                    total_updated += 1
                    print(f"UPDATED {total_updated}: {address} -> ({lat}, {lon})")
                except Exception as e:
                    total_failed += 1
                    writer.writerow([address, query, f"update_error: {type(e).__name__}: {e}"])
                    print(f"UPDATE FAILED: {address} -> {e}")

    print("\nDone.")
    print(f"Total updated:   {total_updated}")
    print(f"No result:      {total_no_result}")
    print(f"Total failed:   {total_failed}")
    print(f"Failures logged to: {failures_path}")

if __name__ == "__main__":
    main()
