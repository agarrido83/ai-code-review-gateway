# AI Code Review Gateway

Servicio cloud-native de revisión de código con IA. Acepta un snippet de código, lo envía a Claude (Amazon Bedrock) a través de un gateway LiteLLM, y devuelve sugerencias de mejora. Desplegado sobre EKS con observabilidad mediante Prometheus y Grafana.

Proyecto de fin de Bootcamp — demostración de IaC (Terraform), contenedores (Docker + ECR), orquestación (Kubernetes) y observabilidad en AWS.

---

## Arquitectura

```
Cliente (curl / Postman)
         │
         ▼  HTTP POST /review
┌──────────────────────────────────��──────────┐
│              EKS Cluster (eu-west-1)         │
│                                             │
│  ┌──────────────────┐  ┌─────────────────┐  │
│  │  API FastAPI      │─▶│ LiteLLM Gateway │  │
│  │  2 réplicas       │  │  1 réplica      │  │
│  │  port 8000        │  │  port 4000      │  │
│  └──────────────────┘  └────────┬────────┘  │
│           ▲                     │           │
│  ┌────────┴──────┐   ┌──────────▼────────┐  │
│  │    Grafana    │◀──│    Prometheus      │  │
│  └───────────────┘   └───────────────────┘  │
└─────────────────────────────────────────────┘
         │                        │
         ▼                        ▼
  Amazon Bedrock          Aurora Serverless v2
  Claude Sonnet 4.6       (keys y logs LiteLLM)
  (inference profile EU)
```

**Infraestructura AWS:**
- EKS Cluster + Managed Node Group (2 × t3.medium)
- Aurora Serverless v2 PostgreSQL (backend de LiteLLM)
- ECR (imagen de la API FastAPI)
- Secrets Manager (master key y DATABASE_URL)

---

## API

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/review` | Recibe `{code, language}`, devuelve `{suggestions}` |
| `GET`  | `/health` | Healthcheck — devuelve `{status: "ok"}` |
| `GET`  | `/metrics` | Métricas Prometheus |

---

## Ejecución local

Requiere Python 3.11+ y una instancia de LiteLLM accesible (o cualquier endpoint compatible con la API de OpenAI).

```bash
cd app/
pip install -r requirements.txt

export LITELLM_URL="http://localhost:4000"
export LITELLM_API_KEY="sk-tu-master-key"

uvicorn main:app --reload --port 8000
```

Prueba:
```bash
curl -X POST http://localhost:8000/review \
  -H "Content-Type: application/json" \
  -d '{"code": "def suma(a,b): return a+b", "language": "python"}'
```

---

## Docker

```bash
cd app/
docker build -t code-review-api .

docker run --rm -p 8000:8000 \
  -e LITELLM_URL="http://host.docker.internal:4000" \
  -e LITELLM_API_KEY="sk-tu-master-key" \
  code-review-api
```

---

## Despliegue en EKS

### Prerrequisitos
- AWS CLI configurado (`aws sts get-caller-identity`)
- Terraform >= 1.0, kubectl, helm, Docker

### 1 — Infraestructura

```bash
cd infra/
terraform init
terraform apply
# ~15 min. EKS + Aurora + ECR + IAM

aws eks update-kubeconfig --region eu-west-1 --name capstone-cluster
kubectl get nodes   # esperar estado Ready
```

### 2 — Build y push de la imagen

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URL=$ACCOUNT_ID.dkr.ecr.eu-west-1.amazonaws.com/code-review-api

aws ecr get-login-password --region eu-west-1 \
  | docker login --username AWS --password-stdin $ECR_URL

cd app/
docker build -t code-review-api .
docker tag code-review-api:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

### 3 — Secret de Kubernetes

```bash
MASTER_KEY=$(aws secretsmanager get-secret-value \
  --secret-id poc-litellm-master-key --query SecretString --output text)

DB_URL=$(aws secretsmanager get-secret-value \
  --secret-id poc-db-url --query SecretString --output text)

kubectl create namespace ai-gateway

kubectl create secret generic litellm-secrets \
  --namespace ai-gateway \
  --from-literal=master_key=$MASTER_KEY \
  --from-literal=database_url=$DB_URL
```

### 4 — Manifiestos Kubernetes

```bash
# Sustituir el placeholder con el Account ID real
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/" k8s/api-deployment.yaml

kubectl apply -f k8s/
kubectl get pods -n ai-gateway -w   # esperar Running (~2-3 min)
```

### 5 — Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --timeout 10m \
  -f monitoring/values.yaml
```

El `additionalServiceMonitors` del chart no crea el ServiceMonitor automáticamente en todas las versiones — aplicarlo a mano:

```bash
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: code-review-api
  namespace: monitoring
  labels:
    release: monitoring
spec:
  selector:
    matchLabels:
      app: code-review-api
  namespaceSelector:
    matchNames:
      - ai-gateway
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
EOF

# Acceder a Grafana (admin / capstone-grafana)
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# → http://localhost:3000
```

### 6 — Verificar el flujo completo

```bash
API_URL=$(kubectl get svc api-service -n ai-gateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://$API_URL/health
curl -X POST http://$API_URL/review \
  -H "Content-Type: application/json" \
  -d '{"code": "def suma(a,b): return a+b", "language": "python"}'
```

---

## Destruir la infraestructura

**Orden importante** — si se destruye antes de eliminar los Services, el NLB queda huérfano y Terraform no puede borrar la VPC.

```bash
helm uninstall monitoring -n monitoring
kubectl delete -f k8s/
kubectl delete namespace ai-gateway monitoring

# Esperar ~2 min a que AWS elimine el NLB
cd infra/
terraform destroy
```
