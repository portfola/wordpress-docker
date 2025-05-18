#!/bin/bash
set -euo pipefail

echo "=== Platform Detection ==="

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "OS: Linux"
    PLATFORM="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "OS: macOS"
    PLATFORM="macos"
elif [[ "$OSTYPE" == "cygwin" ]]; then
    echo "OS: Windows (Cygwin)"
    PLATFORM="windows"
elif [[ "$OSTYPE" == "msys" ]]; then
    echo "OS: Windows (MSYS/Git Bash)"
    PLATFORM="windows"
elif [[ "$OSTYPE" == "win32" ]]; then
    echo "OS: Windows"
    PLATFORM="windows"
else
    echo "OS: Unknown ($OSTYPE)"
    PLATFORM="unknown"
fi

# Check Docker
if command -v docker &> /dev/null; then
    echo "Docker: Installed ($(docker --version))"
    if docker ps &> /dev/null; then
        echo "Docker: Running"
    else
        echo "Docker: Not running or permission denied"
    fi
else
    echo "Docker: Not installed"
    exit 1
fi

# Check Docker Compose
if command -v docker-compose &> /dev/null; then
    echo "Docker Compose: Installed ($(docker-compose --version))"
elif docker compose version &> /dev/null; then
    echo "Docker Compose: Installed ($(docker compose version))"
    echo "Note: Using 'docker compose' command"
else
    echo "Docker Compose: Not installed"
    exit 1
fi

# WSL2 detection (Windows only)
if [[ "$PLATFORM" == "windows" ]]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "WSL: Running in WSL2"
        echo "Docker Desktop: Using WSL2 integration"
    else
        echo "WSL: Not detected"
    fi
fi

echo "=== Platform check complete ==="