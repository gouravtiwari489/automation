#!/bin/bash

# Function to check if a command is available
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check if a port is in use and kill the process
kill_if_port_in_use() {
  local port=$1
  if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
    echo "Port $port is already in use. Killing the process..."
    kill -9 $(lsof -Pi :$port -sTCP:LISTEN -t) >/dev/null 2>&1
    sleep 2
  fi
}

# Function to print dynamic waiting dots
print_waiting_dots() {
  local duration=$1
  local dot_interval=1
  local elapsed_time=0

  while [ $elapsed_time -lt $duration ]; do
    sleep $dot_interval
    printf "."
    elapsed_time=$((elapsed_time + dot_interval))
  done

  echo
}

# Create a log file to store all logs
log_file=$(pwd)/all_logs.txt
touch "$log_file"

# Redirect all output to the log file
exec > >(tee -a "$log_file") 2>&1

# Check if jq is installed, if not, install it
if ! command_exists jq; then
  echo "jq is not installed. Installing jq..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install jq
  else
    echo "Unsupported OS. Please install jq manually: https://stedolan.github.io/jq/download/"
    exit 1
  fi
fi

# Gradle build
echo -n "Build is in progress"
./gradlew build > build.log 2>&1 &

# Print dynamic waiting dots during build
print_waiting_dots 10

# Check if build was successful
if [ $? -ne 0 ]; then
  echo "Failure: Gradle build failed. Exiting script."
  exit 1
fi

echo "Success: Build is successful."

# Initialize variables
success=false
port=8080

# Kill the port if it is already in use
kill_if_port_in_use $port

# Gradle bootRun with the selected port
echo -n "Starting the server. This may take a moment"
./gradlew bootRun -Dserver.port=$port > server_logs.txt 2>&1 &

# Print dynamic waiting dots during server startup
print_waiting_dots 30

# Check if bootRun was successful
if [ $? -eq 0 ]; then
  echo "Success: Gradle bootRun successful on port $port."
  success=true
else
  echo "Failure: Failed to start on port $port. Exiting script."
fi

# Kill the server process
pkill -f ".*org.gradle.wrapper.*$port" >/dev/null 2>&1

# If bootRun was not successful
if [ "$success" = false ]; then
  echo "Failure: Application failed to start. Exiting script."
  exit 1
fi

# Server is up and running successfully, print message
echo "Success: Server is working fine."
echo "Success: Build is working fine."

# Prompt for commit message
read -p "Enter commit message: " commit_message

# Prompt for branch name
read -p "Enter branch name: " branch_name

# Git add, commit, and push
git add .
git commit -m "$commit_message"

# Check if the commit and push were successful
if git push origin "$branch_name"; then
  echo "Success: Changes successfully pushed to branch $branch_name."
  echo "Success: Your changes are ready to be reviewed and merged."

  # Provide a clickable link to the all logs file
  echo "Log file: file://$log_file"
else
  echo "Failure: Failed to push changes to branch $branch_name. Exiting script."
  exit 1
fi
