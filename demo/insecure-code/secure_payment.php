<?php
// SECURE VERSION — correct PHP for each vulnerability in vulnerable_payment.php.
// Patterns follow the OWASP PHP Security Cheat Sheet and PCI-DSS DSS v4.0.
// declare(strict_types=1) enforces type safety at the engine level.
declare(strict_types=1);


// ─── CWE-798 remediation: environment variables, never source code ────────────
// Credentials are injected at runtime via K8s Secrets (k8s/rbac/rbac.yaml)
// or GCP Workload Identity (terraform/gke.tf). The application code never
// contains or even knows credential values — it only knows the env var name.
// If the env var is missing, we fail loudly (misconfiguration is caught at startup).
$db_password = getenv('DB_PASSWORD')
    ?: throw new RuntimeException('DB_PASSWORD environment variable is not set');
$api_key = getenv('PAYMENT_GATEWAY_KEY')
    ?: throw new RuntimeException('PAYMENT_GATEWAY_KEY environment variable is not set');


// ─── CWE-89 remediation: PDO prepared statement ──────────────────────────────
// The :id placeholder is a bind parameter — no user input ever appears in SQL.
// Even a payload of "1 OR 1=1" is treated as a literal string value, not SQL.
// Type validation (ctype_digit) adds a second layer: non-numeric IDs are rejected
// before they reach the database driver at all.
function get_payment(PDO $pdo, string $payment_id): array
{
    if (!ctype_digit($payment_id)) {
        throw new InvalidArgumentException('payment_id must be a positive integer');
    }
    $stmt = $pdo->prepare('SELECT id, amount, status FROM payments WHERE id = :id');
    $stmt->execute([':id' => (int) $payment_id]);
    return $stmt->fetchAll(PDO::FETCH_ASSOC);  // SAFE
}


// ─── CWE-79 remediation: htmlspecialchars() output encoding ──────────────────
// htmlspecialchars() converts <, >, ", ', & to HTML entities.
// ENT_QUOTES ensures both single and double quotes are encoded (prevents attribute injection).
// Specifying 'UTF-8' explicitly prevents charset-based bypass attacks.
// For rich HTML output, use a template engine with auto-escaping (e.g. Twig).
function show_payment_status(): void
{
    $raw_status = $_GET['status'] ?? '';
    $status = htmlspecialchars($raw_status, ENT_QUOTES, 'UTF-8');  // SAFE
    echo "<div class='status'>Payment status: " . $status . "</div>";
}


// ─── CWE-78 remediation: allowlist + escapeshellarg() ────────────────────────
// Two-layer defence:
//   1. Regex allowlist: only accept decimal numbers with up to 2 decimal places.
//      A payload like "100; curl attacker.com" fails the regex and is rejected.
//   2. escapeshellarg(): wraps the value in single quotes for the shell, so even
//      if the allowlist had a gap, metacharacters cannot break out of the argument.
function generate_receipt(string $amount): void
{
    if (!preg_match('/^\d+(\.\d{1,2})?$/', $amount)) {
        throw new InvalidArgumentException('Invalid amount format: ' . $amount);
    }
    $safe_amount = escapeshellarg($amount);
    exec('generate_receipt.sh ' . $safe_amount, $output, $exit_code);  // SAFE
    if ($exit_code !== 0) {
        throw new RuntimeException('Receipt generation failed');
    }
}


// ─── CWE-22 remediation: allowlist map of templates ─────────────────────────
// The user can only request a name from a fixed list.
// The file path is never derived from user input — the map lookup selects
// a hardcoded server-side path. Path traversal is structurally impossible.
function load_template(string $name): void
{
    $allowed = [
        'success' => '/var/www/templates/payment-success.php',
        'failure' => '/var/www/templates/payment-failure.php',
        'pending' => '/var/www/templates/payment-pending.php',
    ];

    if (!array_key_exists($name, $allowed)) {
        throw new InvalidArgumentException("Unknown template name: {$name}");
    }

    include $allowed[$name];  // SAFE — path is a server-side constant
}


// ─── CWE-327 remediation: HMAC-SHA256 with a secret key ─────────────────────
// HMAC-SHA256 with a randomly generated server-side key meets PCI-DSS Req 3.4.
// The key is stored in an environment variable (never in code).
// HMAC is used (not plain SHA-256) because it resists length-extension attacks
// and requires the attacker to know the key to produce a valid hash.
// For passwords, prefer password_hash() with PASSWORD_ARGON2ID instead.
function hash_card_number(string $card_number): string
{
    $hmac_key = getenv('CARD_HASH_KEY')
        ?: throw new RuntimeException('CARD_HASH_KEY environment variable is not set');
    return hash_hmac('sha256', $card_number, $hmac_key);  // SAFE
}
