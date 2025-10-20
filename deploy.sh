#!/bin/bash

set -euo pipefail

# ============================================================================
# DevOps Automated Deployment Script
# Stage 1 Task - Production Grade Bash Script
# ============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "${LOG_DIR}"

# ============================================================================
# LOGGING AND ERROR HANDLING
# ============================================================================

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}✓ $@${NC}" | tee -a "${LOG_FILE}"
    log "SUCCESS" "$@"
}

log_error() {
    echo -e "${RED}✗ $@${NC}" | tee -a "${LOG_FILE}"
    log "ERROR" "$@"
}

log_info() {
    echo -e "${BLUE}ℹ $@${NC}" | tee -a "${LOG_FILE}"
    log "INFO" "$@"
}

log_warning() {
    echo -e "${YELLOW}⚠ $@${NC}" | tee -a "${LOG_FILE}"
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
    local repo_dir="./${repo_name}"
    
    # Add PAT to repo URL for authentication
    local authenticated_url="${GIT_REPO/https:\/\//https:\/\/${PAT}@}"
    
    if [[ -d "$repo_dir" ]]; then
        log_info "Repository already exists at $repo_dir, pulling latest changes..."
        cd "$repo_dir"
        git checkout "$BRANCH" || git checkout -b "$BRANCH" origin/"$BRANCH"
        git pull origin "$BRANCH"
        cd ..
        log_success "Repository updated"
    else
        log_info "Cloning repository..."
        git clone --branch "$BRANCH" "$authenticated_url" "$repo_dir"
        log_success "Repository cloned"
    fi
    
    REPO_DIR="$repo_dir"
}

# ============================================================================
# STEP 3: VERIFY DOCKERFILE OR DOCKER-COMPOSE EXISTS
# ============================================================================

verify_docker_files() {
    log_info "=== STEP 3: Verify Docker Configuration ==="
    
    cd "$REPO_DIR"
    
    if [[ -f "Dockerfile" ]]; then
        log_success "Dockerfile found"
        DOCKER_METHOD="dockerfile"
    elif [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        log_success "docker-compose.yml found"
        DOCKER_METHOD="compose"
    else
        log_error "Neither Dockerfile nor docker-compose.yml found in repository"
        exit 1
    fi
    
    cd - > /dev/null
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
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" << 'REMOTE_COMMANDS'
        set -e
        
        echo "Updating system packages..."
        sudo apt-get update -y > /dev/null
        sudo apt-get upgrade -y > /dev/null
        
        echo "Installing Docker..."
        if ! command -v docker &> /dev/null; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            rm get-docker.sh
            echo "Docker installed successfully"
        else
            echo "Docker already installed: $(docker --version)"
        fi
        
        echo "Installing Docker Compose..."
        if ! command -v docker-compose &> /dev/null; then
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            echo "Docker Compose installed successfully"
        else
            echo "Docker Compose already installed: $(docker-compose --version)"
        fi
        
        echo "Installing Nginx..."
        if ! command -v nginx &> /dev/null; then
            sudo apt-get install -y nginx > /dev/null
            echo "Nginx installed successfully"
        else
            echo "Nginx already installed: $(nginx -v 2>&1)"
        fi
        
        echo "Adding user to Docker group..."
        if ! groups $(whoami) | grep -q docker; then
            sudo usermod -aG docker $(whoami)
            echo "User added to Docker group"
        fi
        
        echo "Enabling and starting Docker service..."
        sudo systemctl enable docker
        sudo systemctl start docker
        
        echo "Enabling and starting Nginx service..."
        sudo systemctl enable nginx
        sudo systemctl start nginx
        
        echo "All services installed and running"
REMOTE_COMMANDS
    
    log_success "Remote environment prepared"
}

# ============================================================================
# STEP 6: DEPLOY DOCKERIZED APPLICATION
# ============================================================================

deploy_application() {
    log_info "=== STEP 6: Deploying Dockerized Application ==="
    
    local app_name=$(basename "$REPO_DIR")
    
    # Transfer files to remote server
    log_info "Transferring project files to remote server..."
    scp -i "$SSH_KEY" -r -o StrictHostKeyChecking=no "$REPO_DIR" \
        "${SSH_USER}@${SERVER_IP}:/tmp/" || true
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" << REMOTE_DEPLOY
        set -e
        cd /tmp/${app_name}
        
        echo "Building and deploying containers..."
        if [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
            docker-compose down -v 2>/dev/null || true
            docker-compose up -d
            echo "Containers started with docker-compose"
        else
            docker build -t ${app_name}:latest .
            docker ps -a | grep ${app_name} && docker stop ${app_name} && docker rm ${app_name} || true
            docker run -d --name ${app_name} -p ${APP_PORT}:${APP_PORT} ${app_name}:latest
            echo "Container started with docker run"
        fi
        
        echo "Waiting for container to be healthy..."
        sleep 5
        
        echo "Checking container status..."
        docker ps -a | grep ${app_name}
        
        echo "Container logs:"
        docker logs ${app_name} | tail -20
REMOTE_DEPLOY
    
    log_success "Application deployed successfully"
}

# ============================================================================
# STEP 7: CONFIGURE NGINX REVERSE PROXY
# ============================================================================

configure_nginx() {
    log_info "=== STEP 7: Configuring Nginx Reverse Proxy ==="
    
    local config_content="server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}"
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" << REMOTE_NGINX
        set -e
        
        echo "Creating Nginx configuration..."
        echo '${config_content}' | sudo tee /etc/nginx/sites-available/default > /dev/null
        
        echo "Testing Nginx configuration..."
        sudo nginx -t
        
        echo "Reloading Nginx..."
        sudo systemctl reload nginx
        
        echo "Nginx configured successfully"
REMOTE_NGINX
    
    log_success "Nginx reverse proxy configured"
}

# ============================================================================
# STEP 8: VALIDATE DEPLOYMENT
# ============================================================================

validate_deployment() {
    log_info "=== STEP 8: Validating Deployment ==="
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" << REMOTE_VALIDATE
        set -e
        
        echo "Checking Docker service..."
        sudo systemctl is-active --quiet docker && echo "✓ Docker is running" || echo "✗ Docker is not running"
        
        echo "Checking running containers..."
        docker ps
        
        echo "Checking Nginx service..."
        sudo systemctl is-active --quiet nginx && echo "✓ Nginx is running" || echo "✗ Nginx is not running"
        
        echo "Testing local connectivity..."
        curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://127.0.0.1 || echo "Local curl test failed"
REMOTE_VALIDATE
    
    log_info "Testing remote connectivity..."
    if curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" "http://${SERVER_IP}" > /dev/null 2>&1; then
        log_success "Remote connectivity test passed"
    else
        log_warning "Remote connectivity test - ensure firewall allows HTTP traffic"
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

# Run main function
main "$@"