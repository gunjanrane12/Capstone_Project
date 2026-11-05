USE ROLE ACCOUNTADMIN;

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS INSURANCE_ALERT_EMAIL_INT
  TYPE = EMAIL
  ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('<littlegiant0212>@gmail.com');   -- add teammates, comma-separated

-- test: you should receive this within a minute
CALL SYSTEM$SEND_EMAIL(
  'INSURANCE_ALERT_EMAIL_INT',
  'littlegiant0212@gmail.com',
  'Insurance alerts - test',
  'If you can read this, threshold alerts will work.');


USE ROLE ACCOUNTADMIN;
USE DATABASE INSURANCEPOLICY_LIFECYCLE_DB;
CREATE SCHEMA IF NOT EXISTS MONITORING;
USE SCHEMA MONITORING;

-- Limits: change these with UPDATE, no code changes needed
CREATE OR REPLACE TABLE MONITORING.ALERT_THRESHOLDS (
    METRIC_NAME     STRING,
    DESCRIPTION     STRING,
    METRIC_SQL      STRING,          -- must return ONE number
    DETAIL_SQL      STRING,          -- optional: up to 10 rows to list in the email
    OPERATOR        STRING,          -- >, >=, <, <=
    THRESHOLD_VALUE NUMBER(20,2),
    SEVERITY        STRING,          -- HIGH / MEDIUM / LOW
    RECIPIENTS      STRING,          -- comma-separated verified emails
    COOLDOWN_HOURS  NUMBER DEFAULT 24,
    IS_ACTIVE       BOOLEAN DEFAULT TRUE,
    UPDATED_BY      STRING DEFAULT CURRENT_USER(),
    UPDATED_TS      TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Every alert fired (and every failed check) is logged here
CREATE OR REPLACE TABLE MONITORING.ALERT_HISTORY (
    ALERT_ID        NUMBER AUTOINCREMENT,
    METRIC_NAME     STRING,
    METRIC_VALUE    NUMBER(20,2),
    OPERATOR        STRING,
    THRESHOLD_VALUE NUMBER(20,2),
    SEVERITY        STRING,
    STATUS          STRING,          -- FIRED / METRIC_ERROR
    SUBJECT         STRING,
    EMAIL_SENT      BOOLEAN,
    ERROR_MESSAGE   STRING,
    ALERT_TS        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO MONITORING.ALERT_THRESHOLDS
  (METRIC_NAME, DESCRIPTION, METRIC_SQL, DETAIL_SQL, OPERATOR, THRESHOLD_VALUE, SEVERITY, RECIPIENTS)
VALUES
-- 1. High-risk claims (Snowpark score)
('HIGH_RISK_CLAIMS',
 'Number of claims scored HIGH risk',
 $$SELECT COUNT_IF(UPPER(RISK_CATEGORY) = 'HIGH')
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIM_RISK_SCORES$$,
 $$SELECT CLAIM_ID, REGION, CLAIM_TYPE, CLAIM_AMOUNT, TOTAL_RISK_SCORE
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIM_RISK_SCORES
   WHERE UPPER(RISK_CATEGORY) = 'HIGH' ORDER BY TOTAL_RISK_SCORE DESC LIMIT 10$$,
 '>', 20, 'HIGH', '<your_email>@ltimindtree.com'),

-- 2. Loss ratio proxy = net settlement / premium collected
('LOSS_RATIO_PCT',
 'Loss ratio proxy (%) across all regions',
 $$SELECT ROUND(100 * SUM(NET_SETTLEMENT_AMOUNT) / NULLIF(SUM(PREMIUM_COLLECTED), 0), 2)
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_KPI_SUMMARY$$,
 $$SELECT REGION,
          ROUND(100 * NET_SETTLEMENT_AMOUNT / NULLIF(PREMIUM_COLLECTED, 0), 1) AS LOSS_RATIO_PCT
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_KPI_SUMMARY
   ORDER BY LOSS_RATIO_PCT DESC NULLS LAST$$,
 '>', 70, 'HIGH', '<your_email>@ltimindtree.com'),

-- 3. Paid without approval: count
('PAID_WITHOUT_APPROVAL_COUNT',
 'Claims settled while Rejected or Under Review',
 $$SELECT COUNT(*)
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD
   WHERE SETTLEMENT_COUNT > 0 AND UPPER(CLAIM_STATUS) IN ('REJECTED', 'UNDER REVIEW')$$,
 $$SELECT CLAIM_ID, CLAIM_STATUS, REGION, NET_SETTLED
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD
   WHERE SETTLEMENT_COUNT > 0 AND UPPER(CLAIM_STATUS) IN ('REJECTED', 'UNDER REVIEW')
   ORDER BY NET_SETTLED DESC LIMIT 10$$,
 '>', 0, 'HIGH', '<your_email>@ltimindtree.com'),

-- 4. Paid without approval: rupee amount
('PAID_WITHOUT_APPROVAL_AMOUNT',
 'Net amount paid on Rejected / Under Review claims (INR)',
 $$SELECT COALESCE(SUM(NET_SETTLED), 0)
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD
   WHERE SETTLEMENT_COUNT > 0 AND UPPER(CLAIM_STATUS) IN ('REJECTED', 'UNDER REVIEW')$$,
 NULL,
 '>', 1000000, 'HIGH', '<your_email>@ltimindtree.com'),

-- 5. Fraud investigations open more than 30 days
('AGED_OPEN_INVESTIGATIONS',
 'Fraud investigations open for more than 30 days',
 $$SELECT COUNT_IF(INVESTIGATION_END_DATE IS NULL
                   AND DATEDIFF(day, INVESTIGATION_START_DATE, CURRENT_DATE()) > 30)
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_FRAUD_DASHBOARD$$,
 $$SELECT FRAUD_CASE_ID, CLAIM_ID, INVESTIGATOR_ID, INVESTIGATION_START_DATE,
          DATEDIFF(day, INVESTIGATION_START_DATE, CURRENT_DATE()) AS DAYS_OPEN
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_FRAUD_DASHBOARD
   WHERE INVESTIGATION_END_DATE IS NULL
   ORDER BY DAYS_OPEN DESC LIMIT 10$$,
 '>', 0, 'MEDIUM', '<your_email>@ltimindtree.com'),

-- 6. Single very large claim
('MAX_SINGLE_CLAIM_INR',
 'Largest single claim amount (INR)',
 $$SELECT MAX(CLAIM_AMOUNT)
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD$$,
 $$SELECT CLAIM_ID, POLICY_ID, CLAIM_TYPE, CLAIM_AMOUNT, CLAIM_STATUS
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD
   WHERE CLAIM_AMOUNT >= 10000000 ORDER BY CLAIM_AMOUNT DESC LIMIT 10$$,
 '>=', 10000000, 'MEDIUM', '<your_email>@ltimindtree.com');

SELECT METRIC_NAME, OPERATOR, THRESHOLD_VALUE, SEVERITY FROM MONITORING.ALERT_THRESHOLDS;

CREATE OR REPLACE PROCEDURE MONITORING.SP_CHECK_THRESHOLDS()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS OWNER
AS
$$
import operator

DB = "INSURANCEPOLICY_LIFECYCLE_DB.MONITORING"
INTEGRATION = "INSURANCE_ALERT_EMAIL_INT"
OPS = {">": operator.gt, ">=": operator.ge, "<": operator.lt, "<=": operator.le}


def log(session, name, value, op, limit, sev, status, subject, sent, err):
    session.sql(
        f"INSERT INTO {DB}.ALERT_HISTORY (METRIC_NAME, METRIC_VALUE, OPERATOR, THRESHOLD_VALUE, "
        f"SEVERITY, STATUS, SUBJECT, EMAIL_SENT, ERROR_MESSAGE) VALUES (?,?,?,?,?,?,?,?,?)",
        params=[name, value, op, limit, sev, status, subject, sent, err]).collect()


def details(session, detail_sql):
    if not detail_sql:
        return ""
    try:
        rows = session.sql(detail_sql).collect()[:10]
    except Exception as e:
        return f"\n(Could not load details: {str(e)[:200]})"
    if not rows:
        return ""
    lines = [", ".join(f"{k}={v}" for k, v in r.as_dict().items()) for r in rows]
    return "\n\nTop records:\n- " + "\n- ".join(lines)


def run(session):
    rules = session.sql(
        f"SELECT METRIC_NAME, DESCRIPTION, METRIC_SQL, DETAIL_SQL, OPERATOR, THRESHOLD_VALUE, "
        f"SEVERITY, RECIPIENTS, COALESCE(COOLDOWN_HOURS, 24) AS COOLDOWN_HOURS "
        f"FROM {DB}.ALERT_THRESHOLDS WHERE IS_ACTIVE").collect()

    fired = suppressed = errors = 0
    for r in rules:
        name, op, sev = r["METRIC_NAME"], r["OPERATOR"], r["SEVERITY"]
        limit = float(r["THRESHOLD_VALUE"])

        # 1. measure the metric
        try:
            raw = session.sql(r["METRIC_SQL"]).collect()[0][0]
        except Exception as e:
            errors += 1
            log(session, name, None, op, limit, sev, "METRIC_ERROR", None, False, str(e)[:1000])
            continue
        if raw is None or op not in OPS or not OPSfloat(raw), limit:
            continue                                          # within limit
        value = float(raw)

        # 2. cool-down: skip if already alerted recently and it has not got worse
        last = session.sql(
            f"SELECT METRIC_VALUE FROM {DB}.ALERT_HISTORY "
            f"WHERE METRIC_NAME = ? AND STATUS = 'FIRED' "
            f"AND ALERT_TS >= DATEADD(hour, -?, CURRENT_TIMESTAMP()) "
            f"ORDER BY ALERT_TS DESC LIMIT 1",
            params=[name, int(r["COOLDOWN_HOURS"])]).collect()
        if last:
            prev = float(last[0][0])
            worse = value > prev if op in (">", ">=") else value < prev
            if not worse:
                suppressed += 1
                continue

        # 3. send the email
        subject = f"[Insurance Alert][{sev}] {name} breached ({value:,.2f} {op} {limit:,.2f})"
        body = (f"{r['DESCRIPTION']}\n\n"
                f"Current value : {value:,.2f}\n"
                f"Limit         : {op} {limit:,.2f}\n"
                f"Severity      : {sev}\n"
                f"Database      : INSURANCEPOLICY_LIFECYCLE_DB"
                f"{details(session, r['DETAIL_SQL'])}\n\n"
                f"Open the Insurance Lifecycle Streamlit dashboard for full details.\n"
                f"Limits are managed in MONITORING.ALERT_THRESHOLDS.")
        sent, err = True, None
        try:
            session.call("SYSTEM$SEND_EMAIL", INTEGRATION, r["RECIPIENTS"], subject, body)
        except Exception as e:
            sent, err = False, str(e)[:1000]

        log(session, name, value, op, limit, sev, "FIRED", subject, sent, err)
        fired += 1

    return f"checked={len(rules)} fired={fired} suppressed={suppressed} metric_errors={errors}"
$$;

-- run it now
CALL MONITORING.SP_CHECK_THRESHOLDS();
SELECT * FROM MONITORING.ALERT_HISTORY ORDER BY ALERT_TS DESC;

CREATE OR REPLACE TASK MONITORING.T_CHECK_THRESHOLDS
  WAREHOUSE = IDMC_COMPUTE_WH
  SCHEDULE  = 'USING CRON 0 9-19 * * * Asia/Kolkata'      -- every hour, 09:00-19:00 IST
AS
  CALL MONITORING.SP_CHECK_THRESHOLDS();

ALTER TASK MONITORING.T_CHECK_THRESHOLDS RESUME;

-- run immediately for the demo
EXECUTE TASK MONITORING.T_CHECK_THRESHOLDS;

-- check it ran
SELECT NAME, STATE, SCHEDULED_TIME, COMPLETED_TIME, RETURN_VALUE, ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'T_CHECK_THRESHOLDS'))
ORDER BY SCHEDULED_TIME DESC LIMIT 5;

