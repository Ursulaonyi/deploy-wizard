# deploy-wizard

# Automated Deployment Script

A production-grade Bash script for automating the setup, deployment, and configuration of Dockerized applications on remote Linux servers.

## Features

- **Automated Repository Management**: Clone or update Git repositories with PAT authentication
- **Remote Server Setup**: Automatically installs Docker, Docker Compose, and Nginx
- **Docker Deployment**: Builds and deploys Dockerized applications (supports both Dockerfile and docker-compose.yml)
- **Nginx Reverse Proxy**: Configures Nginx to forward traffic to your containerized application
- **Comprehensive Logging**: All actions logged to timestamped log files
- **Error Handling**: Includes trap functions, validation checks, and meaningful exit codes
- **Idempotent Operations**: Can be safely re-run without breaking existing setups
- **Health Validation**: Verifies Docker containers and Nginx are running correctly

## Prerequisites

Before running this script, ensure you have:

### Local Machine
- **Bash 4.0+** (macOS, Linux, WSL, or Git Bash on Windows)
- **Git** installed and configured
- **SSH client** available
- **curl** or **wget** for testing endpoints

### Remote Server
- **Ubuntu/Debian-based Linux** (18.04 LTS or newer recommended)
- **SSH access** with key-based authentication
- **sudo privileges** for the SSH user
- **Internet connectivity** for package downloads
- **Open ports**: 22 (SSH), 80 (HTTP), 443 (HTTPS if needed)

### GitHub
- **Git repository** with a Dockerfile or docker-compose.yml
- **Personal Access Token (PAT)** for private repository access

## Installation

1. Clone or download this script:
```bash
git clone <your-repo-url>
cd <repo-name>
```

2. Make the script executable:
```bash
chmod +x deploy.sh
```

3. Verify prerequisites are installed:
```bash
# Check Bash version
bash --version

# Check Git
git --version

# Check SSH
ssh -V
```

## Usage

### Basic Execution

```bash
./deploy.sh
```

The script will prompt you for the following parameters interactively:

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| **Git Repository URL** | HTTPS URL of your GitHub repo | `https://github.com/username/my-app` |
| **Personal Access Token (PAT)** | GitHub PAT for authentication (input hidden) | `ghp_xxxxxxxxxxxx` |
| **Branch** | Git branch to deploy (optional, defaults to `main`) | `main`, `develop`, `production` |
| **SSH Username** | User account on remote server | `ubuntu`, `ec2-user`, `admin` |
| **Server IP Address** | Public IP of your remote server | `192.168.1.100`, `54.123.45.67` |
| **SSH Key Path** | Path to your private SSH key | `~/.ssh/id_rsa`, `/home/user/.ssh/server-key` |
| **Application Port** | Internal container port your app runs on | `3000`, `8080`, `5000` |

### Example Execution

```bash
$ ./deploy.sh

ℹ === STEP 1: Collecting Parameters ===
Enter Git Repository URL: https://github.com/myusername/my-nodejs-app
Enter Personal Access Token (PAT): ••••••••••••••••••••••••
Enter Branch name (default: main): main
Enter SSH Username: ubuntu
Enter Server IP Address: 54.123.45.67
Enter SSH Key Path (e.g., ~/.ssh/id_rsa): ~/.ssh/my-server.pem
Enter Application Port (internal container port): 3000

ℹ === STEP 2: Clone or Update Repository ===
...
✓ All parameters collected successfully
✓ Repository cloned
```

## Script Workflow

The script executes the following steps in sequence:

### Step 1: Collect Parameters
- Validates Git URL format
- Prompts for and validates all required inputs
- Verifies SSH key exists locally

### Step 2: Clone or Update Repository
- Authenticates using PAT
- Clones repo if new, or pulls latest changes if exists
- Switches to specified branch

### Step 3: Verify Docker Configuration
- Checks for Dockerfile or docker-compose.yml
- Exits with error if neither found

### Step 4: Test SSH Connection
- Verifies connectivity to remote server
- Validates SSH key authentication

### Step 5: Prepare Remote Environment
- Updates system packages
- Installs Docker, Docker Compose, Nginx (if missing)
- Adds user to Docker group
- Enables and starts all services

### Step 6: Deploy Application
- Transfers project files via SCP
- Builds Docker image or starts with docker-compose
- Validates container health and logs

### Step 7: Configure Nginx
- Creates reverse proxy configuration
- Forwards HTTP (port 80) to container port
- Tests and reloads Nginx

### Step 8: Validate Deployment
- Confirms Docker service is running
- Checks container status
- Tests local and remote connectivity

## Output & Logging

