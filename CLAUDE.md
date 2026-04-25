# Artemis - AI-Driven Observability Platform

## Project Overview
Artemis is a POC AI-driven observability platform built on AWS. It collects metrics, traces, and logs from microservices using OpenTelemetry, stores them in cost-effective backends, and applies AI/ML for anomaly detection and root cause analysis.

## Owner
- Name: Suresh Reddy
- Email: sureshkumarreddy.y@gmail.com
- AWS Account: 994878981126
- GitHub: https://github.com/applerocks/ai-observability-platform.git

## Key Decisions
- **POC only** — single environment, no dev/staging/prod split
- **Cost-conscious** — single NAT gateway, minimal node count, self-hosted where possible
- **No hardcoding** — all Terraform is variable-driven
- **Home region**: us-east-2 (Ohio)
- **AWS auth**: SSO via IAM Identity Center, profile name `suresh-aws`
- **SSO login**: `aws sso login --profile suresh-aws` (expires every few hours)

## Repo Structure
```
artemis-infra/
├── CLAUDE.md                          # This file
├── infra/terraform/
│   ├── backend.tf                     # S3 backend + provider (profile: suresh-aws)
│   ├── main.tf                        # Root module (VPC, EKS, ALB controller)
│   ├── variables.tf                   # project=artemis, region=us-east-2
│   ├── outputs.tf                     # VPC, EKS, ALB controller outputs
│   ├── bootstrap/main.tf             # One-time S3+DynamoDB for TF state
│   ├── modules/vpc/                   # VPC, subnets, NAT, IGW, SG, S3 endpoint
│   ├── modules/eks/                   # EKS cluster, node group, OIDC, EBS CSI
│   └── modules/alb-controller/       # ALB controller IAM policy + IRSA role
├── apps/
│   ├── online-boutique/              # Google's 11-microservice demo app
│   │   └── kubernetes-manifests.yaml  # With ENV_PLATFORM=aws, internet-facing LB
│   └── observability/                 # Telemetry stack
│       ├── otel-collector.yaml        # OTel Collector (receives OTLP, exports to backends)
│       ├── jaeger.yaml                # Jaeger all-in-one (traces, internet-facing LB)
│       ├── prometheus.yaml            # Prometheus (scrapes OTel Collector metrics)
│       └── grafana.yaml               # Grafana (dashboards, internet-facing LB, admin/artemis123)
```

## Infrastructure (Live on AWS)
| Resource | Details |
|----------|---------|
| VPC | 10.0.0.0/16, 2 AZs (us-east-2a, us-east-2b) |
| Public subnets | 10.0.0.0/20, 10.0.16.0/20 |
| Private subnets | 10.0.64.0/20, 10.0.80.0/20 |
| NAT Gateway | Single (cost saving) |
| EKS | Cluster "artemis", K8s 1.32, API_AND_CONFIG_MAP auth |
| Node Group | artemis-workers, t3.large, 2 min / 2 desired / 4 max, 30GB disk |
| Add-ons | vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver (IRSA) |
| ALB Controller | Helm-installed, IRSA role, internet-facing NLBs |
| TF State | S3: artemis-tfstate-994878981126, uses use_lockfile=true |

## EKS Access
- SSO role ARN: `arn:aws:iam::994878981126:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_ccda8e88ebd1de6c`
- Access policy: AmazonEKSClusterAdminPolicy (not AmazonEKSAdminPolicy)
- Update kubeconfig: `aws eks update-kubeconfig --name artemis --region us-east-2 --profile suresh-aws`

## Kubernetes Namespaces
| Namespace | Contents |
|-----------|----------|
| online-boutique | 11 microservices (frontend, cart, checkout, payment, shipping, currency, product catalog, recommendation, ad, email, redis + loadgenerator) |
| observability | OTel Collector, Jaeger, Prometheus, Grafana |
| kube-system | AWS Load Balancer Controller, EBS CSI, CoreDNS |

## Common Operations

### Scale down to save cost
```bash
kubectl delete namespace online-boutique
kubectl delete namespace observability
aws eks update-nodegroup-config --cluster-name artemis --nodegroup-name artemis-workers --scaling-config minSize=0,maxSize=4,desiredSize=0 --profile suresh-aws --region us-east-2
```

### Scale back up
```bash
aws eks update-nodegroup-config --cluster-name artemis --nodegroup-name artemis-workers --scaling-config minSize=2,maxSize=4,desiredSize=2 --profile suresh-aws --region us-east-2
# Wait for nodes to be Ready, then redeploy apps
```

### Deploy Online Boutique
```bash
kubectl create namespace online-boutique
kubectl apply -f "apps/online-boutique/kubernetes-manifests.yaml" -n online-boutique
```

### Deploy observability stack
```bash
kubectl apply -f "apps/observability/otel-collector.yaml"
kubectl apply -f "apps/observability/jaeger.yaml"
kubectl apply -f "apps/observability/prometheus.yaml"
kubectl apply -f "apps/observability/grafana.yaml"
```

### Enable OTel on Online Boutique
```bash
kubectl set env deployment --all -n online-boutique OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability.svc.cluster.local:4317 OTEL_RESOURCE_ATTRIBUTES=service.namespace=online-boutique
```

### Internet-facing LoadBalancer
Any Service with `type: LoadBalancer` MUST have these annotations to be publicly accessible:
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
  service.beta.kubernetes.io/aws-load-balancer-target-type: ip
```
Without these, the ALB controller creates an internal LB in private subnets.

## Known Issues & Fixes
- **SSO token expires** → `aws sso login --profile suresh-aws`
- **Terraform backend auth** → backend block needs `profile = "suresh-aws"`
- **EKS access denied** → Need AmazonEKSClusterAdminPolicy (not Admin)
- **LB not reachable** → Check `internet-facing` annotation and public subnet tags
- **ALB controller missing permissions** → iam-policy.json needs `ec2:GetSecurityGroupsForVpc` and `elasticloadbalancing:DescribeListenerAttributes`
- **Windows CMD Helm** → Use single-line commands, no `^` line continuation
- **kubectl path with spaces** → Wrap in quotes: `kubectl apply -f "C:\path with spaces\file.yaml"`

## Cost Estimate
- EKS control plane: ~$72/mo
- 2x t3.large nodes: ~$120/mo
- NAT Gateway: ~$32/mo + data
- Load Balancers: ~$16/mo each
- Total running: ~$300-400/mo
- Scaled to 0 nodes: ~$105/mo (control plane + NAT only)

## Observability Stack (Deployed via Helm)
The observability stack was installed using Helm charts (not the basic manifests in apps/observability/):
- **OTel Collector**: `otel-collector-opentelemetry-collector` (Helm release)
- **Prometheus**: `kube-prometheus-stack` Helm chart (includes Operator, Alertmanager, Grafana, node-exporter, kube-state-metrics)
- All services are ClusterIP — access via `kubectl port-forward`

### Access Grafana
```bash
kubectl port-forward svc/prometheus-grafana 3000:80 -n observability
```
Open http://localhost:3000 (admin / artemis123)

### Access Prometheus
```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n observability
```

## Current Phase
Observability stack is live and collecting data. OTel Collector receives metrics from pods. Next: AI/ML anomaly detection layer.

## Future Phases
1. Storage backend (PostgreSQL with pg_vector, Kafka for streaming)
2. AI/ML pipeline (anomaly detection, root cause analysis)
3. Custom Grafana dashboards for Artemis
4. GitHub Actions CI/CD with OIDC
