from flask import Flask, render_template, request, jsonify, send_file, redirect, url_for, session, flash
import mysql.connector
import pandas as pd
import configparser
import json
import subprocess
import socket
import threading
import datetime


app = Flask(__name__)
app.secret_key = 'your_secret_key'  # Replace with a strong secret key
    
# MySQL connection
def get_db_connection():
    config = configparser.ConfigParser()
    config.read('/home/ubuntu/CDN/backup_cms/mysql.ini')

    if 'backup_data' not in config:
        raise ValueError("Missing 'backup_data' section in mysql.ini")

    host = config['backup_data']['host']
    user = config['backup_data']['user']
    password = config['backup_data']['password']
    database = config['backup_data']['database']
    ssl_disabled = config['backup_data']['ssl_disabled']

    return mysql.connector.connect(
        host=host,
        user=user,
        password=password,
        database=database,
        ssl_disabled=ssl_disabled
    )
    
@app.before_request
def restrict_dashboard_access():
    if request.endpoint in ['index', 'get_data', 'download_excel'] and 'username' not in session:
        return redirect(url_for('login'))

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"]
        password = request.form["password"]

        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM users WHERE username = %s AND hashed_password = md5(%s)", (username, password))
        user = cursor.fetchone()
        cursor.close()
        conn.close()

        if user:
            session["username"] = user["username"]
            session["is_admin"] = (user["username"] == "admin")
            return redirect(url_for("index"))
        else:
            flash("Invalid username or password")
    return render_template("backup_login.html")

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

@app.route("/", methods=["GET", "POST"])
def index():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    # Admin users can see all apps, while other users can only see their own app
    if session.get("is_admin"):
        cursor.execute("SELECT DISTINCT app FROM data")
        apps = cursor.fetchall()
        cursor.execute("SELECT DISTINCT stream FROM data")
        streams = cursor.fetchall()
        cursor.execute("SELECT DISTINCT server FROM data")
        servers = cursor.fetchall()
    else:
        cursor.execute("SELECT DISTINCT app FROM data WHERE app = %s", (session["username"],))
        apps = cursor.fetchall()
        cursor.execute("SELECT DISTINCT stream FROM data WHERE app = %s", (session["username"],))
        streams = cursor.fetchall()
        cursor.execute("SELECT DISTINCT server FROM data WHERE app = %s", (session["username"],))
        servers = cursor.fetchall()

    cursor.close()
    conn.close()
    
    return render_template("backup_index.html", servers=servers, apps=apps, streams=streams, is_admin=session.get("is_admin"))

# Data retrieval with app-based restrictions
@app.route("/get_data", methods=["POST"])
def get_data():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    data = request.json
    server_name = data.get("server")
    app_name = data.get("app")
    stream_name = data.get("stream")
    time_range = data.get("time")

    if not session.get("is_admin") and app_name != session["username"]:
        return jsonify({"error": "Unauthorized access"}), 403

    detailed_query = "SELECT * FROM data WHERE 1=1"
    params = []
    if server_name:
        detailed_query += " AND server = %s"
        params.append(server_name)
    if app_name:
        detailed_query += " AND app = %s"
        params.append(app_name)
    if stream_name:
        detailed_query += " AND stream = %s"
        params.append(stream_name)
    if time_range:
        detailed_query += " AND time BETWEEN %s AND %s"
        params.extend(time_range)

    cursor.execute(detailed_query, tuple(params))
    detailed_records = cursor.fetchall()

    chart_query = """
        SELECT time,
               SUM(requests) AS total_requests,
               SUM(unique_users) AS total_unique_users,
               SUM(data_sent) AS total_data_sent
        FROM data
        WHERE 1=1
    """
    if server_name:
        chart_query += " AND server = %s"
    if app_name:
        chart_query += " AND app = %s"
    if stream_name:
        chart_query += " AND stream = %s"
    if time_range:
        chart_query += " AND time BETWEEN %s AND %s"

    chart_query += " GROUP BY time ORDER BY time"
    cursor.execute(chart_query, tuple(params))
    chart_records = cursor.fetchall()

    total_data_sent = sum(record["total_data_sent"] for record in chart_records if record["total_data_sent"] is not None)

    cursor.close()
    conn.close()

    return jsonify({"records": detailed_records, "chart_data": chart_records, "total_data_sent": total_data_sent})

@app.route("/download_excel", methods=["POST"])
def download_excel():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    data = request.json
    server_name = data.get("server")
    app_name = data.get("app")
    stream_name = data.get("stream")
    time_range = data.get("time")

    query = "SELECT * FROM data WHERE 1=1"
    params = []
    if server_name:
        query += " AND server = %s"
        params.append(server_name)
    if app_name:
        query += " AND app = %s"
        params.append(app_name)
    if stream_name:
        query += " AND stream = %s"
        params.append(stream_name)
    if time_range:
        query += " AND time BETWEEN %s AND %s"
        params.extend(time_range)

    cursor.execute(query, tuple(params))
    records = cursor.fetchall()

    cursor.close()
    conn.close()

    df = pd.DataFrame(records).drop(columns=["id"], errors="ignore")
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    file_path = f"/tmp/data_export_{timestamp}.xlsx"
    df.to_excel(file_path, index=False)

    return send_file(file_path, as_attachment=True, download_name="data_export.xlsx")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
