CREATE NOTIFICATION INTEGRATION IF NOT EXISTS INSURANCE_ALERT_EMAIL_INT
  TYPE = EMAIL
  ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('littlegiant0212@gmail.com');   -- add teammates, comma-separated

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
 '>', 20, 'HIGH', 'littlegiant0212@gmail.com'),

-- 2. Loss ratio proxy = net settlement / premium collected
('LOSS_RATIO_PCT',
 'Loss ratio proxy (%) across all regions',
 $$SELECT ROUND(100 * SUM(NET_SETTLEMENT_AMOUNT) / NULLIF(SUM(PREMIUM_COLLECTED), 0), 2)
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_KPI_SUMMARY$$,
 $$SELECT REGION,
          ROUND(100 * NET_SETTLEMENT_AMOUNT / NULLIF(PREMIUM_COLLECTED, 0), 1) AS LOSS_RATIO_PCT
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_KPI_SUMMARY
   ORDER BY LOSS_RATIO_PCT DESC NULLS LAST$$,
 '>', 70, 'HIGH', 'littlegiant0212@gmail.com'),

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
 '>', 0, 'HIGH', 'littlegiant0212@gmail.com'),

-- 4. Paid without approval: rupee amount
('PAID_WITHOUT_APPROVAL_AMOUNT',
 'Net amount paid on Rejected / Under Review claims (INR)',
 $$SELECT COALESCE(SUM(NET_SETTLED), 0)
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD
   WHERE SETTLEMENT_COUNT > 0 AND UPPER(CLAIM_STATUS) IN ('REJECTED', 'UNDER REVIEW')$$,
 NULL,
 '>', 1000000, 'HIGH', 'littlegiant0212@gmail.com'),

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
 '>', 0, 'MEDIUM', 'littlegiant0212@gmail.com'),

-- 6. Single very large claim
('MAX_SINGLE_CLAIM_INR',
 'Largest single claim amount (INR)',
 $$SELECT MAX(CLAIM_AMOUNT)
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD$$,
 $$SELECT CLAIM_ID, POLICY_ID, CLAIM_TYPE, CLAIM_AMOUNT, CLAIM_STATUS
   FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD
   WHERE CLAIM_AMOUNT >= 10000000 ORDER BY CLAIM_AMOUNT DESC LIMIT 10$$,
 '>=', 10000000, 'MEDIUM', 'littlegiant0212@gmail.com');

SELECT METRIC_NAME, OPERATOR, THRESHOLD_VALUE, SEVERITY FROM MONITORING.ALERT_THRESHOLDS;

CREATE OR REPLACE PROCEDURE INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.SP_CHECK_THRESHOLDS()
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


def fmt(x):
    x = float(x)
    return "{:,.0f}".format(x) if x.is_integer() else "{:,.2f}".format(x)


def is_breached(op, value, limit):
    compare = OPS.get(op)
    if compare is None:
        return False
    return compare(value, limit)


def sql_text(s):
    return "'" + str(s).replace("\\", "\\\\").replace("'", "''") + "'"


def log(session, name, value, op, limit, sev, status, subject, sent, err):
    session.sql(
        "INSERT INTO " + DB + ".ALERT_HISTORY (METRIC_NAME, METRIC_VALUE, OPERATOR, THRESHOLD_VALUE, "
        "SEVERITY, STATUS, SUBJECT, EMAIL_SENT, ERROR_MESSAGE) VALUES (?,?,?,?,?,?,?,?,?)",
        params=[name, value, op, limit, sev, status, subject, sent, err]).collect()


def details(session, detail_sql):
    if not detail_sql:
        return ""
    try:
        rows = session.sql(detail_sql).collect()
    except Exception as e:
        return "\n(Could not load details: " + str(e)[:200] + ")"
    rows = rows[:10]
    if not rows:
        return ""
    lines = []
    for row in rows:
        d = row.as_dict()
        lines.append(", ".join(str(k) + "=" + str(v) for k, v in d.items()))
    return "\n\nTop records:\n- " + "\n- ".join(lines)


