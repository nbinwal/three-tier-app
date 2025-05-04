# Three-Tier App on GCP (Terraform)

This repository provisions a three-tier web application on Google Cloud Platform (GCP) using Terraform. It supports both **PostgreSQL** and **MySQL** with optional load testing via **Locust**.

---

## 📋 Prerequisites

1. **Google Cloud SDK** installed and authenticated  
   👉 [Authenticate for using the gcloud CLI](https://cloud.google.com/docs/authentication/gcloud?utm_source=chatgpt.com)

2. **Terraform** v1.5+  
   👉 [Terraform CLI Reference](https://developer.hashicorp.com/terraform/cli/commands/init?utm_source=chatgpt.com)

3. **Python 3** and **pip** (for Locust)  
   👉 [Secret Manager Rotation Recommendations](https://cloud.google.com/secret-manager/docs/rotation-recommendations?utm_source=chatgpt.com)

4. A **GCP project** with billing enabled and sufficient IAM permissions (Owner/Editor)  
   👉 [Google Cloud Auth Guide](https://gcloud.readthedocs.io/en/latest/google-cloud-auth.html?utm_source=chatgpt.com)

---

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/nbinwal/three-tier-app.git
cd three-tier-app
