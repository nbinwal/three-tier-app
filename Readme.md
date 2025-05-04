````markdown
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
````

This repository contains Terraform files like `main.tf`, `variables.tf`, `outputs.tf`, and `versions.tf`.

---

## 2. Configure Environment Variables

Create a `terraform.tfvars` file in the root directory:

```hcl
region          = "asia-south1"
zone            = "asia-south1-a"

# Choose ONE database type
database_type   = "postgresql"  # For PostgreSQL
# database_type = "mysql"       # For MySQL

project_id      = "trusty-stacker-453107-i1"
deployment_name = "three-tier-app"
enable_apis     = true

# Only required for MySQL
# mysql_password = "your-password"

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

Terraform automatically loads `terraform.tfvars`.

---

## 3. Authenticate with GCP

```bash
gcloud auth login
gcloud config set project YOUR_GCP_PROJECT_ID
```

On Compute Engine, Application Default Credentials are used automatically.

---

## 4. Initialize Terraform

```bash
terraform init
```

---

## 5. Review the Execution Plan

```bash
terraform plan -out=tfplan
```

---

## 6. Apply Terraform Configuration

```bash
terraform apply tfplan
```

To auto-approve:

```bash
terraform apply -auto-approve
```

---

## 7. View Outputs

After `apply`, Terraform shows outputs like:

* `endpoint`: Frontend URL
* `sql_instance_name`: Cloud SQL instance
* `secret_manager_password_secret`: Secret Manager secret
* `in_console_tutorial_url`: GCP Console shortcut

You can retrieve specific outputs:

```bash
terraform output endpoint
```

---

## 8. Load Testing with Locust

### Prerequisites

* Install Locust: `pip install locust`
* Install PostgreSQL CLI: `psql`

---

### 8.1. Configure Cloud SQL Access

1. SSH into a private IP VM:

```bash
gcloud compute ssh test-3tierweb-app \
  --zone=asia-south1-a \
  --tunnel-through-iap
```

2. Download and run the Cloud SQL Proxy:

```bash
wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
chmod +x cloud_sql_proxy
pkill cloud_sql_proxy || true

# Refer to: https://cloud.google.com/sql/docs/postgres/connect-auth-proxy#start-proxy
./cloud_sql_proxy -instances=trusty-stacker-453107-i1:asia-south1:three-tier-app-db-8463=tcp:5432 &
```

Keep the proxy running in a background terminal.

---

### 8.2. Set DB Password and Create Table

```bash
gcloud sql users set-password postgres \
  --instance=three-tier-app-db-8463 \
  --password=Newpassword \
  --project=trusty-stacker-453107-i1

psql "host=127.0.0.1 port=5432 dbname=todo user=postgres sslmode=disable"

-- In psql:
CREATE TABLE loadtest_table (
  id SERIAL PRIMARY KEY,
  stub TEXT
);

INSERT INTO loadtest_table (stub) VALUES ('foo'), ('bar'), ('baz');
GRANT USAGE ON SCHEMA public TO postgres;
GRANT SELECT ON loadtest_table TO postgres;
\q
```

---

### 8.3. Locust File

Save the following as `locustfile.py`:

```python
from locust import HttpUser, task, between
import psycopg2
import random
import time

FRONTEND_URL = "https://three-tier-app-fe-1049385999004.asia-south1.run.app"
API_URL = "https://three-tier-app-api-zfm42p5nvq-el.a.run.app"

class FrontendUser(HttpUser):
    host = FRONTEND_URL
    wait_time = between(1, 1)

    @task
    def load_frontend(self):
        self.client.get("/", name="GET /")

class ApiUser(HttpUser):
    host = API_URL
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
    host = API_URL
    wait_time = between(1, 3)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.conn = None
        self.cursor = None
        retries = 3
        for attempt in range(retries):
            try:
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
            self.cursor.fetchall()
            self.conn.commit()
            rt = int((time.time() - start) * 1000)
            self.environment.events.request.fire(
                request_type="db",
                name="SELECT loadtest_table",
                response_time=rt,
                response_length=0,
                exception=None,
                context=self.user_context()
            )
        except Exception as e:
            rt = int((time.time() - start) * 1000)
            self.environment.events.request.fire(
                request_type="db",
                name="SELECT loadtest_table",
                response_time=rt,
                response_length=0,
                exception=e,
                context=self.user_context()
            )

    def on_stop(self):
        if self.cursor:
            self.cursor.close()
        if self.conn:
            self.conn.close()

    def user_context(self):
        user_id = getattr(self.environment.runner, 'user_id', 'N/A')
        return {"user_id": user_id}
```

---

### 8.4. Run Locust

Example with 20 users for 5 minutes:

```bash
locust --headless --users 20 --spawn-rate 20 --run-time 5m -f locustfile.py --only-summary
```

---

## 9. Cleanup

To destroy all resources:

```bash
terraform destroy -auto-approve
```

---

## References

* [GitHub Repository](https://github.com/nbinwal/three-tier-app)
* [Terraform Init](https://developer.hashicorp.com/terraform/cli/commands/init)
* [Terraform Plan](https://developer.hashicorp.com/terraform/cli/commands/plan)
* [Terraform Apply](https://developer.hashicorp.com/terraform/cli/commands/apply)
* [gcloud Auth](https://cloud.google.com/docs/authentication/gcloud)
* [Application Default Credentials](https://cloud.google.com/docs/authentication/production)
* [Variables Reference](https://github.com/nbinwal/three-tier-app/blob/main/variables.tf)
* [Locust Documentation](https://docs.locust.io/en/stable/quickstart.html)
* [GCP Cloud Run Autoscaling](https://cloud.google.com/run/docs/about-instance-autoscaling)