def run(session):
    rules = session.sql(
        "SELECT METRIC_NAME, DESCRIPTION, METRIC_SQL, DETAIL_SQL, OPERATOR, THRESHOLD_VALUE, "
        "SEVERITY, RECIPIENTS, COALESCE(COOLDOWN_HOURS, 24) AS COOLDOWN_HOURS "
        "FROM " + DB + ".ALERT_THRESHOLDS WHERE IS_ACTIVE").collect()

    fired = 0
    suppressed = 0
    errors = 0
    for rule in rules:
        name = rule["METRIC_NAME"]
        op = rule["OPERATOR"]
        sev = rule["SEVERITY"]
        limit = float(rule["THRESHOLD_VALUE"])

        try:
            raw = session.sql(rule["METRIC_SQL"]).collect()[0][0]
        except Exception as e:
            errors += 1
            log(session, name, None, op, limit, sev, "METRIC_ERROR", None, False, str(e)[:1000])
            continue
        if raw is None:
            continue
        value = float(raw)
        if not is_breached(op, value, limit):
            continue

        last = session.sql(
            "SELECT METRIC_VALUE FROM " + DB + ".ALERT_HISTORY "
            "WHERE METRIC_NAME = ? AND STATUS = 'FIRED' "
            "AND ALERT_TS >= DATEADD(hour, -1 * ?, CURRENT_TIMESTAMP()) "
            "ORDER BY ALERT_TS DESC LIMIT 1",
            params=[name, int(rule["COOLDOWN_HOURS"])]).collect()
        if last and last[0][0] is not None:
            prev = float(last[0][0])
            worse = value > prev if op in (">", ">=") else value < prev
            if not worse:
                suppressed += 1
                continue

        subject = ("[Insurance Alert][" + sev + "] " + name + " breached ("
                   + fmt(value) + " " + op + " " + fmt(limit) + ")")
        body = (str(rule["DESCRIPTION"]) + "\n\n"
                + "Current value : " + fmt(value) + "\n"
                + "Limit         : " + op + " " + fmt(limit) + "\n"
                + "Severity      : " + sev + "\n"
                + "Database      : INSURANCEPOLICY_LIFECYCLE_DB"
                + details(session, rule["DETAIL_SQL"]) + "\n\n"
                + "Open the Insurance Lifecycle Streamlit dashboard for full details.\n"
                + "Limits are managed in MONITORING.ALERT_THRESHOLDS.")
        sent = True
        err = None
        try:
            session.sql("CALL SYSTEM$SEND_EMAIL(" + sql_text(INTEGRATION) + ", "
                        + sql_text(rule["RECIPIENTS"]) + ", " + sql_text(subject) + ", "
                        + sql_text(body) + ")").collect()
        except Exception as e:
            sent = False
            err = str(e)[:1000]

        log(session, name, value, op, limit, sev, "FIRED", subject, sent, err)
        fired += 1

    return ("checked=" + str(len(rules)) + " fired=" + str(fired)
            + " suppressed=" + str(suppressed) + " metric_errors=" + str(errors))
$$;

CREATE OR REPLACE TASK INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.T_CHECK_THRESHOLDS
  WAREHOUSE = IDMC_COMPUTE_WH
  SCHEDULE  = 'USING CRON 0 9-19 * * * Asia/Kolkata'
AS
  CALL INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.SP_CHECK_THRESHOLDS();

ALTER TASK INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.T_CHECK_THRESHOLDS RESUME;

-- secure views of the alert tables for the dashboard
CREATE OR REPLACE SECURE VIEW INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_ALERT_HISTORY AS
SELECT ALERT_ID, METRIC_NAME, METRIC_VALUE, OPERATOR, THRESHOLD_VALUE, SEVERITY,
       STATUS, EMAIL_SENT, ALERT_TS AS ALERT_TIMESTAMP
FROM INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_HISTORY;

CREATE OR REPLACE SECURE VIEW INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_ALERT_THRESHOLDS AS
SELECT METRIC_NAME, DESCRIPTION, OPERATOR, THRESHOLD_VALUE, SEVERITY,
       COOLDOWN_HOURS, IS_ACTIVE, UPDATED_BY, UPDATED_TS AS UPDATED_TIMESTAMP
FROM INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_THRESHOLDS;
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
