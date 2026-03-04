# ============================================
# AWS BACKUP - Cross-Region DR
# Primary: us-east-1 | Replica: us-west-2
# ============================================

# --- IAM Role para AWS Backup ---
resource "aws_iam_role" "backup_role" {
  name = "dr-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# --- Vault primario (us-east-1) ---
resource "aws_backup_vault" "primary" {
  name = "dr-backup-vault-primary"
  tags = { Environment = "production", Region = "primary" }
}

# --- Vault secundario (us-west-2) para réplicas ---
resource "aws_backup_vault" "secondary" {
  provider = aws.secondary
  name     = "dr-backup-vault-secondary"
  tags     = { Environment = "production", Region = "secondary" }
}

# --- Backup Plan ---
resource "aws_backup_plan" "rds_backup" {
  name = "dr-rds-backup-plan"

  rule {
    rule_name         = "every-6-hours"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 */6 * * ? *)"
    
    start_window      = 60   # minutos para iniciar
    completion_window = 120  # minutos para completar

    lifecycle {
      delete_after = 7  # retención 7 días
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.secondary.arn

      lifecycle {
        delete_after = 7
      }
    }
  }

  tags = { Project = "dr-system" }
}

# --- Selección de recursos a respaldar ---
resource "aws_backup_selection" "rds" {
  name         = "dr-rds-selection"
  plan_id      = aws_backup_plan.rds_backup.id
  iam_role_arn = aws_iam_role.backup_role.arn

  resources = [aws_db_instance.main.arn]
}

# --- Outputs ---
output "backup_vault_primary_arn" {
  value = aws_backup_vault.primary.arn
}

output "backup_vault_secondary_arn" {
  value = aws_backup_vault.secondary.arn
}
