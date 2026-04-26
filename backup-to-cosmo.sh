#!/bin/bash

##############################################################################
# neurX to Cosmo Backup Script
#
# This script backs up all critical data from neurX to Cosmo's E:\neurX Backups
# Run this script from neurX server
##############################################################################

# Configuration
COSMO_USER="richt"
COSMO_HOST="192.168.1.100"  # UPDATE THIS with Cosmo's actual IP
COSMO_BACKUP_PATH="E:/neurX Backups"  # Note: Use forward slashes for scp
DATE_FOLDER=$(date +%Y%m%d)_neurX_backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/home/rich/dev/${DATE_FOLDER}"
LOG_FILE="${BACKUP_DIR}/backup_log_${TIMESTAMP}.log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "========================================"
echo "neurX Backup Script Started"
echo "Timestamp: ${TIMESTAMP}"
echo "========================================"

# Function to log messages
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

# Create dated backup directory
log "Creating backup directory: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"/{databases,code,configs}

##############################################################################
# 1. BACKUP DATABASES
##############################################################################
log "Starting database backups..."

# OPIE Database
log "Backing up OPIE database..."
docker exec mssql-server /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P OPIEProject2025 -C -Q "
BACKUP DATABASE OPIE
TO DISK = '/var/opt/mssql/data/OPIE_backup_temp.bak'
WITH FORMAT, NAME = 'OPIE Backup ${TIMESTAMP}'
" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    docker cp mssql-server:/var/opt/mssql/data/OPIE_backup_temp.bak "${BACKUP_DIR}/databases/OPIE_backup_${TIMESTAMP}.bak"
    docker exec mssql-server rm /var/opt/mssql/data/OPIE_backup_temp.bak
    log "✓ OPIE database backed up successfully"
else
    error "✗ OPIE database backup failed"
fi

# Sideways6 Database (if needed)
log "Backing up Sideways6 database..."
docker exec mssql-server /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P OPIEProject2025 -C -Q "
BACKUP DATABASE Sideways6
TO DISK = '/var/opt/mssql/data/Sideways6_backup_temp.bak'
WITH FORMAT, NAME = 'Sideways6 Backup ${TIMESTAMP}'
" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    docker cp mssql-server:/var/opt/mssql/data/Sideways6_backup_temp.bak "${BACKUP_DIR}/databases/Sideways6_backup_${TIMESTAMP}.bak"
    docker exec mssql-server rm /var/opt/mssql/data/Sideways6_backup_temp.bak
    log "✓ Sideways6 database backed up successfully"
else
    warn "✗ Sideways6 database backup failed (may not be critical)"
fi

# MySQL databases (SQRL, Kermit if they exist)
log "Checking for MySQL/MariaDB databases..."
if docker ps | grep -q "sqrl-mysql"; then
    log "Backing up SQRL MySQL database..."
    docker exec sqrl-mysql mysqldump -u root -pYourPassword --all-databases > "${BACKUP_DIR}/databases/sqrl_mysql_${TIMESTAMP}.sql" 2>> "$LOG_FILE"
    if [ $? -eq 0 ]; then
        log "✓ SQRL MySQL database backed up successfully"
    else
        warn "✗ SQRL MySQL backup failed - check credentials"
    fi
fi

if docker ps | grep -q "mariadb"; then
    log "Backing up MariaDB databases..."
    docker exec mariadb-dev-db-1 mysqldump -u root -pYourPassword --all-databases > "${BACKUP_DIR}/databases/mariadb_${TIMESTAMP}.sql" 2>> "$LOG_FILE"
    if [ $? -eq 0 ]; then
        log "✓ MariaDB backed up successfully"
    else
        warn "✗ MariaDB backup failed - check credentials"
    fi
fi

##############################################################################
# 2. BACKUP CODE PROJECTS
##############################################################################
log "Starting code backups..."

# OPIE Project
log "Backing up OPIE project..."
rsync -a --exclude 'node_modules' --exclude '.git' --exclude '*.log' --exclude 'uploads' \
    /home/rich/dev/projects/OPIE/ "${BACKUP_DIR}/code/OPIE/" >> "$LOG_FILE" 2>&1
log "✓ OPIE code backed up (excluding node_modules)"

# OPIE uploads folder (separately, only recent files)
log "Backing up OPIE uploads (attachments)..."
if [ -d "/home/rich/dev/projects/OPIE/server/uploads" ]; then
    rsync -a /home/rich/dev/projects/OPIE/server/uploads/ "${BACKUP_DIR}/code/OPIE_uploads/" >> "$LOG_FILE" 2>&1
    log "✓ OPIE uploads backed up"
fi

# SQRL Project
log "Backing up SQRL project..."
rsync -a --exclude 'node_modules' --exclude '.git' --exclude '*.log' \
    /home/rich/dev/projects/SQRL/ "${BACKUP_DIR}/code/SQRL/" >> "$LOG_FILE" 2>&1
