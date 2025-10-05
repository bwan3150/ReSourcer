#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

main() {
    print_status "Starting re-sourcer rebuild process..."
    
    print_status "Looking for and terminating existing re-sourcer processes..."
    if pkill -f re-sourcer; then
        print_status "Terminated existing processes"
        sleep 1
    else
        print_warning "No running re-sourcer processes found"
    fi
    
    print_status "Building project (release mode)..."
    if cargo build --release; then
        print_status "Build successful"
    else
        print_error "Build failed"
        exit 1
    fi
    
    print_status "Launching re-sourcer..."
    if [ -f "./target/release/re-sourcer" ]; then
        ./target/release/re-sourcer
    else
        print_error "Executable not found: ./target/release/re-sourcer"
        exit 1
    fi
}

main "$@"
