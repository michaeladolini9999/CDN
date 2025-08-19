<?php
date_default_timezone_set('Asia/Ho_Chi_Minh');
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

    // 🔹 Lấy start time từ file tạm
    $tmp_file = "/tmp/rtmp_start_{$app_name}_{$stream_name}.txt";
    $duration_str = "";
    if (file_exists($tmp_file)) {
        $start_ts = (int)file_get_contents($tmp_file);
        $duration = time() - $start_ts;
        unlink($tmp_file); // xoá file sau khi tính

        // Format duration (hh:mm:ss)
        $h = floor($duration / 3600);
        $m = floor(($duration % 3600) / 60);
        $s = $duration % 60;
        $duration_str = sprintf(" (Duration: %02d:%02d:%02d)", $h, $m, $s);
    }

    $message = "{$time_str}\nChannel: *{$app_name}/{$stream_name}* stopped{$duration_str}";

    $telegramUrl = "https://api.telegram.org/bot{$botToken}/sendMessage";
    file_get_contents(
        $telegramUrl . "?chat_id={$chatId}&text=" . urlencode($message) . "&parse_mode=Markdown"
    );

    http_response_code(200);
} else {
    http_response_code(401);
}
?>

