# neurX Backup Instructions

## Quick Start

1. **Edit the script** to set Cosmo's IP address:
   ```bash
   nano /home/rich/dev/backup-to-cosmo.sh
   # Change line 13: COSMO_HOST="192.168.1.100" to your Cosmo's actual IP
   ```

2. **Run the backup script** from neurX:
   ```bash
   cd /home/rich/dev
   ./backup-to-cosmo.sh
   ```

3. **Transfer to Cosmo** - The script will show you the exact command to run from Cosmo

## What Gets Backed Up

### Databases
- ✅ **OPIE** - Main OPIE database (SQL Server)
- ✅ **Sideways6** - Legacy Sideways 6 data (SQL Server)
- ✅ **SQRL MySQL** - SQRL application database (if running)
- ✅ **MariaDB** - Development databases (if running)

### Code Projects
- ✅ **OPIE** - `/home/rich/dev/projects/OPIE` (excluding node_modules)
- ✅ **OPIE uploads** - Attachment files uploaded by users
- ✅ **SQRL** - `/home/rich/dev/projects/SQRL` (excluding node_modules)
- ✅ **Kermit** - `/home/rich/dev/projects/kermit` (excluding node_modules)

### Configuration Files
- ✅ **CLAUDE.md** - Development instructions
- ✅ **Bash configs** - .bashrc, .bash_profile
- ✅ **Docker configs** - Docker compose files (if present)

## Backup Schedule Recommendation

### Daily (Automated)
- OPIE database only (small, fast)
- Critical for business continuity

### Weekly (Manual/Automated)
- Full backup including all projects
- Run the backup-to-cosmo.sh script

### Monthly (Manual)
- Verify backup integrity
- Test restore procedure
- Archive old backups off-site

## Manual Database Backup (Quick)

If you just need to backup OPIE database quickly:

```bash
# Create backup
docker exec mssql-server /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P OPIEProject2025 -C -Q "
BACKUP DATABASE OPIE
TO DISK = '/var/opt/mssql/data/OPIE_backup.bak'
WITH FORMAT"

# Copy to host
docker cp mssql-server:/var/opt/mssql/data/OPIE_backup.bak ~/backups/OPIE_backup_$(date +%Y%m%d).bak

# From Cosmo (PowerShell):
scp rich@192.168.1.101:/home/rich/backups/OPIE_backup_YYYYMMDD.bak "E:\neurX Backups\OPIE_backup_YYYYMMDD.bak"
```

## Restore Procedures

### Restore OPIE Database

```bash
# Copy backup to neurX if needed
# Then restore:
docker exec mssql-server /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P OPIEProject2025 -C -Q "
RESTORE DATABASE OPIE
FROM DISK = '/var/opt/mssql/data/OPIE_backup.bak'
WITH REPLACE"
```

### Restore Code Projects

```bash
# Extract archive
cd /tmp
tar -xzf neurx_backup_TIMESTAMP.tar.gz

# Copy projects back
rsync -a neurx_backup_TIMESTAMP/code/OPIE/ /home/rich/dev/projects/OPIE/

# Reinstall dependencies
cd /home/rich/dev/projects/OPIE/app
npm install
cd /home/rich/dev/projects/OPIE/server
npm install
```

## Important Notes

⚠️ **Security**: The backup script does NOT backup SSH keys by default. Uncomment that section if needed.

⚠️ **Passwords**: MySQL/MariaDB backup sections use placeholder passwords. Update with actual credentials.

⚠️ **Network**: Ensure Cosmo (192.168.1.100 or whatever IP) is accessible from neurX.

⚠️ **Storage**: Monitor E:\neurX Backups disk space. Each full backup is approximately:
- Databases: ~20-50 MB
- Code (compressed): ~100-500 MB
- Total: ~150-600 MB per backup

## Automation (Optional)

To run backups automatically, add to crontab:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /home/rich/dev/backup-to-cosmo.sh >> /home/rich/dev/backup_cron.log 2>&1

# Add weekly full backup on Sundays at 3 AM
0 3 * * 0 /home/rich/dev/backup-to-cosmo.sh >> /home/rich/dev/backup_cron.log 2>&1
```

## Troubleshooting

**Problem**: "Access denied" when backing up database
- **Solution**: Check Docker container is running: `docker ps | grep mssql`

**Problem**: "No such file or directory" on Cosmo
- **Solution**: Use full path with filename: `"E:\neurX Backups\filename.bak"`

**Problem**: Backup is too large
- **Solution**: Backup databases only, skip code projects

## Contact

For questions or issues with backups, check:
- Backup log file: `/home/rich/dev/backup_log_TIMESTAMP.log`
- This documentation: `/home/rich/dev/BACKUP_INSTRUCTIONS.md`