### Log Files
All deployment logs are saved to:
```
./logs/deploy_YYYYMMDD_HHMMSS.log
```

Example:
```
./logs/deploy_20250120_143022.log
```

### Console Output
Color-coded output for easy monitoring:
- 🟢 **Green**: Success messages
- 🔴 **Red**: Errors
- 🟡 **Yellow**: Warnings
- 🔵 **Blue**: Information

### Example Log Entry
```
[2025-01-20 14:30:22] [INFO] === STEP 1: Collecting Parameters ===
[2025-01-20 14:30:25] [SUCCESS] Git Repository: https://github.com/myusername/my-app
[2025-01-20 14:30:26] [SUCCESS] Branch: main
```

## Troubleshooting

### SSH Connection Failed
```bash
# Verify SSH key has correct permissions
chmod 600 ~/.ssh/your-key.pem

# Test SSH manually
ssh -i ~/.ssh/your-key.pem ubuntu@54.123.45.67

# Check server firewall allows port 22
```

### Docker Not Installing
```bash
# SSH into server and check internet connectivity
ssh -i ~/.ssh/your-key.pem ubuntu@54.123.45.67
curl -fsSL https://get.docker.com

# Run manually if script fails
sudo apt-get update && sudo apt-get install -y docker.io
```

### Application Port Already in Use
```bash
# Check running containers
docker ps

# Stop conflicting container
docker stop <container-id>
docker rm <container-id>

# Re-run deployment script
./deploy.sh
```

### Nginx Proxy Not Working
```bash
# SSH into server
ssh -i ~/.ssh/your-key.pem ubuntu@54.123.45.67

# Check Nginx config
sudo nginx -t

# View Nginx error logs
sudo tail -f /var/log/nginx/error.log

# Check if container is actually running
docker ps
```

### Container Exits Immediately
```bash
# Check container logs
docker logs <container-name>

# SSH to server and inspect
ssh -i ~/.ssh/your-key.pem ubuntu@54.123.45.67
docker logs <container-name> --tail 50
```

## Security Considerations

1. **PAT Management**
   - Never commit PAT to version control
   - Use GitHub's PAT with minimal required scopes
   - Rotate PATs regularly

2. **SSH Keys**
   - Always use key-based authentication
   - Ensure SSH keys are never committed to Git
   - Set correct permissions: `chmod 600 ~/.ssh/id_rsa`

3. **Server Security**
   - Restrict SSH access via security groups/firewall
   - Use key-based authentication only (disable password auth)
   - Regularly update system packages

4. **Docker Security**
   - Use specific image versions (not `latest`)
   - Scan images for vulnerabilities
   - Run containers with least privileges

5. **Nginx Configuration**
   - Consider SSL/TLS certificates (self-signed or Let's Encrypt)
   - Add security headers
   - Implement rate limiting for production

## Example: Complete Deployment

### Step 1: Prepare Your Application
```bash
# Create a simple Node.js app with Dockerfile
mkdir my-app && cd my-app
cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "index.js"]
EOF

# Add to Git and push
git init
git add .
git commit -m "Initial commit"
git push -u origin main
```

### Step 2: Set Up Server
```bash
# Create EC2 instance or use DigitalOcean droplet
# Ubuntu 22.04 LTS recommended
# Save SSH key locally: ~/.ssh/my-server.pem
```

### Step 3: Run Deployment Script
```bash
./deploy.sh
# Provide your GitHub URL, PAT, server details, and port 3000
```

### Step 4: Verify Deployment
```bash
# Access your app
curl http://<server-ip>
# or open in browser: http://54.123.45.67
```

## Re-running the Script

The script is idempotent and safe to re-run:

```bash
# Safe to run multiple times
./deploy.sh

# It will:
# - Pull latest changes from repository
# - Stop and remove old containers
# - Build and deploy new containers
# - Update Nginx configuration
```

## Performance Notes

- Script typically completes in 2-5 minutes depending on:
  - Docker image size
  - Network speed
  - Server resources
- First run takes longer due to package installations
- Subsequent runs are faster (packages cached)

## File Structure

```
your-repo/
├── deploy.sh          # Main deployment script
├── README.md          # This file
└── logs/              # Created automatically
    └── deploy_*.log   # Timestamped log files
```

## Support & Contributions

For issues or questions:
1. Check the **Troubleshooting** section above
2. Review log files in `./logs/`
3. Test SSH access manually
4. Verify all prerequisites are installed

## License

This script is provided as-is for educational and production use.

---

**Last Updated**: January 2025
**Bash Version**: 4.0+
**Tested On**: Ubuntu 20.04 LTS, Ubuntu 22.04 LTS