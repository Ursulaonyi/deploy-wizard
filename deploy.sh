#!/bin/bash

set -euo pipefail

# ============================================================================
# DevOps Automated Deployment Script - Stage 1
# Production-Grade Bash Script for Docker Application Deployment
# ============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging setup
LOG_DIR="./logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

# ============================================================================
# LOGGING AND ERROR HANDLING
# ============================================================================

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}✓ $@${NC}"
    log "SUCCESS" "$@"
}

log_error() {
    echo -e "${RED}✗ $@${NC}"
    log "ERROR" "$@"
}

log_info() {
    echo -e "${BLUE}ℹ $@${NC}"
    log "INFO" "$@"
}

log_warning() {
    echo -e "${YELLOW}⚠ $@${NC}"
    log "WARNING" "$@"
}

# Error trap
trap 'handle_error $? $LINENO' ERR

handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    exit "${exit_code}"
}

# ============================================================================
# STEP 1: COLLECT PARAMETERS FROM USER INPUT
# ============================================================================

collect_parameters() {
    log_info "=== STEP 1: Collecting Parameters ==="
    
    # Git Repository URL
    read -p "Enter Git Repository URL: " GIT_REPO
    if [[ ! "$GIT_REPO" =~ ^https?:// ]]; then
        log_error "Invalid Git URL format"
        exit 1
    fi
    log_success "Git Repository: $GIT_REPO"
    
    # Personal Access Token
    read -sp "Enter Personal Access Token (PAT): " PAT
    echo ""
    if [[ -z "$PAT" ]]; then
        log_error "PAT cannot be empty"
        exit 1
    fi
    log_success "PAT received"
    
    # Branch name (optional, defaults to main)
    read -p "Enter Branch name (default: main): " BRANCH
    BRANCH=${BRANCH:-main}
    log_success "Branch: $BRANCH"
    
    # SSH details
    read -p "Enter SSH Username: " SSH_USER
    read -p "Enter Server IP Address: " SERVER_IP
    read -p "Enter SSH Key Path (e.g., ~/.ssh/id_rsa): " SSH_KEY
    
    # Validate SSH key exists
    SSH_KEY="${SSH_KEY/#~/$HOME}"
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH key not found at $SSH_KEY"
        exit 1
    fi
    log_success "SSH Key found: $SSH_KEY"
    
    # Application port
    read -p "Enter Application Port (internal container port): " APP_PORT
    if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]]; then
        log_error "Port must be a number"
        exit 1
    fi
    log_success "Application Port: $APP_PORT"
    
    log_success "All parameters collected successfully"
}

# ============================================================================
# STEP 2: CLONE OR UPDATE REPOSITORY
# ============================================================================

clone_or_update_repo() {
    log_info "=== STEP 2: Clone or Update Repository ==="
    
    local repo_name=$(basename "$GIT_REPO" .git)
    local timestamp=$(date +%s)
    local repo_dir="./app_${repo_name}_${timestamp}"
    
    # Add PAT to repo URL for authentication
    local authenticated_url="${GIT_REPO/https:\/\//https:\/\/${PAT}@}"
    
    log_info "Cloning repository to $repo_dir..."
    git clone --branch "$BRANCH" "$authenticated_url" "$repo_dir" 2>&1
    log_success "Repository cloned successfully"
    
    REPO_DIR="$repo_dir"
}

# ============================================================================
# STEP 3: VERIFY DOCKERFILE OR DOCKER-COMPOSE EXISTS
# ============================================================================

verify_docker_files() {
    log_info "=== STEP 3: Verify Docker Configuration ==="
    
    if [[ -f "${REPO_DIR}/Dockerfile" ]]; then
        log_success "Dockerfile found"
        DOCKER_METHOD="dockerfile"
    elif [[ -f "${REPO_DIR}/docker-compose.yml" ]] || [[ -f "${REPO_DIR}/docker-compose.yaml" ]]; then
        log_success "docker-compose.yml found"
        DOCKER_METHOD="compose"
    else
        log_error "Neither Dockerfile nor docker-compose.yml found in repository"
        exit 1
    fi
}

# ============================================================================
# STEP 4: SSH CONNECTION TEST
# ============================================================================

test_ssh_connection() {
    log_info "=== STEP 4: Testing SSH Connection ==="
    
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "${SSH_USER}@${SERVER_IP}" "echo 'SSH connection successful'" > /dev/null 2>&1; then
        log_success "SSH connection established"
    else
        log_error "Failed to establish SSH connection to ${SSH_USER}@${SERVER_IP}"
        exit 1
    fi
}

# ============================================================================
# STEP 5: PREPARE REMOTE ENVIRONMENT
# ============================================================================

