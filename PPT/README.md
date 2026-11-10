# Insurance Policy Lifecycle, Claims, Fraud & Risk Analytics Platform

**Snowflake Capstone Project · Group 8**

An end-to-end insurance analytics platform. It takes seven raw insurance datasets from AWS S3, cleanses them with Informatica IDMC, and organises them in Snowflake as a Bronze → Silver → Gold medallion architecture. Role-based Streamlit dashboards, Snowpark fraud scoring, Cortex Analyst, threshold email alerts and a Fraud Network view sit on top.

![Snowflake](https://img.shields.io/badge/Snowflake-29B5E8?logo=snowflake&logoColor=white)
![Informatica IDMC](https://img.shields.io/badge/Informatica-IDMC-FF4D00)
![AWS S3](https://img.shields.io/badge/AWS-S3-569A31?logo=amazons3&logoColor=white)
![Python](https://img.shields.io/badge/Snowpark-Python-3776AB?logo=python&logoColor=white)
![Streamlit](https://img.shields.io/badge/Streamlit-FF4B4B?logo=streamlit&logoColor=white)

---

## Table of Contents
1. [Business Problem](#business-problem)
2. [Key Features](#key-features)
3. [Architecture](#architecture)
4. [Tech Stack](#tech-stack)
5. [Source Datasets](#source-datasets)
6. [Repository Structure](#repository-structure)
7. [Prerequisites](#prerequisites)
8. [Setup and Run Order](#setup-and-run-order)
9. [Data Quality Rules](#data-quality-rules)
10. [Data Model](#data-model)
11. [Security and Roles](#security-and-roles)
12. [Streamlit Dashboard](#streamlit-dashboard)
13. [Business KPIs](#business-kpis)
14. [Fraud Risk Scoring](#fraud-risk-scoring)
15. [USPs](#usps)
16. [Validation Results](#validation-results)
17. [Business Insights](#business-insights)
18. [Limitations and Future Scope](#limitations-and-future-scope)
19. [Team](#team)

---

## Business Problem
Seven separate business processes produce insurance data: customer registration, product management, policy issuance, premium collection, claims, settlements and fraud investigation. Because the data is disconnected, it contains invalid records, duplicates, unreconciled settlements and KPIs that different analysts calculate differently. This platform turns it into **one governed, traceable and secure source of insurance analytics**.

## Key Features
- **Medallion architecture:** Bronze (raw), Silver (typed and validated) and Gold (dimensions, facts and marts)
- **Data quality at entry:** IDMC profiling, cleansing, deduplication and VALID / ERROR / DUPLICATE routing
- **21 audit tables:** every rejected or flagged record is kept with a reason
- **Event-driven claims ingestion:** IDMC File Listener → Taskflow → Bronze
- **Incremental processing:** Snowflake Stream + Task + idempotent **SCD Type 2** on claims
- **Explainable fraud scoring:** a Snowpark Python procedure scores each claim LOW, MEDIUM or HIGH
- **RBAC:** 4 roles, 5 users, 11 secure views and masked customer contact details
- **Role-based Streamlit app** with a KPI Scorecard, Underwriting, Claims, Fraud, Cortex, Network and Alerts tabs
- **Cortex Analyst:** natural-language questions answered from the Gold marts
- **USPs:** threshold email alerts and Fraud Network analysis

## Architecture
```
Source CSVs (7) ──► AWS S3 ──► Informatica IDMC ──► Snowflake (INSURANCEPOLICY_LIFECYCLE_DB)
                     │          Profiling            ├── BRONZE   raw text + load metadata
                     │          Cleansing / Dedup    ├── AUDIT    error / duplicate / warning (21)
                     │          DQ Router            ├── SILVER   typed, deduped, RI-checked, CLAIMS_SCD2
                     │          File Listener        ├── GOLD     4 dims · 4 facts · 4 marts
                     │          + Taskflow           ├── SECURE_CONSUMPTION  11 role-based secure views
   claims folder ────┘                               └── Streamlit · Cortex Analyst · Email Alerts · Fraud Network
```
**Incremental claims path:** New file in S3 → File Listener `FL_S3_CLAIMS` → Taskflow `CLAIMS_AUTO_INGESTION` → `MT_CLAIMS_LOAD` → `BRONZE.CLAIMS` → Stream → Task → SCD2 procedure → `SILVER.CLAIMS_SCD2` → Gold

## Tech Stack
| Technology | Purpose |
|---|---|
| AWS S3 | Landing zone for source files and the claims incremental folder |
| Informatica IDMC | Profiling, cleansing, DQ routing, File Listener, Taskflow |
| Snowflake | Storage layers, Streams, Tasks, secure views, RBAC, Time Travel |
| Snowpark Python | Fraud risk scoring and KPI verification |
| Streamlit in Snowflake | Role-based dashboards |
| Cortex Analyst | Natural-language querying over a semantic model |
| Snowflake Email Integration | Threshold-based alert emails |

**Warehouse:** `IDMC_COMPUTE_WH` · **Database:** `INSURANCEPOLICY_LIFECYCLE_DB`

## Source Datasets
| Dataset | Records | Business key |
|---|---:|---|
| customers.csv | 800 | customer_id |
| insurance_products.csv | 80 | product_id |
| policies.csv | 1,500 | policy_id |
| premium_payments.csv | 1,400 | payment_id |
| claims.csv | 1,200 | claim_id |
| claim_settlements.csv | 700 | settlement_id |
| fraud_cases.csv | 400 | fraud_case_id |
| **Total** | **6,080** | |

## Repository Structure
```
insurance-analytics-platform/
├── README.md
├── data/                         # 7 source CSV files
├── idmc/                         # IDMC mapping / taskflow exports and parameter files
├── sql/
│   ├── 01_bronze.sql             # Bronze raw tables
│   ├── 02_audit.sql              # Error / duplicate / warning tables
│   ├── 03_silver.sql             # Silver typed tables
│   ├── 04_bronze_to_silver.sql   # Bronze → Silver loads and dedup
│   ├── 05_claims_scd2.sql        # Stream, SCD2 procedure and task
│   ├── 06_gold.sql               # Dimensions, facts, marts and fraud-risk task
│   ├── 07_security_rbac.sql      # Roles, users and grants
│   ├── 08_secure_consumption.sql # Secure views, KPI views and app grants
│   ├── 09_fraud_network.sql      # Fraud Network feature
│   ├── 10_email_alerts.sql       # ALERT_THRESHOLDS, ALERT_HISTORY and alert task
│   └── 11_cortex.sql             # Cortex Analyst setup
├── cortex/
│   └── semantic_model.yaml       # Semantic model for Cortex Analyst
├── streamlit/
│   └── streamlit_app.py          # Role-based dashboard
└── docs/
    ├── Final_Project_Report.docx
    └── Final_Presentation.pptx
```
> Change the file names to match your repository if they differ.

## Prerequisites
- A Snowflake account with the `ACCOUNTADMIN` role, or equivalent privileges
- An Informatica IDMC org with a Secure Agent or Cloud runtime
- An AWS S3 bucket, with access keys or an IAM role for IDMC
- Streamlit in Snowflake and Cortex Analyst enabled in your region
- A Snowflake notification integration for email alerts

## Setup and Run Order
1. **Upload the data:** put the 7 CSVs in the S3 `raw/` folder and create a `claims/` folder for incremental files.
2. **Create the IDMC connections:** an AWS S3 source and a Snowflake target (`IDMC_COMPUTE_WH`). Test both.
3. **Create the Snowflake objects:** run `01_bronze.sql` and `02_audit.sql`.
4. **Run IDMC profiling:** S3 → S3 only, with no Snowflake load.
5. **Run the IDMC cleansing mapping tasks:** S3 → Bronze (VALID rows) and Audit (ERROR / DUPLICATE / WARNING rows).
6. **Build Silver:** run `03_silver.sql` and then `04_bronze_to_silver.sql`.
7. **Set up SCD2:** run `05_claims_scd2.sql`, then resume the task.
8. **Build Gold:** run `06_gold.sql`, which includes the fraud-scoring task.
9. **Set up security:** run `07_security_rbac.sql` and `08_secure_consumption.sql`.
10. **Add the USPs:** run `09_fraud_network.sql` and `10_email_alerts.sql`.
11. **Set up Cortex:** upload `semantic_model.yaml` to a stage and run `11_cortex.sql`.
12. **Deploy Streamlit:** create a Streamlit app in Snowflake from `streamlit_app.py` and grant usage to the roles.
13. **Turn on event-driven loading:** publish the File Listener `FL_S3_CLAIMS` and the taskflow `CLAIMS_AUTO_INGESTION`.

```sql
-- Resume the tasks after deployment
ALTER TASK <claims_scd2_task>   RESUME;
ALTER TASK <fraud_scoring_task> RESUME;
ALTER TASK <alert_task>         RESUME;
```

## Data Quality Rules
| Dataset | Rule | Handling |
|---|---|---|
| Customers | customer_id is mandatory | Reject |
| Policies | Expiry date must be after the start date | Reject |
| Premium Payments | Amount > 0 and reference number present | Reject |
| Premium Payments | Mixed date formats | Standardise and keep |
| Claims | Amount is plausible and loss date is within the policy period | Reject or flag outlier |
| Claim Settlements | Net = gross − deductible − recovery | Reject |
| Fraud Cases | Fraud score is between 0 and 100 | Reject |
| All | Business key is unique | Route duplicates to AUDIT |

**Profiling found** 8 nulls, 3 duplicates, 3 business anomalies, 2 outliers and 4 varied date formats.

## Data Model
- **Dimensions:** `VW_DIM_CUSTOMER`, `VW_DIM_INSURANCE_PRODUCT`, `VW_DIM_POLICY`, `VW_DIM_DATE`
- **Facts:** `VW_FACT_PREMIUM_PAYMENT`, `VW_FACT_CLAIM` (current SCD2 version), `VW_FACT_CLAIM_SETTLEMENT`, `VW_FACT_FRAUD_CASE`
- **Marts:** `MART_POLICY_PORTFOLIO`, `MART_CLAIMS_PERFORMANCE`, `MART_SETTLEMENT_RECONCILIATION`, `MART_FRAUD_RISK`

Facts join only to dimensions, and each fact is aggregated before it is joined. This prevents double counting.

## Security and Roles
| Role | Access |
|---|---|
| INSURANCE_ANALYST | Policy and premium data; masked customer view |
| CLAIMS_ANALYST | Claims and settlements; masked customer view |
| FRAUD_MANAGER | Fraud risk, scores and Fraud Network |
| DATA_ENGINEER | Bronze, Silver and Audit |

Business users read only from `SECURE_CONSUMPTION`. Email, phone and address are masked.

## Streamlit Dashboard
| Tab | Who sees it |
|---|---|
| KPI Scorecard | All roles (aggregated, no personal data) |
| Underwriting | Insurance Analyst |
| Claims | Claims Analyst |
| Fraud | Fraud Manager |
| Ask Cortex | Business users |
| Network | Fraud Manager |
| Alerts | Authorised roles |

Users who aren't mapped to a role see **Access denied**.

## Business KPIs
| KPI | Definition |
|---|---|
| Active policies / sum insured | COUNT and SUM where status = Active |
| Premium collected | SUM(payment_amount) where status = Paid |
| Claim frequency | Claims ÷ policies × 100 |
| Average claim | AVG(claim_amount) over current versions |
| Approval ratio | Approved ÷ decided claims × 100 |
| Settlement turnaround | AVG(settlement date − registration date) |
| Net settlement | SUM(net_settlement_amount) |
| Loss ratio proxy | Net settlement ÷ premium collected × 100 |
| Open investigations | Count of cases not yet closed |
| Confirmed fraud rate | Confirmed ÷ closed investigations × 100 |
| High-risk claims | Count where risk_category = HIGH |

## Fraud Risk Scoring
| Component | Points |
|---|---|
| Claim amount | >500K = 30 · >100K = 20 · >50K = 10 |
| Customer risk | High / Very High = 25 · Medium = 15 |
| Policy risk band | High / Very High = 20 · Medium = 10 |
| Fraud history | Score ≥70 = 25 · ≥40 = 15 |
| **Category** | ≥70 HIGH · ≥40 MEDIUM · otherwise LOW (capped at 100) |

## USPs
**1. Event-driven File Listener.** When a new claims file lands in S3, it automatically triggers the IDMC taskflow, which sends a success or failure email. Nobody has to press Run.

**2. Threshold Email Alerts.** An hourly task compares the KPIs with the limits in `ALERT_THRESHOLDS`. Breaches are logged in `ALERT_HISTORY` and emailed. The same alert is suppressed for 24 hours unless the value gets worse. To change a limit, run a single `UPDATE`.

**3. Fraud Network.** Customers are linked when they share a phone, email, address, nominee, agent or assessor. A customer is HIGH risk with links to 2 or more confirmed fraudsters, and MEDIUM with a link to 1. Groups larger than 10 are excluded to avoid false links.

## Validation Results
| Check | Result |
|---|---|
| Source vs Bronze counts | Matched (6,080) |
| Referential integrity (9 relationships) | 0 orphans |
| Gold KPIs vs independent Snowpark calculation | Reconciled |
| SCD2 replay of the same file | 0 new versions (idempotent) |
| Role and masking tests | Behaved as designed |
| Dashboard vs Snowflake | MATCH |

## Business Insights
- **344 claims** were paid while their status was Rejected or Under Review, totalling **₹82,150,406.67**.
- The **loss ratio proxy is 879.67%**: settlements far exceed the premium collected.
- **86 claims** were scored HIGH risk.
- **304 investigations** have been open for more than 30 days.

## Limitations and Future Scope
- The premium schedule is outside the seven-dataset scope.
- Fraud scoring is rule-based; ML models could be added later.
- Gold layers are views; dynamic tables may be needed at scale.
- The masking uses static views; dynamic masking and row access policies are recommended.

## Team
**Group 8.** Every member built IDMC cleansing and validation mappings, with the datasets split across the team.

| Member | Contributions |
|---|---|
| **Gunjan Rane** (Team Lead) | IDMC Taskflow, File Listeners, SCD Type 2 design and procedure, Streamlit code, Fraud Network USP |
| **Simoni Das** | RBAC, security, SECURE_CONSUMPTION schema, Email Alert USP, PPT presentation |
| **Ayush Wankhede** | Gold architecture, Streamlit enhancement, Cortex implementation in Streamlit, incremental load validation |
| **Sai Bhavika** | Snowpark fraud risk scoring procedure, KPIs, load validation, testing, documentation |
| **Sujitha C** | Silver architecture, Streams and Tasks over procedures, pipeline testing, documentation |

---
*Snowflake Capstone Project. Built in a 5-day sprint, with all 26 planned tasks completed.*
