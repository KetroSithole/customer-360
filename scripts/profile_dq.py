import os
from pathlib import Path

import pyodbc
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

SERVER = os.getenv("MSSQL_SERVER", r"GHOST\MSSQLSERVER02")
DATABASE = os.getenv("MSSQL_DATABASE", "CaseStudyDB")
DRIVER = os.getenv("MSSQL_DRIVER", "ODBC Driver 17 for SQL Server")

cn = pyodbc.connect(
    f"DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={DATABASE};Trusted_Connection=yes;"
)
cur = cn.cursor()

checks = {
    "dup customer_id": "SELECT COUNT(*) FROM (SELECT customer_id FROM customer_raw GROUP BY customer_id HAVING COUNT(*)>1) x",
    "dup email": "SELECT COUNT(*) FROM (SELECT email FROM customer_raw WHERE email IS NOT NULL GROUP BY email HAVING COUNT(*)>1) x",
    "null emails": "SELECT COUNT(*) FROM customer_raw WHERE email IS NULL OR LTRIM(RTRIM(email))=''",
    "invalid email fmt": "SELECT COUNT(*) FROM customer_raw WHERE email NOT LIKE '%_@%_.%_'",
    "null names": "SELECT COUNT(*) FROM customer_raw WHERE first_name IS NULL OR last_name IS NULL",
    "gender values": "SELECT gender, COUNT(*) FROM customer_raw GROUP BY gender",
    "future dob": "SELECT COUNT(*) FROM customer_raw WHERE date_of_birth > GETDATE()",
    "dob under 18": "SELECT COUNT(*) FROM customer_raw WHERE DATEDIFF(YEAR, date_of_birth, GETDATE()) < 18",
    "dob over 100": "SELECT COUNT(*) FROM customer_raw WHERE DATEDIFF(YEAR, date_of_birth, GETDATE()) > 100",
    "signup before dob": "SELECT COUNT(*) FROM customer_raw WHERE signup_date < date_of_birth",
    "future signup": "SELECT COUNT(*) FROM customer_raw WHERE signup_date > GETDATE()",
    "mobile bad len": "SELECT COUNT(*) FROM customer_raw WHERE LEN(mobile) <> 11",
    "enroll orphan cust": "SELECT COUNT(*) FROM product_enrollments e LEFT JOIN customer_raw c ON e.customer_id=c.customer_id WHERE c.customer_id IS NULL",
    "enroll dup product_id": "SELECT COUNT(*) FROM (SELECT product_id FROM product_enrollments GROUP BY product_id HAVING COUNT(*)>1) x",
    "product types": "SELECT product_type, COUNT(*) FROM product_enrollments GROUP BY product_type",
    "enroll before signup": "SELECT COUNT(*) FROM product_enrollments e JOIN customer_raw c ON e.customer_id=c.customer_id WHERE e.enrollment_date < c.signup_date",
    "negative limit": "SELECT COUNT(*) FROM product_enrollments WHERE [limit] < 0",
    "crm orphan cust": "SELECT COUNT(*) FROM crm_interactions i LEFT JOIN customer_raw c ON i.customer_id=c.customer_id WHERE c.customer_id IS NULL",
    "crm types": "SELECT interaction_type, COUNT(*) FROM crm_interactions GROUP BY interaction_type",
    "crm future date": "SELECT COUNT(*) FROM crm_interactions WHERE interaction_date > GETDATE()",
    "crm date range": "SELECT MIN(interaction_date), MAX(interaction_date) FROM crm_interactions",
    "txn orphan cust": "SELECT COUNT(*) FROM transaction_history t LEFT JOIN customer_raw c ON t.customer_id=c.customer_id WHERE c.customer_id IS NULL",
    "txn orphan product": "SELECT COUNT(*) FROM transaction_history t LEFT JOIN product_enrollments p ON t.product_id=p.product_id WHERE p.product_id IS NULL",
    "txn product/cust mismatch": "SELECT COUNT(*) FROM transaction_history t JOIN product_enrollments p ON t.product_id=p.product_id WHERE t.customer_id<>p.customer_id",
    "txn zero amount": "SELECT COUNT(*) FROM transaction_history WHERE transaction_amount = 0",
    "txn date range": "SELECT MIN(transaction_date), MAX(transaction_date) FROM transaction_history",
    "txn future": "SELECT COUNT(*) FROM transaction_history WHERE transaction_date > GETDATE()",
    "txn amount range": "SELECT MIN(transaction_amount), MAX(transaction_amount) FROM transaction_history",
    "cust w/o products": "SELECT COUNT(*) FROM customer_raw c LEFT JOIN product_enrollments p ON c.customer_id=p.customer_id WHERE p.customer_id IS NULL",
}

for name, sql in checks.items():
    cur.execute(sql)
    rows = cur.fetchall()
    if len(rows) == 1 and len(rows[0]) == 1:
        print(f"{name}: {rows[0][0]}")
    else:
        print(f"{name}:")
        for r in rows:
            print("   ", list(r))
