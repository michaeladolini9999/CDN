<?php
date_default_timezone_set('Asia/Ho_Chi_Minh'); // Set timezone VN
$json_data = file_get_contents('server.json');
$data = json_decode($json_data, true);

if ($data === null || !isset($data['apps'])) {
    http_response_code(500);
    exit("Lỗi: Không thể đọc file JSON.");
}

$app_name    = $_GET['app'] ?? '';
$stream_name = $_GET['name'] ?? '';
$user        = $_GET['user'] ?? '';
$password    = $_GET['password'] ?? '';

$is_valid = false;
$chatId   = '';
$botToken = '';

foreach ($data['apps'] as $app) {
    if (
        isset($app[2], $app[3], $app[4], $app[5]) &&
        $app[2] === $app_name &&
        $app[3] === $stream_name &&
        $app[4] === $user &&
        (string)$app[5] === $password
    ) {
        $is_valid = true;
        $chatId   = $app[6];
        $botToken = $app[7];
        break;
    }
}

if ($is_valid) {
    $time_str = date("Y-m-d H:i:s");

    // 🔹 Ghi lại thời gian start vào file tạm
    $tmp_file = "/tmp/rtmp_start_{$app_name}_{$stream_name}.txt";
    file_put_contents($tmp_file, time()); // lưu timestamp

    $message = "{$time_str}\nChannel: *{$app_name}/{$stream_name}* starting";

    $telegramUrl = "https://api.telegram.org/bot{$botToken}/sendMessage";
    file_get_contents(
        $telegramUrl . "?chat_id={$chatId}&text=" . urlencode($message) . "&parse_mode=Markdown"
    );

    http_response_code(200);
} else {
    http_response_code(401);
}
?>
