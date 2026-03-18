<?php
/**
 * Simple-CI — GitHub Webhook для автообновления TEST
 *
 * Этот файл размещается ТОЛЬКО на тестовом сервере.
 * При push в отслеживаемую ветку GitHub отправляет POST-запрос сюда,
 * и скрипт запускает git2test.sh для обновления тестового окружения.
 *
 * Настройка в GitHub:
 *   Settings → Webhooks → Add webhook
 *   Payload URL: https://test.example.com/githook.php
 *   Content type: application/json
 *   Secret: <ваш секрет из .env>
 *   Events: Just the push event
 *
 * Переменные в .env (добавляются install.sh):
 *   WEBHOOK_SECRET — секрет для проверки подписи от GitHub
 */

// --- Конфигурация ---
// Ищем .env в нескольких местах
$env_paths = [
    __DIR__ . '/.env',
    dirname(__DIR__) . '/.env',
];

$env = [];
foreach ($env_paths as $path) {
    if (file_exists($path)) {
        $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || $line[0] === '#') continue;
            if (strpos($line, '=') === false) continue;
            [$key, $value] = explode('=', $line, 2);
            $env[trim($key)] = trim(trim($value), '"\'');
        }
        break;
    }
}

$webhook_secret = $env['WEBHOOK_SECRET'] ?? '';
$git_branch     = $env['GIT_BRANCH'] ?? 'main';

// Путь к git2test.sh — ищем относительно .env
$utils_dir = '';
foreach ($env_paths as $path) {
    $candidate = dirname($path) . '/utils/git2test.sh';
    if (file_exists($candidate)) {
        $utils_dir = dirname($path) . '/utils';
        break;
    }
}

// --- Логирование ---
$log_file = __DIR__ . '/log/webhook.log';
$log_dir = dirname($log_file);
if (!is_dir($log_dir)) {
    mkdir($log_dir, 0755, true);
}

function webhook_log($message) {
    global $log_file;
    $timestamp = date('Y-m-d H:i:s');
    file_put_contents($log_file, "[$timestamp] $message\n", FILE_APPEND | LOCK_EX);
}

// --- Проверки ---

// Только POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

// Читаем тело запроса
$payload = file_get_contents('php://input');

if (empty($payload)) {
    http_response_code(400);
    webhook_log('ERROR: Empty payload');
    echo json_encode(['error' => 'Empty payload']);
    exit;
}

// Проверяем подпись GitHub (если секрет задан)
if ($webhook_secret !== '') {
    $signature = $_SERVER['HTTP_X_HUB_SIGNATURE_256'] ?? '';

    if (empty($signature)) {
        http_response_code(403);
        webhook_log('ERROR: Missing signature header');
        echo json_encode(['error' => 'Missing signature']);
        exit;
    }

    $expected = 'sha256=' . hash_hmac('sha256', $payload, $webhook_secret);

    if (!hash_equals($expected, $signature)) {
        http_response_code(403);
        webhook_log('ERROR: Invalid signature');
        echo json_encode(['error' => 'Invalid signature']);
        exit;
    }
}

// Парсим payload
$data = json_decode($payload, true);

if ($data === null) {
    http_response_code(400);
    webhook_log('ERROR: Invalid JSON');
    echo json_encode(['error' => 'Invalid JSON']);
    exit;
}

// Проверяем что это push в нужную ветку
$ref = $data['ref'] ?? '';
$expected_ref = "refs/heads/$git_branch";

if ($ref !== $expected_ref) {
    http_response_code(200);
    webhook_log("SKIP: Push to $ref (tracking $expected_ref)");
    echo json_encode(['status' => 'skipped', 'reason' => "Not tracking branch: $ref"]);
    exit;
}

// Проверяем наличие git2test.sh
if (empty($utils_dir) || !file_exists("$utils_dir/git2test.sh")) {
    http_response_code(500);
    webhook_log('ERROR: git2test.sh not found');
    echo json_encode(['error' => 'git2test.sh not found']);
    exit;
}

// --- Запуск обновления ---
$pusher = $data['pusher']['name'] ?? 'unknown';
$commits_count = count($data['commits'] ?? []);
$head_commit = $data['head_commit']['message'] ?? '—';

webhook_log("DEPLOY: Push by $pusher ($commits_count commits) — $head_commit");

// Запускаем git2test.sh в фоне, чтобы не блокировать ответ GitHub
$cmd = sprintf(
    'cd %s && bash git2test.sh --auto >> %s 2>&1 &',
    escapeshellarg($utils_dir),
    escapeshellarg($log_file)
);

exec($cmd);

webhook_log("STARTED: git2test.sh --auto");

// Отвечаем GitHub
http_response_code(200);
echo json_encode([
    'status'  => 'ok',
    'message' => "Deploying to test: $commits_count commits by $pusher",
    'branch'  => $git_branch,
]);
