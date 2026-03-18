<?php
/**
 * Simple-CI — информационная страница окружения
 * Читает manifest.json и показывает версию, окружение и статус.
 */

$manifest_path = __DIR__ . '/manifest.json';

$manifest = null;
if (file_exists($manifest_path)) {
    $json = file_get_contents($manifest_path);
    $manifest = json_decode($json, true);
}

$version     = $manifest['version'] ?? '—';
$build       = $manifest['build'] ?? '—';
$date        = $manifest['date'] ?? '—';
$environment = $manifest['environment'] ?? 'unknown';
$description = $manifest['description'] ?? '';

$env_colors = [
    'test' => '#f39c12',
    'beta' => '#3498db',
    'prod' => '#27ae60',
];
$env_labels = [
    'test' => 'TEST',
    'beta' => 'BETA',
    'prod' => 'PRODUCTION',
];

$color = $env_colors[$environment] ?? '#95a5a6';
$label = $env_labels[$environment] ?? strtoupper($environment);

header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= htmlspecialchars($label) ?> — v<?= htmlspecialchars($version) ?></title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #1a1a2e;
            color: #eee;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .card {
            background: #16213e;
            border-radius: 16px;
            padding: 40px;
            min-width: 400px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
            border-top: 4px solid <?= $color ?>;
        }
        .env-badge {
            display: inline-block;
            background: <?= $color ?>;
            color: #fff;
            padding: 6px 20px;
            border-radius: 20px;
            font-weight: 700;
            font-size: 14px;
            letter-spacing: 1px;
            margin-bottom: 24px;
        }
        .version {
            font-size: 48px;
            font-weight: 700;
            margin-bottom: 8px;
        }
        .meta {
            color: #8899aa;
            font-size: 14px;
            margin-bottom: 24px;
        }
        .meta span { margin-right: 16px; }
        .description {
            color: #aab;
            font-size: 15px;
            border-top: 1px solid #2a3a5e;
            padding-top: 16px;
        }
        .info-table {
            width: 100%;
            margin-top: 20px;
            border-collapse: collapse;
        }
        .info-table td {
            padding: 8px 0;
            border-bottom: 1px solid #2a3a5e;
            font-size: 14px;
        }
        .info-table td:first-child {
            color: #8899aa;
            width: 120px;
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="env-badge"><?= htmlspecialchars($label) ?></div>
        <div class="version">v<?= htmlspecialchars($version) ?></div>
        <div class="meta">
            <span>Build <?= htmlspecialchars($build) ?></span>
            <span><?= htmlspecialchars($date) ?></span>
        </div>
        <?php if ($description): ?>
            <div class="description"><?= htmlspecialchars($description) ?></div>
        <?php endif; ?>
        <table class="info-table">
            <tr><td>Окружение</td><td><?= htmlspecialchars($label) ?></td></tr>
            <tr><td>Версия</td><td><?= htmlspecialchars($version) ?></td></tr>
            <tr><td>Билд</td><td><?= htmlspecialchars($build) ?></td></tr>
            <tr><td>Дата</td><td><?= htmlspecialchars($date) ?></td></tr>
            <tr><td>PHP</td><td><?= PHP_VERSION ?></td></tr>
            <tr><td>Сервер</td><td><?= htmlspecialchars($_SERVER['SERVER_SOFTWARE'] ?? 'CLI') ?></td></tr>
        </table>
    </div>
</body>
</html>
