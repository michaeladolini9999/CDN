#!/bin/bash

ini_file="/home/ubuntu/CDN/backup_cms/mysql.ini"

get_ini_value() {
  section=$1
  key=$2
  value=$(awk -F '=' -v section="[$section]" -v key="$key" '
    $0 ~ section {in_section=1}
    in_section && $1 == key {print $2; exit}
    ' "$ini_file" | xargs)
  echo "$value"
}

# Read MySQL credentials from the ini file
host=$(get_ini_value "backup_data" "host")
user=$(get_ini_value "backup_data" "user")
password=$(get_ini_value "backup_data" "password")
database=$(get_ini_value "backup_data" "database")

if [ -z "$user" ] || [ -z "$password" ] || [ -z "$database" ]; then
  echo "Please ensure mysql.ini contains the correct user, password, and database name."
  exit 1
fi

echo "Using database: $database"

echo "Choose an option:"
echo "1. Add new user"
echo "2. Delete a user"
echo "3. Change password"
echo "4. List users"
read -p "Enter your choice (1/2/3/4): " choice

case $choice in
  1)  # Add new user
    read -p "Enter username to add: " new_username
    read -sp "Enter password for new user: " new_password
    echo
    hashed_password=$(echo -n "$new_password" | md5sum | awk '{print $1}')
    sql_statement="INSERT INTO users (username, hashed_password) VALUES ('$new_username', '$hashed_password');"
    ;;

  2)  # Delete a user
    read -p "Enter username to delete: " del_username
    sql_statement="DELETE FROM users WHERE username = '$del_username';"
    ;;

  3)  # Change password
    read -p "Enter username to change password: " change_username
    read -sp "Enter new password: " new_password
    echo
    hashed_password=$(echo -n "$new_password" | md5sum | awk '{print $1}')
    sql_statement="UPDATE users SET hashed_password = '$hashed_password' WHERE username = '$change_username';"
    ;;

  4)  # List users
    sql_statement="SELECT username FROM users;"
    ;;

  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac

# Execute the SQL statement
if [ "$choice" -eq 4 ]; then
  mysql -h "$host" -u "$user" -p"$password" -D "$database" -e "$sql_statement"
else
  mysql -h "$host" -u "$user" -p"$password" -D "$database" -e "$sql_statement"

  if [ $? -eq 0 ]; then
    case $choice in
      1) echo "User $new_username has been added successfully." ;;
      2) echo "User $del_username has been deleted successfully." ;;
      3) echo "Password for user $change_username has been changed successfully." ;;
    esac
  else
    echo "Operation failed. Please check your database settings or permissions."
  fi
fi
