## Prerequisites  
1. **Google Cloud SDK** installed and authenticated to your project via the CLI (`gcloud auth login`)  ([Authenticate for using the gcloud CLI](https://cloud.google.com/docs/authentication/gcloud?utm_source=chatgpt.com)).  
2. **Terraform** (v1.5 or later) installed locally  ([terraform init command reference - HashiCorp Developer](https://developer.hashicorp.com/terraform/cli/commands/init?utm_source=chatgpt.com)).  
3. **Python 3** and **pip** for Locust installation  ([About rotation schedules - Secret Manager - Google Cloud](https://cloud.google.com/secret-manager/docs/rotation-recommendations?utm_source=chatgpt.com)).  
4. A Google Cloud **project** with billing enabled and your user having Owner or Editor IAM roles  ([Authentication — google-cloud 0.20.0 documentation](https://gcloud.readthedocs.io/en/latest/google-cloud-auth.html?utm_source=chatgpt.com)).  

---

## 1. Clone the Repository  
```bash
git clone https://github.com/nbinwal/three-tier-app.git
cd three-tier-app
```  
This repository contains: `main.tf`, `variables.tf`, `outputs.tf`, and `versions.tf`  ([GitHub - nbinwal/three-tier-app](https://github.com/nbinwal/three-tier-app/tree/main)).

---

## 2. Configure Environment Variables  
Create a `terraform.tfvars` file at the root with your parameters:
```hcl
project_id      = "trusty-stacker-453107-i1"
deployment_name = "three-tier-app"

# Choose either "postgresql" or "mysql"
database_type   = "postgresql"

# Enable required APIs
enable_apis = true

# IAM roles for the Cloud Run service account
run_roles_list = [
  "roles/iam.serviceAccountUser",
  "roles/cloudsql.client",
  "roles/redis.viewer",
  "roles/secretmanager.secretAccessor"
]

# Labels for all resources
labels = {
  environment = "dev"
  project     = "three-tier-app"
}

```
Terraform will automatically load `terraform.tfvars` during plan and apply  ([three-tier-app/variables.tf at main · nbinwal/three-tier-app · GitHub](https://github.com/nbinwal/three-tier-app/blob/main/variables.tf)).

---

## 3. Authenticate with GCP  
Ensure the gcloud CLI is using the correct project and credentials:
```bash
gcloud auth login                            # Sign in to Google Cloud SDK  ([Authenticate for using the gcloud CLI](https://cloud.google.com/docs/authentication/gcloud?utm_source=chatgpt.com))
gcloud config set project YOUR_GCP_PROJECT_ID
```
Alternatively, on a Compute Engine VM, Application Default Credentials are automatically provided  ([Authentication — google-cloud 0.20.0 documentation](https://gcloud.readthedocs.io/en/latest/google-cloud-auth.html?utm_source=chatgpt.com)).

---

## 4. Initialize Terraform  
```bash
terraform init
```
- Installs provider plugins and modules.  
- Prepares the working directory for planning and applying  ([terraform init command reference - HashiCorp Developer](https://developer.hashicorp.com/terraform/cli/commands/init?utm_source=chatgpt.com)).

---

## 5. Review the Execution Plan  
```bash
terraform plan -out=tfplan
```
- Generates an execution plan to preview resource changes without applying them  ([terraform plan command reference - HashiCorp Developer](https://developer.hashicorp.com/terraform/cli/commands/plan?utm_source=chatgpt.com)).

---

## 6. Apply Terraform Configuration  
```bash
terraform apply tfplan
```
- Provisions all GCP resources: VPC, Redis, Cloud SQL, IAM, Secret Manager, Cloud Run, etc.  
- Use `-auto-approve` to skip confirmation if desired  ([terraform apply command reference - HashiCorp Developer](https://developer.hashicorp.com/terraform/cli/commands/apply?utm_source=chatgpt.com)).

---

## 7. View Outputs  
After apply completes, Terraform will display outputs:
- **endpoint**: Frontend URL (`todo-fe`)  
- **sql_instance_name**: Cloud SQL instance name  
- **secret_manager_password_secret**: Secret Manager resource name  
- **in_console_tutorial_url**: Quick-start link in the GCP Console  
You can also retrieve them with:
```bash
terraform output endpoint
```
---

## 8. Load Testing with Locust  
1. **Install Locust**:
   ```bash
   pip3 install locust
   ```  
    ([About rotation schedules - Secret Manager - Google Cloud](https://cloud.google.com/secret-manager/docs/rotation-recommendations?utm_source=chatgpt.com))  
2. **Create `locustfile.py`** in the project root:
   ```python
   from locust import HttpUser, task, between

   class TodoUser(HttpUser):
       wait_time = between(1, 3)

       @task(4)
       def list_tasks(self):
           self.client.get("/api/tasks")

       @task(1)
       def create_task(self):
           self.client.post("/api/task", json={"title": "Load Test"})
   ```
    ([About rotation schedules - Secret Manager - Google Cloud](https://cloud.google.com/secret-manager/docs/rotation-recommendations?utm_source=chatgpt.com))  
3. **Run Locust (headless)**:
   ```bash
   locust \
     --headless \
     --users 200 \
     --spawn-rate 20 \
     --host $(terraform output -raw endpoint) \
     --run-time 15m \
     --csv=results
   ```  
   This simulates 200 users ramping at 20 users/s over 15 minutes  ([How to use Google Cloud's automatic password rotation](https://cloud.google.com/blog/products/identity-security/how-to-use-google-clouds-automatic-password-rotation?utm_source=chatgpt.com)).  

---

## 9. Cleanup  
To destroy all resources created by this Terraform configuration:
```bash
terraform destroy -auto-approve
```
This command removes the VPC, Redis, SQL instance, Cloud Run services, and all related IAM bindings.

---

## References  
- **GitHub Repo**: https://github.com/nbinwal/three-tier-app/tree/main  ([GitHub - nbinwal/three-tier-app](https://github.com/nbinwal/three-tier-app/tree/main))  
- **Terraform init**: https://developer.hashicorp.com/terraform/cli/commands/init  ([terraform init command reference - HashiCorp Developer](https://developer.hashicorp.com/terraform/cli/commands/init?utm_source=chatgpt.com))  
- **Terraform plan**: https://developer.hashicorp.com/terraform/cli/commands/plan  ([terraform plan command reference - HashiCorp Developer](https://developer.hashicorp.com/terraform/cli/commands/plan?utm_source=chatgpt.com))  
- **Terraform apply**: https://developer.hashicorp.com/terraform/cli/commands/apply  ([terraform apply command reference - HashiCorp Developer](https://developer.hashicorp.com/terraform/cli/commands/apply?utm_source=chatgpt.com))  
- **gcloud auth**: https://cloud.google.com/docs/authentication/gcloud  ([Authenticate for using the gcloud CLI](https://cloud.google.com/docs/authentication/gcloud?utm_source=chatgpt.com))  
- **GCP Application Default Credentials**: https://cloud.google.com/docs/authentication/production  ([Authentication — google-cloud 0.20.0 documentation](https://gcloud.readthedocs.io/en/latest/google-cloud-auth.html?utm_source=chatgpt.com))  
- **Variables reference**: https://github.com/nbinwal/three-tier-app/blob/main/variables.tf  ([three-tier-app/variables.tf at main · nbinwal/three-tier-app · GitHub](https://github.com/nbinwal/three-tier-app/blob/main/variables.tf))  
- **Locust write tests**: https://docs.locust.io/en/stable/writing-a-locustfile.html  ([About rotation schedules - Secret Manager - Google Cloud](https://cloud.google.com/secret-manager/docs/rotation-recommendations?utm_source=chatgpt.com))  
- **Locust quickstart**: https://docs.locust.io/en/stable/quickstart.html  ([How to use Google Cloud's automatic password rotation](https://cloud.google.com/blog/products/identity-security/how-to-use-google-clouds-automatic-password-rotation?utm_source=chatgpt.com))  
- **GCP Cloud Run autoscaling**: https://cloud.google.com/run/docs/about-instance-autoscaling  ([GitHub - nbinwal/three-tier-app](https://github.com/nbinwal/three-tier-app/tree/main))
