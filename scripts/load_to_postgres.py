"""
load_to_postgres.py
-------------------
Creates the `maven_fuzzy_factory` database (if missing), applies sql/01_schema.sql,
and bulk-loads the six source CSVs from maven-fuzzy-factory/ using PostgreSQL COPY.

Connection settings are read from environment variables, falling back to a
project-root `.env` file:

    PGHOST=localhost  PGPORT=5432  PGUSER=postgres
    PGPASSWORD=<your password>     PGDATABASE=maven_fuzzy_factory

Usage:
    python scripts/load_to_postgres.py
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "maven-fuzzy-factory"
SCHEMA_SQL = PROJECT_ROOT / "sql" / "01_schema.sql"

load_dotenv(PROJECT_ROOT / ".env")

PGHOST = os.getenv("PGHOST", "localhost")
PGPORT = os.getenv("PGPORT", "5432")
PGUSER = os.getenv("PGUSER", "postgres")
PGPASSWORD = os.getenv("PGPASSWORD") or os.getenv("PG_PASSWORD")
TARGET_DB = os.getenv("PGDATABASE", "maven_fuzzy_factory")

# (table, csv file) in FK-safe load order
TABLES = [
    ("products", "products.csv"),
    ("website_sessions", "website_sessions.csv"),
    ("website_pageviews", "website_pageviews.csv"),
    ("orders", "orders.csv"),
    ("order_items", "order_items.csv"),
    ("order_item_refunds", "order_item_refunds.csv"),
]


def base_params(dbname: str) -> dict:
    return dict(host=PGHOST, port=PGPORT, user=PGUSER, password=PGPASSWORD, dbname=dbname)


def ensure_database() -> None:
    """Create the target database if it does not already exist."""
    conn = psycopg2.connect(**base_params("postgres"))
    conn.autocommit = True  # CREATE DATABASE cannot run in a transaction
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_database WHERE datname = %s;", (TARGET_DB,))
            if cur.fetchone():
                print(f"[=] database '{TARGET_DB}' already exists")
            else:
                cur.execute(f'CREATE DATABASE "{TARGET_DB}";')
                print(f"[+] created database '{TARGET_DB}'")
    finally:
        conn.close()


def apply_schema() -> None:
    print("[*] applying sql/01_schema.sql")
    ddl = SCHEMA_SQL.read_text(encoding="utf-8")
    conn = psycopg2.connect(**base_params(TARGET_DB))
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute(ddl)
    finally:
        conn.close()


def load_tables() -> None:
    conn = psycopg2.connect(**base_params(TARGET_DB))
    try:
        with conn.cursor() as cur:
            for table, filename in TABLES:
                csv_path = DATA_DIR / filename
                if not csv_path.exists():
                    raise FileNotFoundError(csv_path)
                # The source files encode missing values as the literal text
                # "NULL"; the explicit NULL 'NULL' option maps them to SQL NULL
                # so Postgres matches pandas' NaN handling.
                with csv_path.open("r", encoding="utf-8", newline="") as fh:
                    cur.copy_expert(
                        f"COPY {table} FROM STDIN "
                        f"WITH (FORMAT csv, HEADER true, NULL 'NULL')",
                        fh,
                    )
                cur.execute(f"SELECT COUNT(*) FROM {table};")
                print(f"[+] loaded {table:<20} {cur.fetchone()[0]:>9,} rows  <- {filename}")
        conn.commit()
    finally:
        conn.close()


def verify() -> None:
    conn = psycopg2.connect(**base_params(TARGET_DB))
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM v_order_revenue;")
            orders = cur.fetchone()[0]
            cur.execute("SELECT ROUND(SUM(price_usd),2) FROM v_order_revenue;")
            revenue = cur.fetchone()[0]
        print(f"[ok] v_order_revenue: {orders:,} orders, ${revenue:,.2f} gross revenue")
    finally:
        conn.close()


def main() -> int:
    if not PGPASSWORD:
        print("ERROR: PGPASSWORD is not set (add it to .env or the environment).", file=sys.stderr)
        return 1
    ensure_database()
    apply_schema()
    load_tables()
    verify()
    print("[done] PostgreSQL load complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
