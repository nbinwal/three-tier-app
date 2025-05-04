# Three-Tier App Deployment on Google Cloud with Terraform

This repository contains a complete example of deploying a three-tier application on Google Cloud using Terraform. It provisions a Cloud Run frontend and API, a Redis instance, Cloud SQL (PostgreSQL or MySQL), Secret Manager, VPC access, and IAM roles.

---

## Prerequisites

1. **Google Cloud SDK** installed and authenticated via the CLI  
   👉 [Authenticate for using the gcloud CLI](https://cloud.google.com/docs/authentication/gcloud?utm_source=chatgpt.com)

2. **Terraform** (v1.5 or later) installed  
   👉 [Terraform CLI Init Command](https://developer.hashicorp.com/terraform/cli/commands/init?utm_source=chatgpt.com)

3. **Python 3** and **pip** installed (for Locust)  
   👉 [Secret Manager Rotation Recommendations](https://cloud.google.com/secret-manager/docs/rotation-recommendations?utm_source=chatgpt.com)

4. A Google Cloud **project** with billing enabled and required IAM roles  
   👉 [Google Cloud Auth Documentation](https://gcloud.readthedocs.io/en/latest/google-cloud-auth.html?utm_source=chatgpt.com)

---

## 1. Clone the Repository

```bash
git clone https://github.com/nbinwal/three-tier-app.git
cd three-tier-app
