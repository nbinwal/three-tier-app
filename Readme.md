## Overview

This README explains how to perform HTTP load testing on a Google Cloud Run front-end service using Apache JMeter.  ([Load testing best practices | Cloud Run Documentation](https://cloud.google.com/run/docs/about-load-testing?utm_source=chatgpt.com)) It walks through installing JMeter on your Mac, configuring Cloud Run for test access, building a JMeter Test Plan, running tests in non-GUI mode, and interpreting results.  ([Apache JMeter - Apache JMeter™](https://jmeter.apache.org/?utm_source=chatgpt.com))

---

## Prerequisites

1. **A running Cloud Run service**  
   You must have already deployed your front-end container and have its URL (e.g., `https://<SERVICE_ID>-<HASH>.run.app`).  ([Load testing best practices | Cloud Run Documentation](https://cloud.google.com/run/docs/about-load-testing?utm_source=chatgpt.com))  
2. **A VM or machine with JMeter installed**  
   Tests should originate from an environment with network access to your Cloud Run service—often a Compute Engine VM in the same VPC so you can use Developer Authentication.  ([Load testing best practices | Cloud Run Documentation](https://cloud.google.com/run/docs/about-load-testing?utm_source=chatgpt.com))  
3. **Java 8 or higher installed**  
   JMeter is a pure Java 8+ application; ensure `java -version` returns at least Java 8.  ([Apache JMeter - Apache JMeter™](https://jmeter.apache.org/?utm_source=chatgpt.com))  

---

## 1. Install Apache JMeter

1. **Download JMeter**  
   Get the latest binaries from the official download page:  
   ```text
   https://jmeter.apache.org/download_jmeter.cgi
   ```  
    ([Download Apache JMeter](https://jmeter.apache.org/download_jmeter.cgi?utm_source=chatgpt.com))  
2. **Extract and install**  
   ```bash
   tar -xzf apache-jmeter-5.6.3.tgz
   mv apache-jmeter-5.6.3 ~/jmeter
   ```  
    ([Download Apache JMeter](https://jmeter.apache.org/download_jmeter.cgi?utm_source=chatgpt.com))  
3. **Verify installation**  
   ```bash
   ~/jmeter/bin/jmeter --version
   ```  
   You should see `Apache JMeter 5.x` printed.   
4. **Use CLI mode for load tests**  
   Non-GUI (CLI) mode is recommended for performance:  
   ```bash
   ~/jmeter/bin/jmeter -n -v
   ```  
    ([Apache JMeter - User's Manual](https://jmeter.apache.org/usermanual/index.html?utm_source=chatgpt.com))  

---

## 2. Configure Cloud Run for Testing

1. **Enable Developer Authentication**  
   In Cloud Run settings, allow your test harness (e.g., VM’s service account) to invoke the service.  ([Load testing best practices | Cloud Run Documentation](https://cloud.google.com/run/docs/about-load-testing?utm_source=chatgpt.com))  
2. **Set min instances = 1**  
   To avoid cold-start skew in results, configure at least one minimum instance in your Cloud Run service’s autoscaling settings.  ([Load testing best practices | Cloud Run Documentation](https://cloud.google.com/run/docs/about-load-testing?utm_source=chatgpt.com))  

---

## 3. Create a JMeter Test Plan

### 3.1 Test Plan Structure  
Your `.jmx` plan should include at minimum:  
- **Test Plan** root element  ([User's Manual: Elements of a Test Plan - Apache JMeter](https://jmeter.apache.org/usermanual/test_plan.html?utm_source=chatgpt.com))  
- **Thread Group** (defines VUs, ramp-up, and duration)  ([User's Manual: Elements of a Test Plan - Apache JMeter](https://jmeter.apache.org/usermanual/test_plan.html?utm_source=chatgpt.com))  
- **HTTP Request** Sampler (points to your Cloud Run URL)  ([User's Manual: Elements of a Test Plan - Apache JMeter](https://jmeter.apache.org/usermanual/test_plan.html?utm_source=chatgpt.com))  
- **Listener(s)** (e.g., Summary Report, Aggregate Report)  ([Apache JMeter - User's Manual](https://jmeter.apache.org/usermanual/index.html?utm_source=chatgpt.com))  
- (Optional) **Assertions** to validate response content  ([Apache JMeter - User's Manual](https://jmeter.apache.org/usermanual/index.html?utm_source=chatgpt.com))  

### 3.2 Example Thread Group Settings  
- **Number of Threads (users):** 50  
- **Ramp-Up Period (seconds):** 60  
- **Loop Count:** 20  
These settings spread 50 virtual users evenly over a minute, each sending 20 loops.  ([User's Manual: Elements of a Test Plan - Apache JMeter](https://jmeter.apache.org/usermanual/test_plan.html?utm_source=chatgpt.com))  

### 3.3 HTTP Request Sampler  
1. **Server Name or IP:** your-service.run.app  
2. **Protocol:** `https`  
3. **Path:** `/` (or specific endpoint)  ([User's Manual: Elements of a Test Plan - Apache JMeter](https://jmeter.apache.org/usermanual/test_plan.html?utm_source=chatgpt.com))  
4. (Optional) **Default HTTP Request** config for shared settings  ([Building a Web Test Plan - Apache JMeter - User's Manual](https://jmeter.apache.org/usermanual/build-web-test-plan.html?utm_source=chatgpt.com))  

### 3.4 Recording with HTTP(S) Test Script Recorder  
For complex flows, use JMeter’s built-in recorder:  
1. Add **HTTP(S) Test Script Recorder** under Test Plan.  
2. Configure your browser’s proxy to point at JMeter (default port 8888).  
3. Perform actions in the browser; JMeter captures them as HTTP samplers.  ([How to Record and Run Load Tests with JMeter in the Cloud ...](https://loadfocus.com/blog/2020/11/how-to-record-and-run-load-tests-with-jmeter-in-the-cloud-chrome-extension?utm_source=chatgpt.com))  

Save your test plan as `cloudrun-load-test.jmx`.

---

## 4. Run the Load Test

Execute in non-GUI mode to maximize performance:

```bash
~/jmeter/bin/jmeter \
  -n \
  -t cloudrun-load-test.jmx \
  -l results.jtl \
  -j jmeter.log
```
- `-n`: non-GUI mode  
- `-t`: path to test plan  
- `-l`: result file  
- `-j`: JMeter log file  ([Apache JMeter - User's Manual](https://jmeter.apache.org/usermanual/index.html?utm_source=chatgpt.com))  

---

## 5. Analyze Results

1. **View Summary Report**  
   Open `results.jtl` in GUI:  
   ```bash
   ~/jmeter/bin/jmeter -g results.jtl -o report/
   ```
   Generates an HTML dashboard in `report/`.  ([Apache JMeter - User's Manual](https://jmeter.apache.org/usermanual/index.html?utm_source=chatgpt.com))  
2. **Key metrics**  
   - **Throughput** (requests/sec)  
   - **Latency percentiles** (p50, p95, p99)  
   - **Error rate** (%)  
3. **Correlate with Cloud Run metrics**  
   In GCP Console → Cloud Run → Your service → Metrics, compare CPU, memory, and instance counts during the test.  ([Load testing best practices | Cloud Run Documentation](https://cloud.google.com/run/docs/about-load-testing?utm_source=chatgpt.com))  

---

## 6. Clean Up

After testing, revert Cloud Run settings if needed:
```bash
gcloud run services update SERVICE_NAME \
  --min-instances=0 \
  --platform=managed \
  --region=REGION
```  

---

## References

1. Cloud Run load-testing best practices  ([Load testing best practices | Cloud Run Documentation](https://cloud.google.com/run/docs/about-load-testing?utm_source=chatgpt.com))  
2. Apache JMeter™ overview  ([Apache JMeter - Apache JMeter™](https://jmeter.apache.org/?utm_source=chatgpt.com))  
3. Download Apache JMeter binaries  ([Download Apache JMeter](https://jmeter.apache.org/download_jmeter.cgi?utm_source=chatgpt.com))  
4. JMeter non-GUI mode details  ([Apache JMeter - User's Manual](https://jmeter.apache.org/usermanual/index.html?utm_source=chatgpt.com))  
5. Building a Test Plan in JMeter  ([User's Manual: Building a Test Plan - Apache JMeter](https://jmeter.apache.org/usermanual/build-test-plan.html?utm_source=chatgpt.com))  
6. Elements of a Test Plan  ([User's Manual: Elements of a Test Plan - Apache JMeter](https://jmeter.apache.org/usermanual/test_plan.html?utm_source=chatgpt.com))  
7. Building a Web Test Plan  ([Building a Web Test Plan - Apache JMeter - User's Manual](https://jmeter.apache.org/usermanual/build-web-test-plan.html?utm_source=chatgpt.com))  
8. Test Plan CLI execution & dashboard report  ([Apache JMeter - User's Manual](https://jmeter.apache.org/usermanual/index.html?utm_source=chatgpt.com))  
9. HTTP(S) Test Script Recorder usage  ([How to Record and Run Load Tests with JMeter in the Cloud ...](https://loadfocus.com/blog/2020/11/how-to-record-and-run-load-tests-with-jmeter-in-the-cloud-chrome-extension?utm_source=chatgpt.com))  
10. Thread Group configuration parameters  ([User's Manual: Elements of a Test Plan - Apache JMeter](https://jmeter.apache.org/usermanual/test_plan.html?utm_source=chatgpt.com))