-- Data engineers manage the limits (no code change, fully audited via UPDATED_BY / UPDATED_TS)
GRANT USAGE ON SCHEMA INSURANCEPOLICY_LIFECYCLE_DB.MONITORING TO ROLE DATA_ENGINEER_ROLE;
GRANT SELECT, UPDATE ON TABLE MONITORING.ALERT_THRESHOLDS TO ROLE DATA_ENGINEER_ROLE;
GRANT SELECT ON TABLE MONITORING.ALERT_HISTORY TO ROLE DATA_ENGINEER_ROLE;

-- Dashboard / Fraud Manager read alerts through secure views
CREATE OR REPLACE SECURE VIEW SECURE_CONSUMPTION.VW_ALERT_HISTORY AS
SELECT ALERT_ID, METRIC_NAME, METRIC_VALUE, OPERATOR, THRESHOLD_VALUE, SEVERITY,
       STATUS, EMAIL_SENT, ALERT_TS AS ALERT_TIMESTAMP
FROM MONITORING.ALERT_HISTORY;

CREATE OR REPLACE SECURE VIEW SECURE_CONSUMPTION.VW_ALERT_THRESHOLDS AS
SELECT METRIC_NAME, DESCRIPTION, OPERATOR, THRESHOLD_VALUE, SEVERITY,
       COOLDOWN_HOURS, IS_ACTIVE, UPDATED_BY, UPDATED_TS AS UPDATED_TIMESTAMP
