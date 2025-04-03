import re
import requests
import time
import os
import configparser
import datetime
import json
import pytz
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from collections import defaultdict

class TelegramNotifier:
    def __init__(self, config_file):
        with open(config_file, 'r') as file:
            self.config = json.load(file)

    def send_message(self, bot_token, chat_id, message):
        url = f'https://api.telegram.org/bot{bot_token}/sendMessage'
        payload = {'chat_id': chat_id, 'text': message, 'parse_mode': 'Markdown'}
        requests.post(url, data=payload)

    def get_bot_info(self, app_name, stream_name):
        for app in self.config['apps']:
            if app[1] == app_name and app[2] == stream_name:
                chat_id = app[5]
                bot_token = app[6]
                return bot_token, chat_id
        return None, None  

class BandwidthAnalyzer:
    def __init__(self, interval_minutes=5):
        self.interval_minutes = interval_minutes
        self.channel_data = defaultdict(lambda: defaultdict(lambda: {'requests': 0, 'unique_users': set(), 'data_sent': 0}))

    def get_time_interval(self, log_time_str):
        log_time = datetime.datetime.strptime(log_time_str, "%d/%b/%Y:%H:%M:%S %z")
        interval_start_minute = (log_time.minute // self.interval_minutes) * self.interval_minutes
        interval_start = log_time.replace(minute=interval_start_minute, second=0, microsecond=0)
        interval_str = interval_start.strftime("%Y-%m-%d_%H-%M")
        return interval_str

    def analyze_log(self, match):
        url_split = match.group('url').split('/')
        if len(url_split) > 4:
            if (url_split[1] == "hls"):
                app_name = url_split[2]
                stream_name = url_split[3]

                client_ip = match.group('ip')
                data_size = int(match.group('bytes_sent'))
                channel_key = f"{app_name}/{stream_name}"

                log_time_str = match.group('datetime')
                time_interval = self.get_time_interval(log_time_str)

                self.channel_data[time_interval][channel_key]['requests'] += 1
                self.channel_data[time_interval][channel_key]['unique_users'].add(client_ip)
                self.channel_data[time_interval][channel_key]['data_sent'] += data_size

    def save_data(self):
        for interval, channels in self.channel_data.items():
            filename = f"/home/ubuntu/CDN/data/log/bw_{interval}.csv"
            time_str = datetime.datetime.strptime(interval, "%Y-%m-%d_%H-%M").strftime("%m/%d/%Y %H:%M")

            with open(filename, 'w') as file:
                file.write("Time,App,Stream,Requests,Unique Users,Data Sent (bytes)\n")
                for channel, data in channels.items():
                    app = channel.split("/")[0]
                    stream = channel.split("/")[1]
                    file.write(f"{time_str},{app},{stream},{data['requests']},{len(data['unique_users'])},{data['data_sent']}\n")
        self.channel_data.clear()

    def check_and_save(self, current_log_time_str):
        if self.channel_data:
            current_interval = self.get_time_interval(current_log_time_str)
            if current_interval not in self.channel_data:
                self.save_data()

    def force_save(self):
        if self.channel_data:
            current_interval = self.get_time_interval(datetime.datetime.now(pytz.timezone('Asia/Ho_Chi_Minh')).strftime("%d/%b/%Y:%H:%M:%S %z"))
            if current_interval not in self.channel_data:
                self.save_data()

class LogProcessor:
    def __init__(self, telegram_notifier, bandwidth_analyzer):
        self.telegram_notifier = telegram_notifier
        self.bandwidth_analyzer = bandwidth_analyzer
        self.log1_pattern = re.compile(r'(?P<ip>\S+) - - \[(?P<time>.*?)\] "GET (?P<url>.*?) HTTP/1\.0" (?P<status>\d{3}) .*')
        self.log2_pattern = re.compile(r'(?P<ip>\S+) \[(?P<time>.*?)\] PUBLISH "(?P<app>\S+)" "(?P<stream>\S+)" .*? (?P<bytes_received>\d+) \d+ .* \((?P<session_time>(\d+h\s*)?(\d+m\s*)?(\d+s)?)\)')
        self.request_pattern = re.compile(r'(?P<ip>\d+\.\d+\.\d+\.\d+)\s-\s-\s\[(?P<datetime>[^\]]+)\]\s"(?P<method>\w+)\s(?P<url>[^\s]+)\sHTTP/[^\s]+"\s(?P<status>\d+)\s(?P<bytes_sent>\d+)\s"[^"]*"\s"(?P<user_agent>[^"]+)"')

    def process_line(self, line):
        log1_match = self.log1_pattern.match(line)
        log2_match = self.log2_pattern.match(line)
        request_match = self.request_pattern.match(line)

        if log1_match:
            self.process_log1(log1_match)
        elif log2_match:
            self.process_log2(log2_match)
        elif request_match:
            self.bandwidth_analyzer.check_and_save(request_match.group('datetime'))
            self.bandwidth_analyzer.analyze_log(request_match)


    def process_log1(self, match):
        status_code = int(match.group('status'))
        if status_code == 200:
            time_str = match.group('time')
            url = match.group('url')
            app_match = re.search(r'app=([\w\.]+)', url)
            stream_match = re.search(r'name=([\w\.]+)', url)
	    domain_match = re.search(r'tcurl=rtmp://([^/]+)', url)
            domain = domain_match.group(1) if domain_match else 'Unknown Domain'

            if app_match and stream_match:
                app_name = app_match.group(1)
                stream_name = stream_match.group(1)
                message = f"{time_str}\nChannel: *{app_name}/{stream_name}* started\nURL: https://{domain}:8080/hls/{app_name}/{stream_name}/index.m3u8"
                bot_token, chat_id = self.telegram_notifier.get_bot_info(app_name, stream_name)
                self.telegram_notifier.send_message(bot_token, chat_id, message)

    def process_log2(self, match):
        session_time = match.group('session_time')
        if session_time.strip() not in ["0s", "1s", "2s", "3s"]:
            time_str = match.group('time')
            time_str1 = datetime.datetime.strptime(time_str, "%d/%b/%Y:%H:%M:%S %z").strftime("%m/%d/%Y %H:%M:%S")
            app_name = match.group('app')
            stream_name = match.group('stream')
            bytes_received = match.group('bytes_received')
            message = f"{time_str}\nChannel: *{app_name}/{stream_name}* finished\nSession time: {session_time}"
            bot_token, chat_id = self.telegram_notifier.get_bot_info(app_name, stream_name)
            self.telegram_notifier.send_message(bot_token, chat_id, message)

            rtmp_csv = '/home/ubuntu/CDN/data/rtmp.csv'
            directory = os.path.dirname(rtmp_csv)
            if not os.path.exists(directory):
                os.makedirs(directory)  

            if not os.path.exists(rtmp_csv):
                with open(rtmp_csv, 'a') as file:
                    file.write("Time, App, Stream, Byte received, Session time\n")
                    file.write(f"{time_str1}, {app_name}, {stream_name}, {bytes_received}, {session_time}\n")
            else:
                with open(rtmp_csv, 'a') as file:
                    file.write(f"{time_str1}, {app_name}, {stream_name}, {bytes_received}, {session_time}\n")

class LogMonitor(FileSystemEventHandler):
    def __init__(self, log_file, log_processor):
        self.log_file = log_file
        self.log_processor = log_processor
        self.last_position = 0
        self.open_log_file()

    def open_log_file(self):
        try:
            self.file = open(self.log_file, 'r')
            self.file.seek(0, os.SEEK_END)
            self.last_position = self.file.tell()  
        except FileNotFoundError:
            print(f"[{datetime.datetime.now()}] File {self.log_file} chưa tồn tại.")
            self.file = None

    def on_modified(self, event):
        if event.src_path == self.log_file:
            if self.file is None or self.file.closed:
                self.open_log_file()
            if self.file:
                self.process_log()

    def on_created(self, event):
        if event.src_path == self.log_file:
            self.open_log_file()

    def process_log(self):
        self.file.seek(self.last_position)  
        for line in self.file:
            self.log_processor.process_line(line)
        self.last_position = self.file.tell()  

def monitor_log(log_file, server_config_file):
    telegram_notifier = TelegramNotifier(server_config_file)
    bandwidth_analyzer = BandwidthAnalyzer()
    log_processor = LogProcessor(telegram_notifier, bandwidth_analyzer)
    log_monitor = LogMonitor(log_file, log_processor)

    observer = Observer()
    observer.schedule(log_monitor, path=os.path.dirname(log_file), recursive=False)
    observer.start()

    last_check_time = time.time()  

    try:
        while True:
            if not os.path.exists(log_file):
                log_monitor.open_log_file()
            time.sleep(1)

            current_time = time.time()
            if current_time - last_check_time >= 60:  
                bandwidth_analyzer.force_save()
                last_check_time = current_time  
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

if __name__ == "__main__":
    log_file_path = "/var/log/nginx/access.log"
    server_config = "/home/ubuntu/CDN/server.json"
    monitor_log(log_file_path, server_config)
