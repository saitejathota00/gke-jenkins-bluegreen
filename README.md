
# GKE Blue-Green Deployment with Jenkins + Terraform

This repository demonstrates a complete **Infrastructure as Code (IaC)** and **CI/CD pipeline** for deploying applications on **Google Kubernetes Engine (GKE)** with a **blue-green deployment strategy** to ensure minimal downtime.

- **Infrastructure provisioning** is automated with **Terraform**, executed via **GitHub Actions**.  
- **Application deployment** is managed via **Jenkins**, with manual pipeline triggers and a webhook configured for this repository.  
- **Blue-Green deployments** provide seamless traffic switching between environments.  

---

## Repository Structure

```

.
├── app/                 # Simple Nginx app (Dockerfile + index.html)
├── k8s/                 # Kubernetes manifests (deployments, services, HPA, loadgen, configmaps)
├── terraform/           # Terraform configs for infra (VPC, GKE, Artifact Registry)
├── Jenkinsfile          # Jenkins pipeline definition
└── README.md            # Documentation

````

---

## Service Accounts

We used two service accounts to separate responsibilities:

1. **Terraform Deployer (`tf-deployer`)**
   - Used by **GitHub Actions** to provision infrastructure with Terraform.
   - Roles:
     - `roles/container.admin`
     - `roles/artifactregistry.admin`
     - `roles/iam.serviceAccountUser`
   - Credentials are handled as a **GitHub Actions secret** (`GCP_TF_KEY`).

2. **Jenkins Deployer (`jenkins-deployer`)**
   - Used by **Jenkins pipeline** for image builds and GKE deployments.
   - Roles:
     - `roles/artifactregistry.writer`
     - `roles/container.admin`
     - `roles/iam.serviceAccountUser`
   - Uploaded to Jenkins as a **secret file credential** (`gcp-sa`).

---

## Infrastructure Setup (Terraform + GitHub Actions)

- **Terraform configs** (`/terraform`) provision:
  - VPC & subnet
  - GKE cluster (`demo-gke`) in `asia-south1-a`
  - Artifact Registry (`demo-repo`) for Docker images

- **GitHub Actions workflow**:
  - Reads the `tf-deployer` service account key from repo secrets (`GCP_TF_KEY`).
  - Runs `terraform init/plan/apply` on push to `main`.
  - Keeps infrastructure in sync with code.

---

## Application Deployment (Jenkins)

- **Jenkins Server** runs on AWS EC2, with worker agents.  
- **Pipeline is triggered manually**, but a **webhook** can be configured from GitHub to Jenkins so jobs can also be triggered on code changes if needed.  
- **Blue Ocean plugin** provides visual pipeline UI.  
- Pipeline authenticates to GCP using `jenkins-deployer` credentials (`gcp-sa`).  

---

## Jenkins Pipeline (Jenkinsfile)

The pipeline implements **blue-green deployments** with minimal downtime:

1. **Checkout** → Pulls repo code.  
2. **Set Build Vars** → Derives Docker image tag from Git commit.  
3. **Authenticate to GCP** → Service account (`gcp-sa`) injected as secret file.  
4. **Build & Push Docker Image** → Pushed to Artifact Registry.  
5. **Decide Target Color** → If current is `blue`, deploy `green`, else vice versa.  
6. **Deploy Target** → Apply Kubernetes manifests for the target color.  
7. **Smoke Test** → Run curl pod inside cluster to verify.  
8. **Switch Traffic** → Update `web` service selector to point to the target color.  
9. **Post Verification** → Inspect deployments, pods, HPA.  
10. **Post Actions**:  
    - Success → scale down old deployment.  
    - Failure → rollback service to previous color.  

---

## Kubernetes Components (`/k8s`)

- **Deployments**:  
  - `deploy-blue.yaml` / `deploy-green.yaml` mount HTML from configmaps (`cm-blue.yaml`, `cm-green.yaml`).  
- **Service**:  
  - A single LoadBalancer (`service.yaml`) with dynamic selector switching between `blue` and `green`.  
- **HPA**:  
  - `hpa.yaml` enables autoscaling from 2–10 pods based on CPU load.  
- **Load Generator**:  
  - `loadgen/loadgen-deploy.yaml` produces synthetic traffic to test HPA.  

---

## Deployment Flow

1. **Infra Provisioning**  
   - GitHub Actions runs Terraform with `tf-deployer` service account.  

2. **Pipeline Execution**  
   - Jenkins job triggered manually (or via webhook).  
   - Pipeline builds image, deploys target color, and switches traffic.  

3. **Traffic Switching**  
   - Service selector updates atomically.  
   - End users experience **zero downtime** as traffic flips between blue and green pods.  

---

## Demo Verification

1. **Check which color is live**
   ```bash
   kubectl -n demo get svc web -o jsonpath='{.spec.selector.color}{"\n"}'
````

2. **Hit the LoadBalancer repeatedly**

   ```bash
   EXTERNAL_IP=$(kubectl -n demo get svc web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   watch -n1 curl -s http://$EXTERNAL_IP/
   ```

   👉 Output switches from `BLUE` → `GREEN` seamlessly.

3. **Inspect deployments**

   ```bash
   kubectl -n demo get deploy,svc,pods,hpa -o wide
   ```

---

## Outcome

* ✅ Infrastructure as Code via Terraform + GitHub Actions
* ✅ Application deployment via Jenkins pipeline
* ✅ Blue-Green strategy with minimal downtime
* ✅ Autoscaling with HPA + synthetic traffic (loadgen)




## ✅ Demonstration

### 1. Auto-scaling
- Load generated via `loadgen` deployment  
- HPA scaled `web-blue` pods from 2 → 4 during traffic  
- Scaled back down when load stopped  

(Screenshot reference: `proof-hpa-scale.png`)  

### 2. Blue-Green Deployment
- Initial live environment: **blue**  
- Jenkins pipeline deployed **green**  
- Service selector switched → minimal downtime  
- ConfigMap HTML verified pod color responses  

(Screenshot reference: `proof-blue-green-switch.png`)  

---

## 🧩 Approach & Challenges

- **Approach**:  
  - Infrastructure = Terraform (via GitHub Actions)  
  - Application = Jenkins (manual trigger + webhook configured)  
  - Blue-Green = Service selector flip between `blue` and `green`  
  - HPA = Stress test with synthetic load generator  

- **Challenges**:  
  - Correct IAM permissions for Jenkins SA (`iam.serviceAccountUser` required).  
  - `metrics-server` configuration to expose CPU metrics for HPA.  
  - ConfigMap mounting — initially both deployments served default Nginx page.  
  - Artifact Registry ImagePull errors — fixed by authenticating Docker in Jenkins pipeline.  

📌 **Note:** All **screenshots, logs, and process documentation** are provided in a **separate document** (attached with the submission email) to keep the repository clean and focused.






