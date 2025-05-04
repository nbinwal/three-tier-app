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
region          = "asia-south1"
zone            = "asia-south1-a"

# Choose ONE database type (comment/uncomment as needed)
database_type   = "postgresql"  # For PostgreSQL
#database_type   = "mysql"      # For MySQL

project_id      = "trusty-stacker-453107-i1"
deployment_name = "three-tier-app"
enable_apis     = true

# Only required for MySQL (comment when using PostgreSQL)
#mysql_password  = "whatever"

# IAM roles (automatically adjusts based on database type)
run_roles_list = [
  "roles/cloudsql.instanceUser",
  "roles/cloudsql.client",
  "roles/iam.serviceAccountUser",
  "roles/redis.viewer",
  # Uncomment next line for MySQL
  #"roles/secretmanager.secretAccessor"  
]

labels = {
  environment = "dev",
  project     = "three-tier-app",
  managed-by  = "terraform"
}
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
    * Set Up Cloud Nat for that VM to communicate to the Internet.
    * Download and set up the Cloud SQL Proxy.

    ```bash
    # Download Cloud SQL Proxy
    wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
    chmod +x cloud_sql_proxy

    # Stop any existing proxy process
    pkill cloud_sql_proxy

    # Start Cloud SQL Proxy in the background
    # Replace project ID, region, and instance name if different
    Refer https://cloud.google.com/sql/docs/postgres/connect-auth-proxy#start-proxy
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

from locust import HttpUser, task, between
import psycopg2
import random
import time

# --- Update these URLs to your deployed services ---
FRONTEND_URL = "https://three-tier-app-fe-1049385999004.asia-south1.run.app"
API_URL = "https://three-tier-app-api-zfm42p5nvq-el.a.run.app"
# -----------------------------------------------

class FrontendUser(HttpUser):
    host = FRONTEND_URL
    wait_time = between(1, 1)

    @task
    def load_frontend(self):
        # Test the root endpoint of the frontend
        self.client.get("/", name="GET /")

class ApiUser(HttpUser):
    host = API_URL
    # Wait 0.5s between tasks: ~4 RPS per user
    wait_time = between(0.5, 0.5)

    @task(1)
    def list_todos(self):
        # Test listing todos
        self.client.get("/api/v1/todo", name="GET /api/v1/todo")

    @task(1)
    def create_todo(self):
        # Test creating a new todo
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
                # Connect via Cloud SQL Proxy
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
            # Skip task if connection failed
            print("Skipping DB task due to connection issue.")
            return

        start = time.time()
        try:
            self.cursor.execute("SELECT * FROM loadtest_table LIMIT 10")
            results = self.cursor.fetchall()
            print(f"Fetched {len(results)} rows")
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
        # Safely get user_id if available
        user_id = getattr(self.environment.runner, 'user_id', 'N/A')
        return {"user_id": user_id}

  3.  **Run the locust test:**

      Example for 20 users, spawning 5 per second, running for 3 minutes:
      locust --headless   --users 20   --spawn-rate 20   --run-time 5m   -f locustfile.py   --only-summary

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
