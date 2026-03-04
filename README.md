# Multi-Region Disaster Recovery System

![AWS](https://img.shields.io/badge/AWS-ECS%20Fargate%20%7C%20RDS%20%7C%20Backup-orange?logo=amazonaws)
![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)
![Docker](https://img.shields.io/badge/Container-Docker-2496ED?logo=docker)
![RTO](https://img.shields.io/badge/RTO-30--60%20min-green)
![RPO](https://img.shields.io/badge/RPO-5%20min-green)

Enterprise-grade disaster recovery system built on AWS. Automatic cross-region database backups, containerized application on ECS Fargate with Multi-AZ PostgreSQL, and infrastructure fully managed with Terraform.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   us-east-1 (Primary)            │
│                                                  │
│   Internet → ALB → ECS Fargate (2 tasks)         │
│                         │                        │
│              RDS PostgreSQL Multi-AZ             │
│              (primary + standby AZ)              │
│                         │                        │
│              AWS Backup Vault (primary)          │
└─────────────────────────┬───────────────────────┘
                          │ Cross-region copy
                          ▼ (every 6 hours)
┌─────────────────────────────────────────────────┐
│               us-west-2 (DR Region)              │
│                                                  │
│              AWS Backup Vault (secondary)        │
│              Recovery Points (7-day retention)   │
└─────────────────────────────────────────────────┘
```

**Key metrics:**
| Metric | Value |
|--------|-------|
| RTO (Recovery Time Objective) | 30–60 minutes |
| RPO (Recovery Point Objective) | 5 minutes |
| Backup frequency | Every 6 hours |
| Backup retention | 7 days |
| Estimated monthly cost | ~$77/month |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Infrastructure as Code | Terraform |
| Compute | AWS ECS Fargate |
| Database | RDS PostgreSQL Multi-AZ |
| Container Registry | Amazon ECR |
| Load Balancer | Application Load Balancer |
| Backup & DR | AWS Backup (cross-region) |
| Application | Flask + Gunicorn (Python) |
| Container | Docker |

---

## Project Structure

```
multi-region-dr-system/
├── app/
│   ├── app.py              # Flask application
│   ├── Dockerfile          # Container definition
│   └── requirements.txt    # Python dependencies
│
├── terraform/
│   ├── provider.tf         # Dual-region AWS providers
│   ├── variables.tf        # Input variables
│   ├── vpc.tf              # VPC, subnets, NAT, IGW
│   ├── security_groups.tf  # ALB, ECS, RDS security groups
│   ├── rds.tf              # PostgreSQL Multi-AZ instance
│   ├── ecr.tf              # Container registry
│   ├── alb.tf              # Application Load Balancer
│   ├── ecs.tf              # Cluster, task definition, service
│   ├── backup.tf           # AWS Backup cross-region plan
│   └── outputs.tf          # ALB URL, ECR URL, RDS endpoint
│
├── docs/
│   └── screenshots/        # AWS console evidence
│
└── README.md
```

---

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- Docker
- IAM user with: `EC2FullAccess`, `ECSFullAccess`, `RDSFullAccess`, `ECRFullAccess`, `BackupFullAccess`, `IAMFullAccess`

---

## Deploy

### 1. Clone and configure

```bash
git clone https://github.com/<your-user>/multi-region-dr-system.git
cd multi-region-dr-system/terraform

export TF_VAR_db_username="dbadmin"
export TF_VAR_db_password="<your-secure-password>"
```

### 2. Deploy infrastructure

```bash
terraform init
terraform plan
terraform apply
```

> RDS takes ~10 minutes to provision. Total apply time: ~15 minutes.

### 3. Push application to ECR

```bash
# Get ECR URL from outputs
ECR_URL=$(terraform output -raw ecr_repository_url)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build and push
cd ../app
docker build -t dr-app .
docker tag dr-app:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

### 4. Force ECS deployment

```bash
aws ecs update-service \
  --cluster dr-system-cluster \
  --service dr-system-service \
  --force-new-deployment \
  --region us-east-1
```

### 5. Verify

```bash
ALB_URL=$(cd ../terraform && terraform output -raw alb_url)

curl $ALB_URL/health
# {"status": "ok"}

curl $ALB_URL/
# {"status": "healthy", "message": "DR System Running", "region": "us-east-1"}
```

---

## Disaster Recovery Runbook

### Scenario: Primary region failure

**1. Identify latest recovery point in us-west-2**
```bash
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name dr-backup-vault-secondary \
  --region us-west-2 \
  --query 'RecoveryPoints[0].RecoveryPointArn'
```

**2. Restore RDS from recovery point**
```bash
aws backup start-restore-job \
  --recovery-point-arn <RECOVERY_POINT_ARN> \
  --iam-role-arn arn:aws:iam::<ACCOUNT_ID>:role/dr-backup-role \
  --metadata '{"engine":"postgres","instanceClass":"db.t3.micro"}' \
  --region us-west-2
```

**3. Deploy ECS service in us-west-2**

Update `provider.tf` to set `us-west-2` as primary and run:
```bash
terraform apply -var="primary_region=us-west-2"
```

**4. Update DNS** to point to new ALB in us-west-2.

---

## Networking

| Resource | Value |
|----------|-------|
| VPC CIDR | 10.0.0.0/16 |
| Public Subnet A | 10.0.0.0/24 |
| Public Subnet B | 10.0.1.0/24 |
| Private Subnet A | 10.0.10.0/24 |
| Private Subnet B | 10.0.11.0/24 |
| Primary Region | us-east-1 |
| DR Region | us-west-2 |

---

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| RDS db.t3.micro Multi-AZ | ~$29 |
| ECS Fargate (2 tasks, 0.25 vCPU / 0.5GB) | ~$15 |
| ALB | ~$18 |
| NAT Gateway | ~$10 |
| AWS Backup storage | ~$5 |
| **Total** | **~$77/month** |

> **Cost optimization:** Destroy resources when not in use with `terraform destroy`. Re-deploy takes ~15 minutes.

---

## Cleanup

```bash
# Delete ECR images first (Terraform can't delete non-empty repos)
aws ecr delete-repository \
  --repository-name dr-system-app \
  --region us-east-1 \
  --force

# Delete backup recovery points if any exist
# AWS Backup → Backup vaults → delete recovery points manually

# Destroy all infrastructure
cd terraform
terraform destroy

# Clean up CloudWatch logs
aws logs delete-log-group \
  --log-group-name /ecs/dr-system \
  --region us-east-1
```

---

## Screenshots

| Component | Status |
|-----------|--------|
| ECS Tasks Running | `docs/screenshots/ecs-tasks.png` |
| RDS Multi-AZ | `docs/screenshots/rds-multiaz.png` |
| ALB Active | `docs/screenshots/alb-active.png` |
| Backup Vaults | `docs/screenshots/backup-vaults.png` |
| ECR Repository | `docs/screenshots/ecr-repo.png` |
| Health Check Response | `docs/screenshots/curl-health.png` |

---

## Key Learnings

- **Multi-AZ vs Cross-Region:** Multi-AZ provides HA within a region (automatic failover in <2 min). Cross-region backup provides DR for full region outages (manual failover, longer RTO).
- **ECS Fargate over EC2:** No server management, automatic scaling, pay-per-use — ideal for containerized workloads with variable traffic.
- **Terraform state management:** Always run `terraform` commands from the same directory that contains `terraform.tfstate`.
- **ECR cleanup:** Terraform cannot delete non-empty ECR repositories. Always use `--force` flag when deleting manually.

---

## Author

Built as part of a cloud engineering portfolio demonstrating production-grade AWS architecture, IaC best practices, and enterprise DR patterns.
