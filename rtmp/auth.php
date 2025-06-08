<?php
// Định nghĩa đường dẫn đến file user credentials
$json_data = file_get_contents('server.json');

// Phân tích cú pháp JSON để lấy dữ liệu
$data = json_decode($json_data, true);

// Kiểm tra xem dữ liệu có đúng không
if ($data === null || !isset($data['apps'])) {
    http_response_code(500); // Lỗi server nếu JSON không hợp lệ hoặc không có key 'apps'
    exit("Lỗi: Không thể đọc file JSON.");
}

// Lấy các tham số từ chuỗi truy vấn
$app_name = $_GET['app'] ?? '';
$stream_name = $_GET['name'] ?? '';
$user = $_GET['user'] ?? '';
$password = $_GET['password'] ?? '';

$is_valid = false;

// Kiểm tra từng mục trong danh sách apps
foreach ($data['apps'] as $app) {
    // Kiểm tra các điều kiện xác thực
    if (
        isset($app[2], $app[3], $app[4], $app[5]) &&
        $app[2] === $app_name &&
        $app[3] === $stream_name &&
        $app[4] === $user &&
        (string)$app[5] === $password
    ) {
        $is_valid = true;
        break;
    }
}

// Phản hồi dựa trên kết quả xác thực
if ($is_valid) {
    http_response_code(200); // Xác thực thành công
} else {
    http_response_code(401); // Xác thực thất bại
}
?>