log "✓ SQRL code backed up"

# Kermit Project
log "Backing up Kermit project..."
rsync -a --exclude 'node_modules' --exclude '.git' --exclude '*.log' \
    /home/rich/dev/projects/kermit/ "${BACKUP_DIR}/code/kermit/" >> "$LOG_FILE" 2>&1
log "✓ Kermit code backed up"

##############################################################################
# 3. BACKUP CONFIGURATIONS
##############################################################################
log "Backing up configuration files..."

# Docker configurations
if [ -d "/home/rich/dev/docker" ]; then
    rsync -a /home/rich/dev/docker/ "${BACKUP_DIR}/configs/docker/" >> "$LOG_FILE" 2>&1
fi

# Important config files
cp /home/rich/dev/CLAUDE.md "${BACKUP_DIR}/configs/" 2>/dev/null
cp /home/rich/.bashrc "${BACKUP_DIR}/configs/" 2>/dev/null
cp /home/rich/.bash_profile "${BACKUP_DIR}/configs/" 2>/dev/null

# SSH keys (if you want to back them up - BE CAREFUL with these!)
# Uncomment if needed:
# mkdir -p "${BACKUP_DIR}/configs/ssh"
# cp /home/rich/.ssh/id_* "${BACKUP_DIR}/configs/ssh/" 2>/dev/null

log "✓ Configuration files backed up"

##############################################################################
# 4. CREATE COMPRESSED ARCHIVE (Optional)
##############################################################################
log "All backups stored in: ${BACKUP_DIR}"
log "Creating compressed archive..."
cd /home/rich/dev
tar -czf "${DATE_FOLDER}.tar.gz" "${DATE_FOLDER}/" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    ARCHIVE_SIZE=$(du -sh "${DATE_FOLDER}.tar.gz" | cut -f1)
    log "✓ Archive created successfully: ${DATE_FOLDER}.tar.gz (${ARCHIVE_SIZE})"
else
    warn "⚠ Failed to create archive (backup files still available in ${BACKUP_DIR})"
fi

##############################################################################
# 5. TRANSFER TO COSMO
##############################################################################
log "Ready to transfer backup to Cosmo computer..."
log "Destination: ${COSMO_USER}@${COSMO_HOST}:${COSMO_BACKUP_PATH}/"

echo ""
echo "========================================"
echo "BACKUP READY - TRANSFER TO COSMO:"
echo "========================================"
echo "Backup Location: ${BACKUP_DIR}"
echo "Archive: ${DATE_FOLDER}.tar.gz"
echo ""
echo "From your Cosmo computer (Windows PowerShell), run ONE of these commands:"
echo ""
echo "Option 1 - Copy entire archive (recommended):"
echo "scp -r rich@192.168.1.101:/home/rich/dev/${DATE_FOLDER}.tar.gz \"${COSMO_BACKUP_PATH}\\${DATE_FOLDER}.tar.gz\""
echo ""
echo "Option 2 - Copy entire folder:"
echo "scp -r rich@192.168.1.101:${BACKUP_DIR} \"${COSMO_BACKUP_PATH}\\${DATE_FOLDER}\""
echo ""
echo "Option 3 - Copy just the OPIE database:"
echo "scp rich@192.168.1.101:${BACKUP_DIR}/databases/OPIE_backup_${TIMESTAMP}.bak \"${COSMO_BACKUP_PATH}\\${DATE_FOLDER}_OPIE.bak\""
echo ""
echo "========================================"

# Alternative: Automatic SCP (requires password or SSH keys)
# Uncomment if you set up SSH keys:
# scp "${DATE_FOLDER}.tar.gz" "${COSMO_USER}@${COSMO_HOST}:${COSMO_BACKUP_PATH}/"

##############################################################################
# 6. CLEANUP
##############################################################################
log "Backup files preserved in: ${BACKUP_DIR}"
log "Archive preserved: ${DATE_FOLDER}.tar.gz"
log "✓ Backup complete - ready for transfer to Cosmo"

echo ""
echo "========================================"
echo "Backup Summary"
echo "========================================"
echo "Backup Folder: ${BACKUP_DIR}"
echo "Archive: ${DATE_FOLDER}.tar.gz"
echo "Archive Size: ${ARCHIVE_SIZE}"
echo "Log File: ${LOG_FILE}"
echo ""
echo "Backed up:"
echo "  - OPIE database"
echo "  - Sideways6 database"
echo "  - OPIE project code + uploads"
echo "  - SQRL project code"
echo "  - Kermit project code"
echo "  - Configuration files"
echo ""
echo "Next step: Transfer to Cosmo using one of the scp commands above"
echo "======================================"
