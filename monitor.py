import re
import time
import os
import datetime
import json
import pytz
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from collections import defaultdict
import threading

class BandwidthAnalyzer:
    def __init__(self, interval_minutes=5):
        self.interval_minutes = interval_minutes
        self.channel_data = defaultdict(lambda: defaultdict(lambda: {'requests': 0, 'unique_users': set(), 'data_sent': 0}))
        self.lock = threading.Lock()

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

                with self.lock:
                    self.channel_data[time_interval][channel_key]['requests'] += 1
                    self.channel_data[time_interval][channel_key]['unique_users'].add(client_ip)
                    self.channel_data[time_interval][channel_key]['data_sent'] += data_size

    def save_data(self):
        with self.lock:
            data_to_save = dict(self.channel_data)
            self.channel_data.clear()

        for interval, channels in data_to_save.items():
            filename = f"/home/ubuntu/CDN/data/log/bw_{interval}.csv"
            time_str = datetime.datetime.strptime(interval, "%Y-%m-%d_%H-%M").strftime("%m/%d/%Y %H:%M")

            with open(filename, 'w') as file:
                file.write("Time,App,Stream,Requests,Unique Users,Data Sent (bytes)\n")
                for channel, data in channels.items():
                    app = channel.split("/")[0]
                    stream = channel.split("/")[1]
                    file.write(f"{time_str},{app},{stream},{data['requests']},{len(data['unique_users'])},{data['data_sent']}\n")

    def check_and_save(self, current_log_time_str):
        with self.lock:
            has_data = bool(self.channel_data)
        if has_data:
            current_interval = self.get_time_interval(current_log_time_str)
            with self.lock:
                need_save = current_interval not in self.channel_data
            if need_save:
                self.save_data()

    def force_save(self):
        with self.lock:
            has_data = bool(self.channel_data)
        if has_data:
            current_interval = self.get_time_interval(datetime.datetime.now(pytz.timezone('Asia/Ho_Chi_Minh')).strftime("%d/%b/%Y:%H:%M:%S %z"))
            with self.lock:
                need_save = current_interval not in self.channel_data
            if need_save:
                self.save_data()

class LogProcessor:
    def __init__(self, bandwidth_analyzer):
        self.bandwidth_analyzer = bandwidth_analyzer
        self.request_pattern = re.compile(r'(?P<ip>\d+\.\d+\.\d+\.\d+)\s-\s-\s\[(?P<datetime>[^\]]+)\]\s"(?P<method>\w+)\s(?P<url>[^\s]+)\sHTTP/[^\s]+"\s(?P<status>\d+)\s(?P<bytes_sent>\d+)\s"[^"]*"\s"(?P<user_agent>[^"]+)"')

    def process_line(self, line):
        request_match = self.request_pattern.match(line)
        if request_match:
            self.bandwidth_analyzer.check_and_save(request_match.group('datetime'))
            self.bandwidth_analyzer.analyze_log(request_match)

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

def monitor_log(log_file):
    bandwidth_analyzer = BandwidthAnalyzer()
    log_processor = LogProcessor(bandwidth_analyzer)
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
    monitor_log(log_file_path)
