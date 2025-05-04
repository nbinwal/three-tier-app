
# Three‑Tier App Deployment on Google Cloud with Terraform

This repository provisions a three‑tier web application on Google Cloud using Terraform.  
It includes a Cloud Run frontend & API, Redis, Cloud SQL (PostgreSQL/MySQL), Secret Manager, VPC access, and IAM roles.

---

## Table of Contents

- [Prerequisites](#prerequisites)  
- [Clone the Repository](#clone-the-repository)  
- [Configure Environment Variables](#configure-environment-variables)  
- [Authenticate with GCP](#authenticate-with-gcp)  
- [Initialize Terraform](#initialize-terraform)  
- [Review the Execution Plan](#review-the-execution-plan)  
- [Apply Terraform Configuration](#apply-terraform-configuration)  
- [View Outputs](#view-outputs)  
- [Load Testing with Locust](#load-testing-with-locust)  
  - [Configure Cloud SQL Access](#configure-cloud-sql-access)  
  - [Set DB Password & Create Table](#set-db-password--create-table)  
  - [Locustfile](#locustfile)  
  - [Run Locust](#run-locust)  
- [Frontend and Middle Tier Testing from External User Perspective](#frontend-and-middle-tier-testing-from-external-user-perspective)  
- [Cleanup](#cleanup)  
- [References](#references)  
- [License](#license)  

---

## Prerequisites

- **Google Cloud SDK** installed and authenticated  
  👉 [Authenticate with the gcloud CLI](https://cloud.google.com/docs/authentication/gcloud?utm_source=chatgpt.com)  

- **Terraform** (v1.5+) installed locally  
  👉 [Terraform init docs](https://developer.hashicorp.com/terraform/cli/commands/init?utm_source=chatgpt.com)  

- **Python 3** and **pip** installed (for Locust)  
  👉 [Secret Manager rotation guide](https://cloud.google.com/secret-manager/docs/rotation-recommendations?utm_source=chatgpt.com)  

- A **GCP project** with billing enabled and Owner/Editor IAM roles  
  👉 [GCP Auth documentation](https://gcloud.readthedocs.io/en/latest/google-cloud-auth.html?utm_source=chatgpt.com)  

---

## Clone the Repository

```bash
git clone https://github.com/nbinwal/three-tier-app.git
cd three-tier-app
````

This repo contains: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`. ([GitHub][1])

---

## Configure Environment Variables

Create a `terraform.tfvars` file in the project root:

```hcl
region          = "asia-south1"
zone            = "asia-south1-a"

# Choose ONE database type:
database_type   = "postgresql"  # For PostgreSQL
# database_type = "mysql"       # For MySQL

project_id      = "trusty-stacker-453107-i1"
deployment_name = "three-tier-app"
enable_apis     = true

# Only for MySQL:
# mysql_password = "your_mysql_password"

run_roles_list = [
  "roles/cloudsql.instanceUser",
  "roles/cloudsql.client",
  "roles/iam.serviceAccountUser",
  "roles/redis.viewer",
  # "roles/secretmanager.secretAccessor"  # Uncomment for MySQL
]

labels = {
  environment = "dev"
  project     = "three-tier-app"
  managed-by  = "terraform"
}

event_labels = {
  environment = "dev"
  project     = "three-tier-app"
}
```

Terraform will automatically load `terraform.tfvars`. ([GitHub][1])

---

## Authenticate with GCP

```bash
gcloud auth login
gcloud config set project YOUR_GCP_PROJECT_ID
```

On Compute Engine VMs, Application Default Credentials (ADC) are used automatically. ([GitHub][1])

---

## Initialize Terraform

```bash
terraform init
```

---

## Review the Execution Plan

```bash
terraform plan -out=tfplan
```

---

## Apply Terraform Configuration

```bash
terraform apply tfplan
```

To skip interactive approval:

```bash
terraform apply -auto-approve
```

---

## View Outputs

After a successful apply, Terraform displays outputs:

* **endpoint** – Frontend URL
* **sql\_instance\_name** – Cloud SQL instance name
* **secret\_manager\_password\_secret** – Secret Manager resource name
* **in\_console\_tutorial\_url** – GCP Console quick‑start link

Fetch any output manually:

```bash
terraform output endpoint
```

---

## Load Testing with Locust

### Configure Cloud SQL Access

1. SSH into a private‑IP VM:

   ```bash
   gcloud compute ssh test-3tierweb-app \
     --zone=asia-south1-a \
     --tunnel-through-iap
   ```

2. Download and start the Cloud SQL Proxy:

   ```bash
   wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
   chmod +x cloud_sql_proxy
   pkill cloud_sql_proxy || true
   ./cloud_sql_proxy \
     -instances=trusty-stacker-453107-i1:asia-south1:three-tier-app-db-8463=tcp:5432 &
   ```

Keep the proxy running in a separate terminal. ([GitHub][1])

### Set DB Password & Create Table

```bash
gcloud sql users set-password postgres \
  --instance=three-tier-app-db-8463 \
  --password=Newpassword \
  --project=trusty-stacker-453107-i1

psql "host=127.0.0.1 port=5432 dbname=todo user=postgres sslmode=disable"
```

Then run:

```sql
CREATE TABLE loadtest_table (
  id SERIAL PRIMARY KEY,
  stub TEXT
);

INSERT INTO loadtest_table (stub)
VALUES ('foo'), ('bar'), ('baz');

GRANT USAGE ON SCHEMA public TO postgres;
GRANT SELECT ON loadtest_table TO postgres;

\q
```

### Locustfile

Save this as `locustfile.py`:

```python
from locust import HttpUser, task, between
import psycopg2
import random
import time

# Update these URLs to match your deployed services:
FRONTEND_URL = "https://three-tier-app-fe-1049385999004.asia-south1.run.app"
API_URL      = "https://three-tier-app-api-zfm42p5nvq-el.a.run.app"

class FrontendUser(HttpUser):
    host      = FRONTEND_URL
    wait_time = between(1, 1)

    @task
    def load_frontend(self):
        self.client.get("/", name="GET /")

class ApiUser(HttpUser):
    host      = API_URL
    wait_time = between(0.5, 0.5)

    @task(1)
    def list_todos(self):
        self.client.get("/api/v1/todo", name="GET /api/v1/todo")

    @task(1)
    def create_todo(self):
        title = f"Load test task #{random.randint(1, 10000)}"
        self.client.post(
            "/api/v1/todo",
            json={"title": title},
            name="POST /api/v1/todo",
            timeout=10
        )

class DBLoadUser(HttpUser):
    host      = API_URL
    wait_time = between(1, 3)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.conn   = None
        self.cursor = None
        retries = 3
        for attempt in range(retries):
            try:
                # Connect via Cloud SQL Proxy (must be running locally)
                self.conn = psycopg2.connect(
                    host="127.0.0.1", port=5432, dbname="todo",
                    user="postgres", password="Newpassword"
                )
                self.cursor = self.conn.cursor()
                break
            except psycopg2.OperationalError as e:
                print(f"DB connection failed: {e}. Retrying ({attempt+1}/{retries})...")
                time.sleep(5)

    @task
    def query_db(self):
        if not self.cursor or not self.conn:
            print("Skipping DB task due to connection issue.")
            return

        start = time.time()
        try:
            self.cursor.execute("SELECT * FROM loadtest_table LIMIT 10")
            _ = self.cursor.fetchall()
            self.conn.commit()
            rt = int((time.time() - start) * 1000)
            self.environment.events.request.fire(
                request_type="db",
                name="SELECT loadtest_table",
                response_time=rt,
                response_length=0,
                exception=None,
                context={"user_id": getattr(self.environment.runner, 'user_id', 'N/A')}
            )
        except Exception as e:
            rt = int((time.time() - start) * 1000)
            self.environment.events.request.fire(
                request_type="db",
                name="SELECT loadtest_table",
                response_time=rt,
                response_length=0,
                exception=e,
                context={"user_id": getattr(self.environment.runner, 'user_id', 'N/A')}
            )

    def on_stop(self):
        if self.cursor:
            self.cursor.close()
        if self.conn:
            self.conn.close()
```

---

## Frontend and Middle Tier Testing from External User Perspective

To simulate real-world external traffic, use the **hey** HTTP load generator ([Homebrew Formulae][2]):

```bash
brew install hey

hey -z 2m -c 350 https://three-tier-app-fe-1049385999004.us-central1.run.app/

hey -z 5m -c 500 https://three-tier-app-api-zfm42p5nvq-el.a.run.app/api/v1/todo
```

---

## Cleanup

```bash
terraform destroy -auto-approve
```

---

## References

* [GitHub: three-tier-app](https://github.com/nbinwal/three-tier-app) ([GitHub][1])
* [Homebrew Formula for hey](https://formulae.brew.sh/formula/hey) ([Homebrew Formulae][2])
* [hey on GitHub](https://github.com/rakyll/hey) ([GitHub][3])
* [Terraform init](https://developer.hashicorp.com/terraform/cli/commands/init)
* [Terraform plan](https://developer.hashicorp.com/terraform/cli/commands/plan)
* [Terraform apply](https://developer.hashicorp.com/terraform/cli/commands/apply)
* [gcloud auth](https://cloud.google.com/docs/authentication/gcloud)
* [GCP Auth](https://gcloud.readthedocs.io/en/latest/google-cloud-auth.html)
* [Locust docs](https://docs.locust.io/en/stable/quickstart.html)
* [Cloud Run autoscaling](https://cloud.google.com/run/docs/about-instance-autoscaling)

---

## License

This project is open‑source under the [MIT License](LICENSE).

```

You can copy & paste this into your `README.md` (or submit it as a PR) to retain all original content and add the requested **Frontend and Middle Tier Testing** section. Let me know if you’d like any tweaks!
::contentReference[oaicite:8]{index=8}
```

[1]: https://raw.githubusercontent.com/nbinwal/three-tier-app/main/Readme.md "raw.githubusercontent.com"
[2]: https://formulae.brew.sh/formula/hey?utm_source=chatgpt.com "hey - Homebrew Formulae"
[3]: https://github.com/rakyll/hey?utm_source=chatgpt.com "rakyll/hey: HTTP load generator, ApacheBench (ab) replacement"
