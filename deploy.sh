#!/bin/bash

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
  local dots=""
  local elapsed_time=0

  while [ $elapsed_time -lt $duration ]; do
    sleep $dot_interval
    printf "."
    elapsed_time=$((elapsed_time + dot_interval))
  done

  echo
}

# Gradle build
echo -n "Build is in progress"
./gradlew build > build.log 2>&1 &

# Print dynamic waiting dots during build
print_waiting_dots 10

# Check if build was successful
if [ $? -ne 0 ]; then
  echo "Gradle build failed. Exiting script."
  echo "Sorry, your changes are not ready to be pushed."
  exit 1
fi

echo "Build is successful."

# Initialize variables
success=false
port=8080

# Kill the port if it is already in use
kill_if_port_in_use $port

# Gradle bootRun with the selected port
echo -n "Starting the server. This may take a moment"
./gradlew bootRun -Dserver.port=$port > run.log 2>&1 &

# Print dynamic waiting dots during server startup
print_waiting_dots 30

# Check if bootRun was successful
if [ $? -eq 0 ]; then
  echo "Gradle bootRun successful on port $port."
  success=true
else
  echo "Failed to start on port $port. Exiting script."
  echo "Sorry, your changes are not ready to be pushed."
fi

# Kill the server process
pkill -f ".*org.gradle.wrapper.*$port" >/dev/null 2>&1

# If bootRun was not successful
if [ "$success" = false ]; then
  echo "Application failed to start. Exiting script."
  echo "Sorry, your changes are not ready to be pushed."
  exit 1
fi

# Server is up and running successfully, print message
echo "Server is working fine."

# Print success message for build
echo "Build is working fine."

# Check if the current directory is a git repository
if [ ! -d ".git" ]; then
  read -p "This directory is not a git repository. Initialize it now? (y/n): " initialize_git

  if [ "$initialize_git" == "y" ]; then
    git init
    git add .
    git commit -m "Initial commit"
    echo "Git repository initialized successfully."
  else
    echo "Exiting script. Your changes are not ready to be pushed."
    exit 1
  fi
fi

# Prompt for commit message
read -p "Enter commit message: " commit_message

# Prompt for branch name
read -p "Enter branch name: " branch_name

# Git add, commit, and push
git add .
git commit -m "$commit_message"

# Check if the commit was successful
if [ $? -eq 0 ]; then
  git push origin "$branch_name"
  if [ $? -eq 0 ]; then
    echo "Changes successfully pushed to branch $branch_name."
    echo "Your changes are ready to be reviewed and merged."

    # Start ngrok to expose build and run logs
    ngrok http 4040 -log=stdout > ngrok.log 2>&1 &

    # Wait for ngrok to generate the public URLs
    sleep 5

    build_log_url=$(curl -s localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url')
    run_log_url=$(curl -s localhost:4040/api/tunnels | jq -r '.tunnels[1].public_url')

    echo "You can watch the build logs at: $build_log_url"
    echo "You can watch the run logs at: $run_log_url"
  else
    echo "Failed to push changes. Exiting script."
    echo "Sorry, your changes are not ready to be pushed."
    exit 1
  fi
else
  echo "Failed to commit changes. Exiting script."
  echo "Sorry, your changes are not ready to be pushed."
  exit 1
fi
