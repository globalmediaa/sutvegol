<?php
declare(strict_types=1);

require dirname(__DIR__) . '/vendor/autoload.php';

function envv(string $key, ?string $default = null): ?string {
    static $loaded = false;
    if (!$loaded) {
        $loaded = true;
        $file = dirname(__DIR__) . '/.env';
        if (is_file($file)) {
            foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
                if (str_starts_with($line, '#') || !str_contains($line, '=')) continue;
                [$k, $v] = explode('=', $line, 2);
                $_ENV[trim($k)] = trim($v, " \t\n\r\0\x0B\"");
            }
        }
    }
    return $_ENV[$key] ?? getenv($key) ?: $default;
}

function db(): PDO {
    static $pdo;
    return $pdo ??= new PDO(envv('DB_DSN') ?? '', envv('DB_USER') ?? '', envv('DB_PASS') ?? '', [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
}

function body(): array {
    $value = json_decode(file_get_contents('php://input'), true);
    if (!is_array($value)) fail('invalid_json', 'Geçersiz istek.', 400);
    return $value;
}

function output(array $value, int $status = 200): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function fail(string $code, string $message, int $status = 422): never {
    output(['ok' => false, 'error' => ['code' => $code, 'message' => $message]], $status);
}

function public_id(int $bytes = 13): string { return strtoupper(substr(bin2hex(random_bytes($bytes)), 0, $bytes * 2)); }
function username_key(string $value): string { return mb_strtolower(trim($value), 'UTF-8'); }
function valid_username(string $value): bool { return (bool) preg_match('/^[a-zA-Z0-9_]{3,20}$/', $value); }

function rate_limit(string $scope, int $max = 20, int $seconds = 60): void {
    $window = date('Y-m-d H:i:s', intdiv(time(), $seconds) * $seconds);
    $bucket = hash('sha256', $scope . '|' . ($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
    db()->prepare('INSERT INTO api_rate_limits(bucket,window_start,hits) VALUES(?,?,1) ON DUPLICATE KEY UPDATE hits=hits+1')->execute([$bucket,$window]);
    $query=db()->prepare('SELECT hits FROM api_rate_limits WHERE bucket=? AND window_start=?'); $query->execute([$bucket,$window]);
    if ((int)$query->fetchColumn()>$max) fail('rate_limited','Çok fazla deneme yaptın. Biraz bekle.',429);
}

function access_token(array $user): string {
    $now = time();
    return Firebase\JWT\JWT::encode([
        'iss' => envv('APP_URL'), 'sub' => (string) $user['id'], 'pid' => $user['public_id'],
        'iat' => $now, 'exp' => $now + 900,
    ], envv('APP_KEY') ?? '', 'HS256');
}

function current_user(): array {
    if (!preg_match('/^Bearer\s+(.+)$/i', $_SERVER['HTTP_AUTHORIZATION'] ?? '', $match)) {
        fail('unauthorized', 'Oturum gerekli.', 401);
    }
    try {
        $claims = Firebase\JWT\JWT::decode($match[1], new Firebase\JWT\Key(envv('APP_KEY') ?? '', 'HS256'));
    } catch (Throwable $error) {
        fail('unauthorized', 'Oturum süresi doldu.', 401);
    }
    $query = db()->prepare('SELECT * FROM users WHERE id=? AND status="active"');
    $query->execute([(int) $claims->sub]);
    return $query->fetch() ?: fail('unauthorized', 'Hesap kullanılamıyor.', 401);
}

function public_user(array $user): array {
    return [
        'id' => $user['public_id'], 'email' => $user['email'], 'username' => $user['username'],
        'displayName' => $user['display_name'], 'avatarUrl' => $user['avatar_url'],
        'requiresUsername' => $user['username'] === null,
    ];
}

function issue_session(array $user): never {
    $refresh = bin2hex(random_bytes(32));
    db()->prepare('INSERT INTO refresh_tokens(user_id,token_hash,device_name,expires_at) VALUES(?,?,?,DATE_ADD(NOW(),INTERVAL 90 DAY))')
        ->execute([$user['id'], hash('sha256', $refresh), substr($_SERVER['HTTP_USER_AGENT'] ?? 'unknown', 0, 120)]);
    output(['ok' => true, 'accessToken' => access_token($user), 'refreshToken' => $refresh,
        'expiresIn' => 900, 'user' => public_user($user)]);
}

function identity_claims(string $provider, string $token): array {
    $url = $provider === 'apple' ? 'https://appleid.apple.com/auth/keys' : 'https://www.googleapis.com/oauth2/v3/certs';
    $cache = sys_get_temp_dir() . '/sutvegol-' . $provider . '-jwks.json';
    if (!is_file($cache) || filemtime($cache) < time() - 21600) {
        $raw = @file_get_contents($url);
        if (!$raw) fail('provider_unavailable', 'Giriş servisine ulaşılamadı.', 503);
        file_put_contents($cache, $raw);
    }
    try {
        $keys = Firebase\JWT\JWK::parseKeySet(json_decode(file_get_contents($cache), true));
        $claims = (array) Firebase\JWT\JWT::decode($token, $keys);
    } catch (Throwable $error) {
        fail('invalid_identity', 'Kimlik doğrulanamadı.', 401);
    }
    $allowed = $provider === 'apple'
        ? [envv('APPLE_CLIENT_ID')]
        : array_map('trim', explode(',', envv('GOOGLE_CLIENT_IDS', '') ?? ''));
    if (!in_array((string) ($claims['aud'] ?? ''), $allowed, true)) fail('invalid_identity', 'Uygulama kimliği eşleşmedi.', 401);
    if ($provider === 'apple' && ($claims['iss'] ?? '') !== 'https://appleid.apple.com') fail('invalid_identity', 'Apple kimliği geçersiz.', 401);
    return $claims;
}
