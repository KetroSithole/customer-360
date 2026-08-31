"""Load the case-study CSV files into SQL Server.

Reads the four pipe-delimited CSVs in data/raw, creates the target
database and tables if they do not exist, and bulk-inserts the data.

The script is idempotent: the database and tables are only created when
missing, and any table that already contains rows is skipped, so it is
safe to run repeatedly.

Usage:
    python load_to_sqlserver.py

Requirements:
    pip install -r requirements.txt (pandas, pyodbc, python-dotenv).
    Connection settings come from the .env file in the repo root
    (see .env.example). Connects with Windows authentication.
"""

import os
from pathlib import Path

import pandas as pd
import pyodbc
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

SERVER = os.getenv("MSSQL_SERVER", r"GHOST\MSSQLSERVER02")
DATABASE = os.getenv("MSSQL_DATABASE", "CaseStudyDB")
DRIVER = os.getenv("MSSQL_DRIVER", "ODBC Driver 17 for SQL Server")
CSV_SEPARATOR = "|"
BATCH_SIZE = 50_000
DATA_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"

# Target tables: source CSV, table DDL, and pandas dtype overrides.
# "mobile" is forced to str to preserve leading zeros.
TABLES = {
    "customer_raw": {
        "file": "customer_raw.csv",
        "dtype": {"mobile": str},
        "ddl": """
            CREATE TABLE customer_raw (
                customer_id INT NOT NULL PRIMARY KEY,
                first_name NVARCHAR(100),
                last_name NVARCHAR(100),
                email NVARCHAR(255),
                mobile VARCHAR(20),
                gender NVARCHAR(20),
                date_of_birth DATE,
                signup_date DATE
            )
        """,
    },
    "crm_interactions": {
        "file": "crm_interactions.csv",
        "dtype": None,
        "ddl": """
            CREATE TABLE crm_interactions (
                interaction_id INT NOT NULL PRIMARY KEY,
                customer_id INT NOT NULL,
                interaction_type NVARCHAR(50),
                interaction_date DATE
            )
        """,
    },
    "product_enrollments": {
        "file": "product_enrollments.csv",
        "dtype": None,
        "ddl": """
            CREATE TABLE product_enrollments (
                product_id INT NOT NULL PRIMARY KEY,
                customer_id INT NOT NULL,
                product_type NVARCHAR(50),
                enrollment_date DATE,
                [limit] DECIMAL(18, 2)
            )
        """,
    },
    "transaction_history": {
        "file": "transaction_history.csv",
        "dtype": None,
        "ddl": """
            CREATE TABLE transaction_history (
                transaction_id INT NOT NULL PRIMARY KEY,
                product_id INT NOT NULL,
                customer_id INT NOT NULL,
                transaction_amount DECIMAL(18, 2),
                closing_balance DECIMAL(18, 2),
                transaction_date DATETIME2(0)
            )
        """,
    },
}


def connect(database: str = "master", autocommit: bool = False) -> pyodbc.Connection:
    """Open a trusted (Windows-auth) connection to the given database."""
    return pyodbc.connect(
        f"DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={database};Trusted_Connection=yes;",
        autocommit=autocommit,
    )


def create_database() -> None:
    """Create the target database if it does not already exist."""
    with connect("master", autocommit=True) as cn:
        cn.execute(
            f"IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = '{DATABASE}') "
            f"CREATE DATABASE [{DATABASE}]"
        )
    print(f"Database {DATABASE} ready.")


def ensure_table(cur: pyodbc.Cursor, table: str, ddl: str) -> None:
    """Create the table if it does not already exist."""
    cur.execute(
        "IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = ?) "
        "EXEC sp_executesql N'" + ddl.replace("'", "''") + "'",
        table,
    )
    cur.connection.commit()


def table_has_rows(cur: pyodbc.Cursor, table: str) -> bool:
    """Return True if the table already contains data."""
    cur.execute(f"SELECT COUNT(*) FROM [{table}]")
    return cur.fetchone()[0] > 0


def read_csv(spec: dict) -> pd.DataFrame:
    """Read a source CSV, parsing date columns and converting NaN to None."""
    df = pd.read_csv(DATA_DIR / spec["file"], sep=CSV_SEPARATOR, dtype=spec["dtype"])
    for col in df.columns:
        if "date" in col.lower():
            df[col] = pd.to_datetime(df[col], format="ISO8601")
    return df.astype(object).where(pd.notnull(df), None)


def load_table(cur: pyodbc.Cursor, table: str, df: pd.DataFrame) -> None:
    """Bulk-insert a DataFrame into the table in batches."""
    # Column order must match the table definition, not the CSV.
    cur.execute(
        "SELECT name FROM sys.columns WHERE object_id = OBJECT_ID(?) ORDER BY column_id",
        table,
    )
    cols = [row[0] for row in cur.fetchall()]
    df = df[cols]

    col_list = ", ".join(f"[{c}]" for c in cols)
    placeholders = ", ".join("?" * len(cols))
    insert_sql = f"INSERT INTO [{table}] ({col_list}) VALUES ({placeholders})"

    rows = list(df.itertuples(index=False, name=None))
    for start in range(0, len(rows), BATCH_SIZE):
        cur.executemany(insert_sql, rows[start : start + BATCH_SIZE])
        cur.connection.commit()
    print(f"{table}: loaded {len(rows)} rows.")


def create_and_load() -> None:
    """Create each table (if missing) and load its CSV (if empty)."""
    with connect(DATABASE) as cn:
        cur = cn.cursor()
        cur.fast_executemany = True
        for table, spec in TABLES.items():
            ensure_table(cur, table, spec["ddl"])
            if table_has_rows(cur, table):
                print(f"{table}: already has data, skipping load.")
                continue
            load_table(cur, table, read_csv(spec))


if __name__ == "__main__":
    create_database()
    create_and_load()
    print("Done.")
