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
project_id      = "YOUR_GCP_PROJECT_ID"
region          = "us-central1"
zone            = "us-central1-a"
deployment_name = "three-tier-app"

# Choose "postgresql" or "mysql"
database_type   = "postgresql"

# PostgreSQL password (only if database_type = "postgresql")
pg_password     = "YOUR_SECURE_PG_PASSWORD"

# MySQL password (only if database_type = "mysql")
# mysql_password = "YOUR_SECURE_MYSQL_PASSWORD"

# Enable required APIs
enable_apis     = true

# (Optional) List of IAM roles to attach to the Run service account
default_run_roles = [
  "roles/iam.serviceAccountUser",
  "roles/cloudsql.client",
  "roles/redis.viewer",
  "roles/secretmanager.secretAccessor"
]

# Labels to apply to resources
event_labels = {
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

This section details the steps to perform load testing on the deployed application using Locust.

### Prerequisites

* Locust installed (`pip install locust`)
* `psql` command-line tool installed

### Setup and Configuration

1.  **Configure Cloud SQL Database Access:**
    * Spin up a private IP VM in the same VPC as the Cloud SQL Instance.
    * Download and set up the Cloud SQL Proxy.

    ```bash
    # Download Cloud SQL Proxy
    wget [https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64](https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64) -O cloud_sql_proxy
    chmod +x cloud_sql_proxy

    # Stop any existing proxy process
    pkill cloud_sql_proxy

    # Start Cloud SQL Proxy in the background
    # Replace project ID, region, and instance name if different
    ./cloud_sql_proxy \
      -instances="three-tier-web-app-457409:us-central1:three-tier-app-db-4097=tcp:5432" \
      -ip_address_types=PUBLIC &
    ```
    *Note: Keep the Cloud SQL Proxy running in a separate terminal or as a background process during testing.*

2.  **Set Database Password and Prepare Test Table:**
    * Set a password for the `postgres` user. **Choose a strong password and update it in the `locustfile.py` as well.**
    * Connect to the database via the proxy and create a table for load testing.

    ```bash
    # Set password (replace 'Newpassword' with your chosen password)
    gcloud sql users set-password postgres \
      --instance=three-tier-app-db-4097 \
      --password=Newpassword \
      --project=three-tier-web-app-457409

    # Connect using psql (enter 'Newpassword' or your chosen password when prompted)
    psql "host=127.0.0.1 port=5432 dbname=todo user=postgres sslmode=disable"

    # Inside psql, run the following SQL commands:
    CREATE TABLE loadtest_table (
      id  SERIAL PRIMARY KEY,
      stub TEXT
    );

    INSERT INTO loadtest_table (stub) VALUES
      ('foo'), ('bar'), ('baz');

    GRANT USAGE  ON SCHEMA public TO postgres;
    GRANT SELECT ON TABLE  loadtest_table TO postgres;

    # Exit psql
    \q
    ```

### Locust File (`locustfile.py`)

Save the following code as `locustfile.py` in your working directory.

* **Important:**
    * Update `DB_CONFIG` with your actual database `password`.
    * Update `FrontendUser.host` with your actual frontend Cloud Run URL.
    * Update `TodoUser.host` with your actual backend API Cloud Run URL.

```python
from locust import HttpUser, User, task, between
import psycopg2
import random
import time

# --- IMPORTANT: Update these connection details ---
DB_CONFIG = {
    "host": "127.0.0.1",  # Connect via Cloud SQL Proxy
    "port": 5432,
    "dbname": "todo",
    "user": "postgres",
    "password": "Newpassword" # <-- REPLACE WITH YOUR ACTUAL DB PASSWORD
}

FRONTEND_URL = "[https://three-tier-app-fe-qlxblrcnua-el.a.run.app](https://three-tier-app-fe-qlxblrcnua-el.a.run.app)" # <-- REPLACE WITH YOUR FRONTEND URL
BACKEND_API_URL = "[https://three-tier-app-api-815139404174.asia-south1.run.app](https://three-tier-app-api-815139404174.asia-south1.run.app)" # <-- REPLACE WITH YOUR BACKEND API URL
# --- End of update section ---


class FrontendUser(HttpUser):
    host = FRONTEND_URL
    wait_time = between(1,3)

    @task(3)
    def index(self):
        self.client.get("/", name="GET /")


class TodoUser(HttpUser):
    wait_time = between(1, 3)
    host = BACKEND_API_URL

    @task(4)
    def list_todos(self):
        self.client.get("/api/v1/todo", name="GET /api/v1/todo")

    @task(1)
    def create_todo(self):
        title = f"Load test task #{random.randint(1,10000)}"
        self.client.post(
            "/api/v1/todo",
            data={"title": title},
            name="POST /api/v1/todo",
            timeout=10
        )


class DBLoadUser(User):
    wait_time = between(1, 3)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.conn = None
        self.cursor = None
        try:
            self.conn = psycopg2.connect(**DB_CONFIG)
            self.cursor = self.conn.cursor()
        except psycopg2.OperationalError as e:
            print(f"DB connection failed: {e}")
            # Handle connection error appropriately, maybe exit locust?
            # For now, we just won't execute tasks if connection fails
            pass


    @task
    def query_db(self):
        if not self.cursor or not self.conn:
            # Skip task if connection failed during init
            print("Skipping DB task due to connection issue.")
            time.sleep(self.wait_time()) # Still wait to avoid busy-looping
            return

        start = time.time()
        try:
            self.cursor.execute("SELECT * FROM loadtest_table LIMIT 10")
            # Fetching results might be more realistic, but depends on test goals
            # results = self.cursor.fetchall()
            self.conn.commit() # Not strictly necessary for SELECT, but good practice
            rt = int((time.time() - start) * 1000)
            self.environment.events.request.fire(
                request_type="db",
                name="SELECT loadtest_table",
                response_time=rt,
                response_length=0, # Adjust if fetching data
                exception=None,
                context=self.user_context() # Pass user context if needed
            )
        except Exception as e:
            rt = int((time.time() - start) * 1000)
            self.environment.events.request.fire(
                request_type="db",
                name="SELECT loadtest_table",
                response_time=rt,
                response_length=0,
                exception=e,
                context=self.user_context() # Pass user context if needed
            )
            # Optional: Reconnect or handle specific errors
            # try:
            #    self.conn.rollback() # Rollback in case of error during transaction
            # except psycopg2.InterfaceError:
                 # Handle case where connection might be closed
            #    pass


    def on_stop(self):
        if self.cursor:
            self.cursor.close()
        if self.conn:
            self.conn.close()

    # Helper to provide context for events if needed
    def user_context(self):
        return {"user_id": self.environment.runner.user_id if self.environment.runner else "N/A"}

  3.  **Run the locust test:**

      Example for 20 users, spawning 5 per second, running for 3 minutes:
      locust --headless --users 20 --spawn-rate 5 --run-time 3m -f locustfile.py --only-summary

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
