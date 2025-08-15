import os
import csv
import socket
import mysql.connector
from datetime import datetime
import configparser
import logging
import time
import random

# === Random delay to avoid simultaneous cron execution across VPS ===
time.sleep(random.randint(10, 60))

# Configure logging to track synchronization process
logging.basicConfig(
    filename='/home/ubuntu/CDN/log/database.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Read database configuration from mysql.ini
config = configparser.ConfigParser()
config.read('/home/ubuntu/CDN/mysql.ini')

# Local database configuration
DB_CONFIG_LOCAL = {
    'host': config['mysql']['host'],
    'user': config['mysql']['user'],
    'password': config['mysql']['password'],
    'database': config['mysql']['database'],
    'ssl_disabled': config['mysql']['ssl_disabled'],
    'autocommit': True  # ✅ Enable autocommit
}

# Backup database configuration
DB_CONFIG_BACKUP = {
    'host': config['backup']['host'],
    'user': config['backup']['user'],
    'password': config['backup']['password'],
    'database': config['backup']['database'],
    'ssl_disabled': config['backup']['ssl_disabled'],
    'autocommit': True  # ✅ Enable autocommit
}

FILE_PATH = '/home/ubuntu/CDN/data/data.csv'
HOSTNAME = socket.gethostname()
xfactor = 2

def get_last_sync_time(cursor, hostname=None):
    """Retrieve the most recent synchronization time from the database."""
    try:
        if hostname:
            query = "SELECT MAX(time) FROM data WHERE server = %s"
            cursor.execute(query, (hostname,))
        else:
            query = "SELECT MAX(time) FROM data"
            cursor.execute(query)
        result = cursor.fetchone()[0]
        return result if result else datetime.strptime('1970-01-01 00:00:00', "%Y-%m-%d %H:%M:%S")
    except Exception as e:
        logging.error(f"Error retrieving last sync time: {e}")
        raise

def sync_to_local(file_path, db_config, hostname):
    """Synchronize data to the local database (batch insert)."""
    conn_local = None
    try:
        conn_local = mysql.connector.connect(**db_config)
        cursor_local = conn_local.cursor()

        # 1 request: lấy thời điểm sync cuối cùng
        last_sync_time_local = get_last_sync_time(cursor_local)

        # Gom dữ liệu vào list
        data_to_insert = []
        with open(file_path, 'r') as file:
            reader = csv.DictReader(file)
            for row in reader:
                time_obj = datetime.strptime(row['Time'], "%m/%d/%Y %H:%M")
                if time_obj >= last_sync_time_local:
                    app = row['App']
                    stream = row['Stream']
                    requests = int(row['Requests'])
                    unique_users = int(row['Unique Users'])
                    data_sent = int(row['Data Sent (bytes)']) * xfactor
                    data_to_insert.append(
                        (time_obj, hostname, app, stream, requests, unique_users, data_sent)
                    )

        if data_to_insert:
            # 1 request: batch insert/update
            query = """
            INSERT INTO data (time, server, app, stream, requests, unique_users, data_sent)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE
                requests = VALUES(requests),
                unique_users = VALUES(unique_users),
                data_sent = VALUES(data_sent)
            """
            cursor_local.executemany(query, data_to_insert)

        logging.info(f"Successfully synchronized {len(data_to_insert)} rows to local database.")

    except Exception as e:
        logging.error(f"Error during local synchronization: {e}")
    finally:
        if conn_local and conn_local.is_connected():
            conn_local.close()

def sync_to_backup(file_path, db_config, hostname):
    """Synchronize data to the backup database (batch insert)."""
    conn_backup = None
    try:
        conn_backup = mysql.connector.connect(**db_config)
        cursor_backup = conn_backup.cursor()

        last_sync_time_backup = get_last_sync_time(cursor_backup, hostname)

        data_to_insert = []
        with open(file_path, 'r') as file:
            reader = csv.DictReader(file)
            for row in reader:
                time_obj = datetime.strptime(row['Time'], "%m/%d/%Y %H:%M")
                if time_obj >= last_sync_time_backup:
                    app = row['App']
                    stream = row['Stream']
                    requests = int(row['Requests'])
                    unique_users = int(row['Unique Users'])
                    data_sent = int(row['Data Sent (bytes)']) * xfactor
                    data_to_insert.append(
                        (time_obj, hostname, app, stream, requests, unique_users, data_sent)
                    )

        if data_to_insert:
            # 1 request: batch insert/update
            query = """
            INSERT INTO data (time, server, app, stream, requests, unique_users, data_sent)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE
                requests = VALUES(requests),
                unique_users = VALUES(unique_users),
                data_sent = VALUES(data_sent)
            """
            cursor_backup.executemany(query, data_to_insert)

        logging.info(f"Successfully synchronized {len(data_to_insert)} rows to backup database.")

    except Exception as e:
        logging.error(f"Error during backup synchronization: {e}")
    finally:
        if conn_backup and conn_backup.is_connected():
            conn_backup.close()

if __name__ == "__main__":
    if not os.path.exists(FILE_PATH):
        logging.warning("File data.csv not found. Exiting.")
    else:
        sync_to_local(FILE_PATH, DB_CONFIG_LOCAL, HOSTNAME)
        sync_to_backup(FILE_PATH, DB_CONFIG_BACKUP, HOSTNAME)