prepare_remote_environment() {
    log_info "=== STEP 5: Preparing Remote Environment ==="
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" bash << 'REMOTE_SETUP'
set -e

echo "Updating system packages..."
sudo apt-get update -y > /dev/null 2>&1
sudo apt-get upgrade -y > /dev/null 2>&1

echo "Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh 2>/dev/null
    sudo sh get-docker.sh > /dev/null 2>&1
    rm get-docker.sh
else
    echo "Docker already installed"
fi

echo "Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 2>/dev/null
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "Docker Compose already installed"
fi

echo "Installing Nginx..."
if ! command -v nginx &> /dev/null; then
    sudo apt-get install -y nginx > /dev/null 2>&1
else
    echo "Nginx already installed"
fi

echo "Adding user to Docker group..."
if ! groups $(whoami) | grep -q docker; then
    sudo usermod -aG docker $(whoami)
fi

echo "Enabling and starting services..."
sudo systemctl enable docker > /dev/null 2>&1
sudo systemctl start docker > /dev/null 2>&1
sudo systemctl enable nginx > /dev/null 2>&1
sudo systemctl start nginx > /dev/null 2>&1

echo "Services ready"
REMOTE_SETUP

    log_success "Remote environment prepared"
}

# ============================================================================
# STEP 6: DEPLOY DOCKERIZED APPLICATION
# ============================================================================

deploy_application() {
    log_info "=== STEP 6: Deploying Dockerized Application ==="
    
    local app_name=$(basename "$REPO_DIR" | cut -d'_' -f2)
    
    log_info "Transferring project files to remote server..."
    scp -i "$SSH_KEY" -r -o StrictHostKeyChecking=no "$REPO_DIR" \
        "${SSH_USER}@${SERVER_IP}:/tmp/" > /dev/null 2>&1
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" bash << REMOTE_DEPLOY
set -e

APP_NAME="${app_name}"
APP_PORT="${APP_PORT}"
REPO_DIR="/tmp/$(basename ${REPO_DIR})"

cd \$REPO_DIR

echo "Building Docker image..."
docker build -t \${APP_NAME}:latest . > /dev/null 2>&1

echo "Stopping old container if exists..."
docker ps -a | grep -q \${APP_NAME} && docker stop \${APP_NAME} && docker rm \${APP_NAME} 2>/dev/null || true

echo "Starting new container..."
docker run -d --name \${APP_NAME} -p \${APP_PORT}:\${APP_PORT} \${APP_NAME}:latest

echo "Waiting for container to start..."
sleep 3

echo "Container status:"
docker ps | grep \${APP_NAME}

echo "Deployment complete"
REMOTE_DEPLOY

    log_success "Application deployed successfully"
}

# ============================================================================
# STEP 7: CONFIGURE NGINX REVERSE PROXY
# ============================================================================

configure_nginx() {
    log_info "=== STEP 7: Configuring Nginx Reverse Proxy ==="
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" bash << REMOTE_NGINX
set -e

APP_PORT="${APP_PORT}"

CONFIG_CONTENT="server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:\${APP_PORT};
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
    }
}"

echo "\$CONFIG_CONTENT" | sudo tee /etc/nginx/sites-available/default > /dev/null

echo "Testing Nginx configuration..."
sudo nginx -t > /dev/null 2>&1

echo "Reloading Nginx..."
sudo systemctl reload nginx > /dev/null 2>&1

echo "Nginx configured successfully"
REMOTE_NGINX

    log_success "Nginx reverse proxy configured"
}

# ============================================================================
# STEP 8: VALIDATE DEPLOYMENT
# ============================================================================

validate_deployment() {
    log_info "=== STEP 8: Validating Deployment ==="
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" bash << REMOTE_VALIDATE
set -e

echo "Docker service status:"
sudo systemctl is-active --quiet docker && echo "✓ Docker is running" || echo "✗ Docker is not running"

echo "Running containers:"
docker ps

echo "Nginx service status:"
sudo systemctl is-active --quiet nginx && echo "✓ Nginx is running" || echo "✗ Nginx is not running"

echo "Testing local connectivity on port 80..."
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://127.0.0.1 || echo "Local test inconclusive"

REMOTE_VALIDATE

    log_info "Testing remote connectivity..."
    if curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" "http://${SERVER_IP}" 2>/dev/null; then
        log_success "Remote connectivity test passed"
    else
        log_warning "Could not reach http://${SERVER_IP} - check firewall rules"
    fi
    
    log_success "Deployment validation completed"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "========================================="
    log_info "DevOps Stage 1 - Automated Deployment"
    log_info "Log file: $LOG_FILE"
    log_info "========================================="
    
    collect_parameters
    clone_or_update_repo
    verify_docker_files
    test_ssh_connection
    prepare_remote_environment
    deploy_application
    configure_nginx
    validate_deployment
    
    log_success "========================================="
    log_success "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    log_success "========================================="
    echo -e "${GREEN}Log file saved at: $LOG_FILE${NC}"
}

main "$@"