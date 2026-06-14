# SECURE VERSION — the correct implementations for each vulnerability in vulnerable_payment.py.
# This is what the code looks like AFTER CodeQL and Snyk findings are remediated.
#
# Each function documents the remediation technique so it can be explained at interview.

import sqlite3
import os
import hashlib
import secrets
import json
import subprocess
import re


# ─── CWE-798 remediation: environment variables, never source code ────────────
# Credentials are injected at runtime via K8s Secrets (see k8s/rbac/rbac.yaml)
# or GCP Workload Identity (see terraform/gke.tf). They are never committed to git.
# CI pipelines use GitHub Actions secrets (repo → Settings → Secrets).
# Rotation is handled by KMS (terraform/kms.tf) without touching source code.
PAYMENT_GATEWAY_KEY = os.environ["PAYMENT_GATEWAY_KEY"]    # SAFE — sourced from env


# ─── CWE-89 remediation: parameterised query ─────────────────────────────────
# The '?' placeholder is a bound parameter. The database driver handles all escaping.
# User input is NEVER concatenated into the query string — it is passed separately.
# No SQL injection is possible regardless of what user_id contains.
def get_payment_details(user_id: str):
    conn = sqlite3.connect("payments.db")
    cursor = conn.cursor()
    query = "SELECT card_number, amount FROM payments WHERE user_id = ?"   # SAFE
    cursor.execute(query, (user_id,))   # user_id is a bind parameter, not SQL
    return cursor.fetchall()


# ─── CWE-78 remediation: allowlist + subprocess with list args ───────────────
# 1. report_name is validated against a strict allowlist (only a-z, 0-9, _ -)
#    Any payload like "jan; curl ..." is rejected before it reaches the shell.
# 2. subprocess.run() with a list (not a string) never invokes a shell at all.
#    Even if the allowlist had a gap, shell metacharacters are inert as list elements.
def generate_payment_report(report_name: str):
    if not re.fullmatch(r"[a-z0-9_-]{1,64}", report_name):
        raise ValueError(f"Invalid report name: {report_name!r}")
    subprocess.run(["generate_report.sh", report_name], check=True, shell=False)   # SAFE


# ─── CWE-327 remediation: PBKDF2-HMAC-SHA256 ────────────────────────────────
# PBKDF2 with a unique random salt and 600,000 iterations meets:
#   NIST SP 800-132 (key derivation for password storage)
#   PCI-DSS Requirement 3.5 (strong cryptography for stored sensitive data)
# The salt ensures two identical card numbers produce different hashes.
# 600,000 iterations makes brute-force attacks computationally infeasible.
def mask_card_number(card_number: str) -> str:
    salt = secrets.token_bytes(32)
    dk = hashlib.pbkdf2_hmac("sha256", card_number.encode(), salt, 600_000)
    return salt.hex() + ":" + dk.hex()   # SAFE — salt stored alongside the hash


# ─── CWE-502 remediation: JSON with schema validation ────────────────────────
# json.loads() has no code execution surface — it only parses data types.
# The payload is then validated against required keys before any field is trusted.
# If the session store needs richer types, use a typed schema validator (e.g. pydantic).
def restore_payment_session(session_blob: bytes) -> dict:
    session = json.loads(session_blob)   # SAFE — no arbitrary code execution
    required_keys = {"user_id", "expires_at", "cart_total_pence"}
    if not required_keys.issubset(session):
        raise ValueError(f"Malformed session — missing keys: {required_keys - session.keys()}")
    return session
