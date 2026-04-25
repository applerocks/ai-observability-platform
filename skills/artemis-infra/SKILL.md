---
name: artemis-infra
description: Manage the Artemis AI-Driven Observability Platform on AWS EKS. Use this skill whenever the user mentions Artemis, EKS cluster operations, deploying or updating microservices, OpenTelemetry setup, observability stack, Terraform changes to the Artemis infrastructure, scaling nodes, fixing load balancers, or any AWS infrastructure work related to this project. Also triggers on "deploy app", "fix LB", "scale cluster", "OTel", "Jaeger", "Grafana", "Prometheus", "Online Boutique", or "push to git".
---

# Artemis Infrastructure Skill

Read `CLAUDE.md` at the repo root first — it has all project context, infrastructure details, known issues, and common operations. This skill covers the patterns and procedures for working on Artemis.

## Quick Reference

- **Repo**: `C:\Users\Suresh Reddy\artemis-infra`
- **AWS Profile**: `suresh-aws` (SSO, expires every few hours)
- **Region**: us-east-2
- **EKS Cluster**: artemis (K8s 1.32)
- **Node Group**: artemis-workers (t3.large, 2-4 nodes)
- **Terraform**: `infra/terraform/` with S3 backend

## Before Any AWS Operation

Check SSO token validity. If any AWS/kubectl command fails with auth errors:
```bash
aws sso login --profile suresh-aws
```

## Terraform Workflow

All infrastructure changes go through Terraform in `infra/terraform/`.

1. Save files directly to the repo (user preference — never show code in chat for them to copy)
2. Tell user to run `terraform apply` (not `terraform plan` separately)
3. If backend errors, ensure `profile = "suresh-aws"` is in backend.tf
4. After backend config changes, use `terraform init -reconfigure`

Module structure:
- `modules/vpc/` — VPC, subnets, NAT, security groups
- `modules/eks/` — EKS cluster, node group, OIDC, EBS CSI, add-ons
- `modules/alb-controller/` — ALB controller IAM policy + IRSA role

## Kubernetes Deployments

### Internet-Facing Services
Every `type: LoadBalancer` service MUST have:
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
  service.beta.kubernetes.io/aws-load-balancer-target-type: ip
```
Without these, the ALB controller creates internal LBs. This has caused issues multiple times.

### Deploying Apps
Save manifests to `apps/` directory, then tell user the kubectl command with path in quotes (Windows spaces):
```bash
kubectl apply -f "C:\Users\Suresh Reddy\artemis-infra\apps\<path>\file.yaml" -n <namespace>
```

### Namespaces
- `online-boutique` — Demo app (11 microservices)
- `observability` — OTel Collector, Jaeger, Prometheus, Grafana
- `kube-system` — ALB controller, EBS CSI, system components

## Observability Stack

Data flow: `App pods → OTel Collector (OTLP) → Jaeger (traces) + Prometheus (metrics) → Grafana (dashboards)`

Enable OTel on any namespace:
```bash
kubectl set env deployment --all -n <namespace> \
  OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability.svc.cluster.local:4317 \
  OTEL_RESOURCE_ATTRIBUTES=service.namespace=<namespace>
```

### Grafana Access
- Login: admin / artemis123
- Datasources auto-provisioned: Prometheus + Jaeger

## Cost Management

### Scale Down (stop spending on compute)
```bash
kubectl delete namespace online-boutique
kubectl delete namespace observability  
aws eks update-nodegroup-config --cluster-name artemis --nodegroup-name artemis-workers \
  --scaling-config minSize=0,maxSize=4,desiredSize=0 --profile suresh-aws --region us-east-2
```

### Scale Up (resume work)
```bash
aws eks update-nodegroup-config --cluster-name artemis --nodegroup-name artemis-workers \
  --scaling-config minSize=2,maxSize=4,desiredSize=2 --profile suresh-aws --region us-east-2
# Wait 2-3 min for nodes, then redeploy apps
```

## Git Workflow
```bash
cd C:\Users\Suresh Reddy\artemis-infra
git add .
git commit -m "<descriptive message>"
git push origin main
```

## Windows-Specific Gotchas
- Use quotes around paths with spaces in kubectl/helm commands
- Helm commands must be single-line (no `^` continuation in CMD)
- PowerShell works better than CMD for multi-line commands
- `--watch` not `watch` for kubectl (two dashes)

## Troubleshooting Checklist
1. **Auth error** → `aws sso login --profile suresh-aws`
2. **Terraform no credentials** → Check `profile = "suresh-aws"` in backend.tf
3. **LB timeout/unreachable** → Check `internet-facing` annotation + verify Scheme with `aws elbv2 describe-load-balancers`
4. **ALB controller permission denied** → Update `iam-policy.json`, run `terraform apply`
5. **Pods not starting** → `kubectl describe pod <name> -n <ns>` for events
6. **EKS access denied** → Verify access entry has AmazonEKSClusterAdminPolicy