FROM MONITORING.ALERT_THRESHOLDS;

GRANT SELECT ON VIEW SECURE_CONSUMPTION.VW_ALERT_HISTORY    TO ROLE STREAMLIT_APP_ROLE;
GRANT SELECT ON VIEW SECURE_CONSUMPTION.VW_ALERT_THRESHOLDS TO ROLE STREAMLIT_APP_ROLE;
GRANT SELECT ON VIEW SECURE_CONSUMPTION.VW_ALERT_HISTORY    TO ROLE FRAUD_MANAGER_ROLE;
GRANT SELECT ON VIEW SECURE_CONSUMPTION.VW_ALERT_THRESHOLDS TO ROLE FRAUD_MANAGER_ROLE;

-- Example: change a limit live during the demo
UPDATE MONITORING.ALERT_THRESHOLDS
   SET THRESHOLD_VALUE = 15, UPDATED_BY = CURRENT_USER(), UPDATED_TS = CURRENT_TIMESTAMP()
 WHERE METRIC_NAME = 'HIGH_RISK_CLAIMS';

# ===========================================================================
# 5. ALERTS - threshold breaches (Fraud Manager / Data Engineer)
# ===========================================================================
def alerts():
    hist = load("VW_ALERT_HISTORY")
    thr = load("VW_ALERT_THRESHOLDS")
    fired = hist[hist["STATUS"] == "FIRED"] if not hist.empty else hist
    week = pd.Timestamp(date.today()) - pd.Timedelta(days=7)
    recent = fired[fired["ALERT_TIMESTAMP"] >= week] if not fired.empty else fired

    k = st.columns(4)
    k[0].metric("Alerts (last 7 days)", f"{len(recent):,}")
    k[1].metric("HIGH severity (7 days)", int((recent["SEVERITY"] == "HIGH").sum()) if len(recent) else 0)
    k[2].metric("Emails failed", int((~fired["EMAIL_SENT"].astype(bool)).sum()) if len(fired) else 0)
    k[3].metric("Active rules", int(thr["IS_ACTIVE"].astype(bool).sum()) if len(thr) else 0)

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Alerts by metric")
        bar(fired.groupby("METRIC_NAME")["ALERT_ID"].count() if len(fired) else None)
    with c2:
        st.subheader("Alerts per day")
        line(monthly_count(fired, "ALERT_TIMESTAMP", "ALERT_ID") if len(fired) else None)

    st.subheader("Latest alerts")
    show(hist.sort_values("ALERT_TIMESTAMP", ascending=False).head(50))
    st.subheader("Current limits")
    show(thr)
    st.caption("Limits are changed by Data Engineers in MONITORING.ALERT_THRESHOLDS - no code change needed.")


ICON = {"KPI": "📊 KPI Scorecard", "Underwriting": "📑 Underwriting", "Claims": "📋 Claims",
        "Fraud": "🚨 Fraud", "Network": "🕸️ Network", "Alerts": "🔔 Alerts"}
RENDER = {"KPI": kpi_scorecard, "Underwriting": underwriting, "Claims": claims,
          "Fraud": fraud, "Network": fraud_network, "Alerts": alerts}
pages = ["KPI"] + allowed + (["Network", "Alerts"] if "Fraud" in allowed else [])
