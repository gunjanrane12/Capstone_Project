/* =====================================================================================
   INSURANCE POLICY LIFECYCLE - EMAIL THRESHOLD ALERTS ADD-ON (SQL + STREAMLIT, ALL IN ONE)
   -------------------------------------------------------------------------------------
   Adds: email integration, alert limits table, alert history, checking procedure,
         hourly task, secure views, grants, and redeploys the Streamlit app with the
         "Alerts" tab (Fraud Manager / Data Engineer users).

   HOW TO USE
   1. Find & replace in this whole script:
        <YOUR_SNOWFLAKE_USER> -> your Snowflake user name
        <YOUR_EMAIL>          -> your VERIFIED Snowflake email
                                 (Snowsight -> your name -> Settings -> Profile -> Email -> Verify)
   2. Paste into a Snowsight worksheet -> Run All.

   NEEDS (created earlier by the main script)
   - SECURE_CONSUMPTION views: VW_CLAIM_RISK_SCORES, VW_KPI_SUMMARY, VW_CLAIMS_DASHBOARD,
     VW_FRAUD_DASHBOARD (used by the alert queries), and the dashboard views used by the app
   - Role STREAMLIT_APP_ROLE, warehouse IDMC_COMPUTE_WH
   Safe to re-run.
   ===================================================================================== */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDMC_COMPUTE_WH;
USE DATABASE INSURANCEPOLICY_LIFECYCLE_DB;
CREATE SCHEMA IF NOT EXISTS INSURANCEPOLICY_LIFECYCLE_DB.MONITORING;
CREATE SCHEMA IF NOT EXISTS INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION;

-- app owner role (no-op if it already exists)
USE ROLE SECURITYADMIN;
CREATE ROLE IF NOT EXISTS STREAMLIT_APP_ROLE;
GRANT ROLE STREAMLIT_APP_ROLE TO ROLE SYSADMIN;
GRANT ROLE STREAMLIT_APP_ROLE TO USER <YOUR_SNOWFLAKE_USER>;
USE ROLE ACCOUNTADMIN;

/* =====================================================================================
   1. EMAIL INTEGRATION
      <YOUR_EMAIL> must be VERIFIED: Snowsight -> your name -> Settings -> Profile -> Email
   ===================================================================================== */
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS INSURANCE_ALERT_EMAIL_INT
  TYPE = EMAIL
  ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('<YOUR_EMAIL>');


/* =====================================================================================
   2. ALERT TABLES + LIMITS (edit limits with UPDATE - no code change)
   ===================================================================================== */
CREATE TABLE IF NOT EXISTS INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_THRESHOLDS (
    METRIC_NAME     STRING,
    DESCRIPTION     STRING,
    METRIC_SQL      STRING,
    DETAIL_SQL      STRING,
    OPERATOR        STRING,
    THRESHOLD_VALUE NUMBER(20,2),
    SEVERITY        STRING,
    RECIPIENTS      STRING,
    COOLDOWN_HOURS  NUMBER DEFAULT 24,
    IS_ACTIVE       BOOLEAN DEFAULT TRUE,
    UPDATED_BY      STRING DEFAULT CURRENT_USER(),
    UPDATED_TS      TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_HISTORY (
    ALERT_ID        NUMBER AUTOINCREMENT,
    METRIC_NAME     STRING,
    METRIC_VALUE    NUMBER(20,2),
    OPERATOR        STRING,
    THRESHOLD_VALUE NUMBER(20,2),
    SEVERITY        STRING,
    STATUS          STRING,
    SUBJECT         STRING,
    EMAIL_SENT      BOOLEAN,
    ERROR_MESSAGE   STRING,
    ALERT_TS        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- re-runnable: clears and reloads the default limits (re-apply any limits you changed)
DELETE FROM INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_THRESHOLDS;
INSERT INTO INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_THRESHOLDS
  (METRIC_NAME, DESCRIPTION, METRIC_SQL, DETAIL_SQL, OPERATOR, THRESHOLD_VALUE, SEVERITY, RECIPIENTS)
VALUES
('HIGH_RISK_CLAIMS', 'Number of claims scored HIGH risk',
 'SELECT COUNT_IF(UPPER(RISK_CATEGORY) = ''HIGH'') FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIM_RISK_SCORES',
 'SELECT CLAIM_ID, REGION, CLAIM_TYPE, CLAIM_AMOUNT, TOTAL_RISK_SCORE FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIM_RISK_SCORES WHERE UPPER(RISK_CATEGORY) = ''HIGH'' ORDER BY TOTAL_RISK_SCORE DESC LIMIT 10',
 '>', 20, 'HIGH', '<YOUR_EMAIL>'),
('LOSS_RATIO_PCT', 'Loss ratio proxy (%) across all regions',
 'SELECT ROUND(100 * SUM(NET_SETTLEMENT_AMOUNT) / NULLIF(SUM(PREMIUM_COLLECTED), 0), 2) FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_KPI_SUMMARY',
 'SELECT REGION, ROUND(100 * NET_SETTLEMENT_AMOUNT / NULLIF(PREMIUM_COLLECTED, 0), 1) AS LOSS_RATIO_PCT FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_KPI_SUMMARY ORDER BY LOSS_RATIO_PCT DESC NULLS LAST',
 '>', 70, 'HIGH', '<YOUR_EMAIL>'),
('PAID_WITHOUT_APPROVAL_COUNT', 'Claims settled while Rejected or Under Review',
 'SELECT COUNT(*) FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD WHERE SETTLEMENT_COUNT > 0 AND UPPER(CLAIM_STATUS) IN (''REJECTED'', ''UNDER REVIEW'')',
 'SELECT CLAIM_ID, CLAIM_STATUS, REGION, NET_SETTLED FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD WHERE SETTLEMENT_COUNT > 0 AND UPPER(CLAIM_STATUS) IN (''REJECTED'', ''UNDER REVIEW'') ORDER BY NET_SETTLED DESC LIMIT 10',
 '>', 0, 'HIGH', '<YOUR_EMAIL>'),
('PAID_WITHOUT_APPROVAL_AMOUNT', 'Net amount paid on Rejected / Under Review claims (INR)',
 'SELECT COALESCE(SUM(NET_SETTLED), 0) FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD WHERE SETTLEMENT_COUNT > 0 AND UPPER(CLAIM_STATUS) IN (''REJECTED'', ''UNDER REVIEW'')',
 NULL,
 '>', 1000000, 'HIGH', '<YOUR_EMAIL>'),
('AGED_OPEN_INVESTIGATIONS', 'Fraud investigations open for more than 30 days',
 'SELECT COUNT_IF(INVESTIGATION_END_DATE IS NULL AND DATEDIFF(day, INVESTIGATION_START_DATE, CURRENT_DATE()) > 30) FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_FRAUD_DASHBOARD',
 'SELECT FRAUD_CASE_ID, CLAIM_ID, INVESTIGATOR_ID, INVESTIGATION_START_DATE, DATEDIFF(day, INVESTIGATION_START_DATE, CURRENT_DATE()) AS DAYS_OPEN FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_FRAUD_DASHBOARD WHERE INVESTIGATION_END_DATE IS NULL ORDER BY DAYS_OPEN DESC LIMIT 10',
 '>', 0, 'MEDIUM', '<YOUR_EMAIL>'),
('MAX_SINGLE_CLAIM_INR', 'Largest single claim amount (INR)',
 'SELECT MAX(CLAIM_AMOUNT) FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD',
 'SELECT CLAIM_ID, POLICY_ID, CLAIM_TYPE, CLAIM_AMOUNT, CLAIM_STATUS FROM INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_CLAIMS_DASHBOARD WHERE CLAIM_AMOUNT >= 10000000 ORDER BY CLAIM_AMOUNT DESC LIMIT 10',
 '>=', 10000000, 'MEDIUM', '<YOUR_EMAIL>');


/* =====================================================================================
   3. ALERT PROCEDURE + HOURLY TASK
   ===================================================================================== */
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


/* =====================================================================================
   4. ALERT GRANTS
   ===================================================================================== */
USE ROLE ACCOUNTADMIN;
GRANT USAGE ON WAREHOUSE IDMC_COMPUTE_WH TO ROLE STREAMLIT_APP_ROLE;
GRANT USAGE ON DATABASE INSURANCEPOLICY_LIFECYCLE_DB TO ROLE STREAMLIT_APP_ROLE;
GRANT USAGE ON SCHEMA INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION TO ROLE STREAMLIT_APP_ROLE;
GRANT CREATE STREAMLIT, CREATE STAGE
      ON SCHEMA INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION TO ROLE STREAMLIT_APP_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION TO ROLE STREAMLIT_APP_ROLE;

GRANT USAGE ON SCHEMA INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION TO ROLE FRAUD_MANAGER_ROLE;
GRANT SELECT ON VIEW INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_ALERT_HISTORY    TO ROLE FRAUD_MANAGER_ROLE;
GRANT SELECT ON VIEW INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.VW_ALERT_THRESHOLDS TO ROLE FRAUD_MANAGER_ROLE;

-- data engineers manage the limits (audited by UPDATED_BY / UPDATED_TS)
GRANT USAGE ON SCHEMA INSURANCEPOLICY_LIFECYCLE_DB.MONITORING TO ROLE DATA_ENGINEER_ROLE;
GRANT SELECT, UPDATE ON TABLE INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_THRESHOLDS TO ROLE DATA_ENGINEER_ROLE;
GRANT SELECT ON TABLE INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_HISTORY TO ROLE DATA_ENGINEER_ROLE;


/* =====================================================================================
   5. DEPLOY THE STREAMLIT APP (no file upload needed)
       A small procedure writes the app code below into a stage, then the app is created
       from that stage. The app code sits between the two $$ markers - edit it there.
   ===================================================================================== */
CREATE STAGE IF NOT EXISTS INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.APP_STAGE
  DIRECTORY = (ENABLE = TRUE);
GRANT READ, WRITE ON STAGE INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.APP_STAGE TO ROLE STREAMLIT_APP_ROLE;

CREATE OR REPLACE PROCEDURE INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.SP_WRITE_APP_FILE(CODE STRING)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS
$$
import io

def run(session, code):
    target = "@INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.APP_STAGE/insurance_app/streamlit_app.py"
    session.file.put_stream(io.BytesIO(code.encode("utf-8")), target,
                            auto_compress=False, overwrite=True)
    return "written " + str(len(code)) + " characters to " + target
$$;

CALL INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.SP_WRITE_APP_FILE(
$$
# =====================================================================================
# Insurance Policy Lifecycle - Secure Underwriting, Claims & Fraud Dashboard (FINAL)
# Streamlit in Snowflake | reads ONLY the SECURE_CONSUMPTION secure views.
# Tabs: KPI Scorecard (10 KPIs) + role-based Underwriting / Claims / Fraud,
#       plus Fraud Network and Alerts for fraud users.
# =====================================================================================
from datetime import date
from decimal import Decimal

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Insurance Lifecycle Dashboard", page_icon="🛡️", layout="wide")
session = get_active_session()
SC = "INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION"

# -------------------------------------------------------------------------------------
# ACCESS CONTROL - the app runs with its OWNER role, so access is decided here by the
# viewer's Snowflake user name (UPPER CASE). Add your own user to test everything.
# -------------------------------------------------------------------------------------
ACCESS = {
    "PROJECT_USER_1": ["Underwriting"],                     # Insurance Analyst
    "PROJECT_USER_2": ["Claims"],                           # Claims Analyst
    "PROJECT_USER_3": ["Fraud"],                            # Fraud Manager
    "PROJECT_USER_4": ["Underwriting", "Claims", "Fraud"],  # Data Engineer
    "PROJECT_USER_5": ["Underwriting", "Claims", "Fraud"],  # Data Engineer
    # "YOUR_SNOWFLAKE_USER": ["Underwriting", "Claims", "Fraud"],
}
PERSONA = {
    "PROJECT_USER_1": "Insurance Analyst", "PROJECT_USER_2": "Claims Analyst",
    "PROJECT_USER_3": "Fraud Manager", "PROJECT_USER_4": "Data Engineer",
    "PROJECT_USER_5": "Data Engineer",
}
# Views with a REGION column (used to build the Region filter)
VIEWS_FOR = {
    "Underwriting": ["VW_UNDERWRITING_DASHBOARD"],
    "Claims": ["VW_CLAIMS_DASHBOARD"],
    "Fraud": ["VW_FRAUD_DASHBOARD", "VW_CLAIM_RISK_SCORES", "VW_FRAUD_NETWORK_RISK"],
}


# -------------------------------------------------------------------------------------
# HELPERS (work on old and new Streamlit versions in Snowflake)
# -------------------------------------------------------------------------------------
def show(df):
    try:
        st.dataframe(df, use_container_width=True, hide_index=True)
    except TypeError:
        st.dataframe(df.reset_index(drop=True), use_container_width=True)


def rerun():
    fn = getattr(st, "rerun", None) or getattr(st, "experimental_rerun", None)
    if fn:
        fn()


def bar(data, empty_msg="No data for the current selection."):
    if data is None or len(data) == 0:
        st.info(empty_msg)
    else:
        st.bar_chart(data)


def line(data, empty_msg="No data for the current selection."):
    if data is None or len(data) == 0:
        st.info(empty_msg)
    else:
        st.line_chart(data)


def period_count(df, date_col, id_col, freq="MS"):
    if df is None or df.empty:
        return pd.Series(dtype="int64")
    d = df.dropna(subset=[date_col])
    if d.empty:
        return pd.Series(dtype="int64")
    return d.set_index(date_col).resample(freq)[id_col].count()


def viewer_name():
    u = getattr(st, "user", None) if hasattr(st, "user") else getattr(st, "experimental_user", None)
    if u is not None:
        try:
            name = u.get("user_name") or u.get("login_name")
            if name:
                return str(name).upper()
        except Exception:
            pass
    try:
        return str(session.sql("SELECT CURRENT_USER()").collect()[0][0]).upper()
    except Exception:
        return ""


@st.cache_data(ttl=600, show_spinner="Loading secure data...")
def load(view):
    df = session.table(SC + "." + view).to_pandas()
    df.columns = [str(c).upper() for c in df.columns]
    for c in df.columns:
        if c.endswith("_DATE"):
            df[c] = pd.to_datetime(df[c], errors="coerce")
        elif c.endswith("_TIMESTAMP"):
            df[c] = pd.to_datetime(df[c], errors="coerce", utc=True).dt.tz_localize(None)
        elif df[c].dtype == object:
            vals = df[c].dropna()
            if len(vals) and vals.map(lambda v: isinstance(v, (Decimal, int, float))).all():
                df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


@st.cache_data(ttl=600)
def sql_value(sql):
    v = session.sql(sql).collect()[0][0]
    return float(v) if v is not None else 0.0


def up(s):
    return s.fillna("").astype(str).str.strip().str.upper()


def inr(x):
    x = float(x) if x is not None and not pd.isna(x) else 0.0
    if abs(x) >= 1e7:
        return f"₹{x / 1e7:,.2f} Cr"
    if abs(x) >= 1e5:
        return f"₹{x / 1e5:,.2f} L"
    return f"₹{x:,.0f}"


def div(a, b):
    a = 0.0 if a is None or pd.isna(a) else float(a)
    b = 0.0 if b is None or pd.isna(b) else float(b)
    return a / b if b else 0.0


def pct(n, d):
    return f"{100 * div(n, d):.1f}%" if d else "n/a"


def reconcile(rows):
    df = pd.DataFrame(rows, columns=["Measure", "Dashboard (pandas)", "Snowflake (SQL)"])
    df["Dashboard (pandas)"] = df["Dashboard (pandas)"].astype(float).round(2)
    df["Snowflake (SQL)"] = df["Snowflake (SQL)"].astype(float).round(2)
    df["Result"] = ["✅ MATCH" if abs(a - b) < 0.01 else "❌ MISMATCH"
                    for a, b in zip(df["Dashboard (pandas)"], df["Snowflake (SQL)"])]
    show(df)


def in_list(values):
    return "(" + ", ".join("'" + str(v).replace("'", "''") + "'" for v in values) + ")"


# -------------------------------------------------------------------------------------
# WHO IS LOOKING + SIDEBAR FILTERS
# -------------------------------------------------------------------------------------
me = viewer_name()
allowed = ACCESS.get(me, [])

st.sidebar.title("🛡️ Insurance Lifecycle")
st.sidebar.caption(f"Signed in as **{me or 'unknown'}** · {PERSONA.get(me, 'Unmapped user')}")
if not allowed:
    st.error(f"Access denied: user {me or '(unknown)'} is not mapped to any dashboard. "
             "Ask the data team to add you to ACCESS.")
    st.stop()

views_needed = {"VW_KPI_SUMMARY"} | {v for d in allowed for v in VIEWS_FOR[d]}
region_values = set()
for v in sorted(views_needed):
    region_values |= set(load(v)["REGION"].dropna().astype(str).unique())
all_regions = sorted(region_values)

regions = st.sidebar.multiselect("Region", all_regions, default=all_regions)
picked = st.sidebar.date_input("Date range", value=(date(2021, 1, 1), date.today()))
if isinstance(picked, (list, tuple)):
    d_from = picked[0] if len(picked) > 0 else date(2000, 1, 1)
    d_to = picked[1] if len(picked) > 1 else date.today()
else:
    d_from, d_to = picked, date.today()
if st.sidebar.button("🔄 Refresh data"):
    st.cache_data.clear()
    rerun()
st.sidebar.caption("Customer PII is never shown in this app.")

if not regions:
    st.warning("Select at least one region in the sidebar.")
    st.stop()


def apply_filters(df, date_col):
    out = df[df["REGION"].isin(regions)] if "REGION" in df.columns else df
    if date_col in out.columns:
        dts = out[date_col]
        out = out[dts.isna() | dts.between(pd.Timestamp(d_from), pd.Timestamp(d_to))]
    return out


# =====================================================================================
# 0. KPI SCORECARD - all 10 KPIs (every role)
# =====================================================================================
def kpi_scorecard():
    k = load("VW_KPI_SUMMARY")
    k = k[k["REGION"].isin(regions)].copy()
    s = k.sum(numeric_only=True)

    st.caption("All 10 business KPIs · aggregated, no customer PII · follows the Region filter (all dates)")
    r1 = st.columns(5)
    r1[0].metric("① Active policies", f"{int(s.get('ACTIVE_POLICIES', 0)):,}")
    r1[1].metric("① Active sum insured", inr(s.get("ACTIVE_SUM_INSURED", 0)))
    r1[2].metric("② Premium collected", inr(s.get("PREMIUM_COLLECTED", 0)), help="Sum of PAID premium payments")
    r1[3].metric("③ Claim frequency",
                 f"{100 * div(s.get('TOTAL_CLAIMS'), s.get('TOTAL_POLICIES')):.1f} / 100 policies")
    r1[4].metric("③ Average claim", inr(div(s.get("TOTAL_CLAIM_AMOUNT"), s.get("TOTAL_CLAIMS"))))
    r2 = st.columns(5)
    r2[0].metric("④ Approval ratio", pct(s.get("APPROVED_CLAIMS"), s.get("TOTAL_CLAIMS")),
                 help="Approved + Settled claims ÷ all claims (status-based)")
    r2[1].metric("⑤ Settlement TAT", f"{div(s.get('TAT_DAYS_SUM'), s.get('SETTLED_CLAIMS')):.1f} days")
    r2[2].metric("⑥ Net settlement", inr(s.get("NET_SETTLEMENT_AMOUNT", 0)))
    r2[3].metric("⑦ Loss ratio proxy", pct(s.get("NET_SETTLEMENT_AMOUNT"), s.get("PREMIUM_COLLECTED")),
                 help="Net settlement ÷ premium collected")
    r2[4].metric("⑧ Open investigations", f"{int(s.get('OPEN_INVESTIGATIONS', 0)):,}")
    r3 = st.columns(5)
    r3[0].metric("⑨ Confirmed fraud rate", pct(s.get("CONFIRMED_FRAUD_CASES"), s.get("FRAUD_CASES")))
    r3[1].metric("⑩ High-risk claims", f"{int(s.get('HIGH_RISK_CLAIMS', 0)):,}")

    st.subheader("KPIs by region")
    if k.empty:
        st.info("No KPI data for the selected regions.")
        return

    def ratio(n, d, mult=1.0, digits=1):
        return (mult * k[n] / k[d].where(k[d] != 0)).round(digits)

    k["CLAIMS_PER_100_POLICIES"] = ratio("TOTAL_CLAIMS", "TOTAL_POLICIES", 100)
    k["AVG_CLAIM"] = ratio("TOTAL_CLAIM_AMOUNT", "TOTAL_CLAIMS", 1, 0)
    k["APPROVAL_RATIO_%"] = ratio("APPROVED_CLAIMS", "TOTAL_CLAIMS", 100)
    k["SETTLEMENT_TAT_DAYS"] = ratio("TAT_DAYS_SUM", "SETTLED_CLAIMS")
    k["LOSS_RATIO_%"] = ratio("NET_SETTLEMENT_AMOUNT", "PREMIUM_COLLECTED", 100)
    k["CONFIRMED_FRAUD_%"] = ratio("CONFIRMED_FRAUD_CASES", "FRAUD_CASES", 100)
    show(k[["REGION", "ACTIVE_POLICIES", "ACTIVE_SUM_INSURED", "PREMIUM_COLLECTED",
            "CLAIMS_PER_100_POLICIES", "AVG_CLAIM", "APPROVAL_RATIO_%", "SETTLEMENT_TAT_DAYS",
            "NET_SETTLEMENT_AMOUNT", "LOSS_RATIO_%", "OPEN_INVESTIGATIONS",
            "CONFIRMED_FRAUD_%", "HIGH_RISK_CLAIMS"]].sort_values("REGION"))

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Loss ratio proxy by region (%)")
        bar(k.set_index("REGION")["LOSS_RATIO_%"].dropna())
    with c2:
        st.subheader("Approval ratio by region (%)")
        bar(k.set_index("REGION")["APPROVAL_RATIO_%"].dropna())

    with st.expander("🔎 Reconciliation - scorecard vs Snowflake"):
        where = " WHERE REGION IN " + in_list(regions)
        reconcile([
            ("Active policies", s.get("ACTIVE_POLICIES", 0),
             sql_value(f"SELECT COALESCE(SUM(ACTIVE_POLICIES),0) FROM {SC}.VW_KPI_SUMMARY" + where)),
            ("Premium collected", s.get("PREMIUM_COLLECTED", 0),
             sql_value(f"SELECT COALESCE(SUM(PREMIUM_COLLECTED),0) FROM {SC}.VW_KPI_SUMMARY" + where)),
        ])


# =====================================================================================
# 1. UNDERWRITING - Insurance Analyst
# =====================================================================================
def underwriting():
    raw = load("VW_UNDERWRITING_DASHBOARD")
    df = apply_filters(raw, "POLICY_START_DATE")
    types = st.multiselect("Insurance type", sorted(df["INSURANCE_TYPE"].dropna().unique()), key="uw_types")
    if types:
        df = df[df["INSURANCE_TYPE"].isin(types)]

    status = up(df["POLICY_STATUS"])
    active = df[status == "ACTIVE"]

    k = st.columns(5)
    k[0].metric("Active policies", f"{len(active):,}", help=f"{len(df):,} policies in selection")
    k[1].metric("Active sum insured", inr(active["SUM_INSURED"].sum()))
    k[2].metric("Premium collected", inr(df["PREMIUM_COLLECTED"].sum()))
    k[3].metric("Lapse rate", pct((status == "LAPSED").sum(), len(df)))
    k[4].metric("Reversed payments", f"{int(df['REVERSED_PAYMENTS'].sum()):,}")

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Premium collected by insurance type")
        bar(df.groupby("INSURANCE_TYPE")["PREMIUM_COLLECTED"].sum())
    with c2:
        st.subheader("Policy status by underwriting risk band")
        if df.empty:
            st.info("No data for the current selection.")
        else:
            bar(df.pivot_table(index="UNDERWRITING_RISK_BAND", columns="POLICY_STATUS",
                               values="POLICY_ID", aggfunc="count", fill_value=0))
    c3, c4 = st.columns(2)
    with c3:
        st.subheader("Active sum insured by region")
        bar(active.groupby("REGION")["SUM_INSURED"].sum())
    with c4:
        st.subheader("New policies per month")
        line(period_count(df, "POLICY_START_DATE", "POLICY_ID"))

    st.subheader("⏳ Active policies expiring in the next 90 days")
    today = pd.Timestamp(date.today())
    soon = active[active["POLICY_EXPIRY_DATE"].between(today, today + pd.Timedelta(days=90))]
    show(soon[["POLICY_ID", "PRODUCT_NAME", "INSURANCE_TYPE", "REGION", "POLICY_EXPIRY_DATE",
               "SUM_INSURED", "PREMIUM_AMOUNT", "UNDERWRITING_RISK_BAND"]].sort_values("POLICY_EXPIRY_DATE"))

    st.subheader("⚠️ High-risk customers holding active policies")
    hr = active[up(active["CUSTOMER_RISK_CATEGORY"]) == "HIGH"]
    show(hr[["POLICY_ID", "CUSTOMER_ID", "INSURANCE_TYPE", "REGION", "SUM_INSURED",
             "UNDERWRITING_RISK_BAND", "PREMIUM_COLLECTED"]])

    with st.expander("🔎 Reconciliation - dashboard vs Snowflake (all data)"):
        reconcile([
            ("Total policies", len(raw), sql_value(f"SELECT COUNT(*) FROM {SC}.VW_UNDERWRITING_DASHBOARD")),
            ("Premium collected", raw["PREMIUM_COLLECTED"].sum(),
             sql_value(f"SELECT COALESCE(SUM(PREMIUM_COLLECTED),0) FROM {SC}.VW_UNDERWRITING_DASHBOARD")),
        ])


# =====================================================================================
# 2. CLAIMS - Claims Analyst
# =====================================================================================
def claims():
    raw = load("VW_CLAIMS_DASHBOARD")
    df = apply_filters(raw, "CLAIM_REGISTRATION_DATE")
    types = st.multiselect("Claim type", sorted(df["CLAIM_TYPE"].dropna().unique()), key="cl_types")
    if types:
        df = df[df["CLAIM_TYPE"].isin(types)]

    status = up(df["CLAIM_STATUS"])
    approved = status.isin(["APPROVED", "SETTLED"])
    settled = df[df["SETTLEMENT_COUNT"] > 0]
    kp = load("VW_KPI_SUMMARY")
    kp = kp[kp["REGION"].isin(regions)]

    k = st.columns(6)
    k[0].metric("Claims", f"{len(df):,}")
    k[1].metric("Loss ratio proxy", pct(kp["NET_SETTLEMENT_AMOUNT"].sum(), kp["PREMIUM_COLLECTED"].sum()),
                help="Net settlement ÷ premium collected (selected regions, all dates)")
    k[2].metric("Average claim", inr(df["CLAIM_AMOUNT"].mean() if len(df) else 0))
    k[3].metric("Approval ratio", pct(approved.sum(), len(df)))
    k[4].metric("Avg settlement TAT",
                f"{settled['SETTLEMENT_TAT_DAYS'].mean():.1f} days" if len(settled) else "n/a")
    k[5].metric("Net settled", inr(df["NET_SETTLED"].sum()))

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Claims registered per month")
        line(period_count(df, "CLAIM_REGISTRATION_DATE", "CLAIM_ID"))
    with c2:
        st.subheader("Claim status mix")
        bar(df.groupby("CLAIM_STATUS")["CLAIM_ID"].count())
    c3, c4 = st.columns(2)
    with c3:
        st.subheader("Claim vs approved amount by claim type")
        bar(df.groupby("CLAIM_TYPE")[["CLAIM_AMOUNT", "APPROVED_AMOUNT"]].sum())
    with c4:
        st.subheader("Average settlement TAT (days) by insurance type")
        bar(settled.groupby("INSURANCE_TYPE")["SETTLEMENT_TAT_DAYS"].mean().dropna())

    st.subheader("🚩 Settlement exceptions")
    cols = ["CLAIM_ID", "POLICY_ID", "CLAIM_TYPE", "REGION", "CLAIM_STATUS", "CLAIM_AMOUNT",
            "APPROVED_AMOUNT", "GROSS_SETTLED", "NET_SETTLED", "SETTLEMENT_TAT_DAYS"]
    e1, e2, e3 = st.tabs(["Settled without approval", "Approved but not settled", "Net amount mismatch"])
    with e1:
        x = df[(df["SETTLEMENT_COUNT"] > 0) & status.isin(["REJECTED", "UNDER REVIEW"])]
        st.caption(f"{len(x):,} claims paid while Rejected / Under Review · {inr(x['NET_SETTLED'].sum())} at risk")
        show(x[cols])
    with e2:
        x = df[(df["SETTLEMENT_COUNT"] == 0) & (status == "APPROVED")]
        st.caption(f"{len(x):,} approved claims with no settlement yet")
        show(x[cols])
    with e3:
        x = df[df["NET_MISMATCH_COUNT"] > 0]
        st.caption(f"{len(x):,} claims where net ≠ gross − deductible − recovery")
        show(x[cols])

    with st.expander("🔎 Reconciliation - dashboard vs Snowflake (all data)"):
        reconcile([
            ("Total claims", len(raw), sql_value(f"SELECT COUNT(*) FROM {SC}.VW_CLAIMS_DASHBOARD")),
            ("Total claim amount", raw["CLAIM_AMOUNT"].sum(),
             sql_value(f"SELECT COALESCE(SUM(CLAIM_AMOUNT),0) FROM {SC}.VW_CLAIMS_DASHBOARD")),
            ("Net settled", raw["NET_SETTLED"].sum(),
             sql_value(f"SELECT COALESCE(SUM(NET_SETTLED),0) FROM {SC}.VW_CLAIMS_DASHBOARD")),
        ])


# =====================================================================================
# 3. FRAUD - Fraud Manager
# =====================================================================================
def fraud():
    fc_raw, rs_raw = load("VW_FRAUD_DASHBOARD"), load("VW_CLAIM_RISK_SCORES")
    fc = apply_filters(fc_raw, "INVESTIGATION_START_DATE")
    rs = apply_filters(rs_raw, "CLAIM_REGISTRATION_DATE")

    is_open = fc["INVESTIGATION_END_DATE"].isna() | (up(fc["INVESTIGATION_STATUS"]) == "OPEN")
    confirmed = up(fc["INVESTIGATION_OUTCOME"]).str.contains("CONFIRMED")
    days_open = (pd.Timestamp(date.today()) - fc["INVESTIGATION_START_DATE"]).dt.days
    high = rs[up(rs["RISK_CATEGORY"]) == "HIGH"]

    k = st.columns(5)
    k[0].metric("Fraud cases", f"{len(fc):,}")
    k[1].metric("Open investigations", f"{int(is_open.sum()):,}")
    k[2].metric("Confirmed fraud rate", pct(confirmed.sum(), len(fc)))
    k[3].metric("High-risk claims", f"{len(high):,}")
    avg_open = days_open[is_open].mean()
    k[4].metric("Avg days open", f"{avg_open:.0f}" if pd.notna(avg_open) else "0")

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Claim risk category mix")
        bar(rs.groupby("RISK_CATEGORY")["CLAIM_ID"].count())
    with c2:
        st.subheader("Investigation outcomes")
        bar(fc.groupby("INVESTIGATION_OUTCOME")["FRAUD_CASE_ID"].count())
    c3, c4 = st.columns(2)
    with c3:
        st.subheader("Top trigger reasons")
        bar(fc.groupby("TRIGGER_REASON")["FRAUD_CASE_ID"].count().sort_values(ascending=False).head(10))
    with c4:
        st.subheader("Open cases per investigator")
        bar(fc[is_open].groupby("INVESTIGATOR_ID")["FRAUD_CASE_ID"].count())

    st.subheader("🔍 Why is this claim high risk?")
    if high.empty:
        st.info("No HIGH risk claims in the current selection.")
    else:
        top = high.sort_values("TOTAL_RISK_SCORE", ascending=False)
        pick = st.selectbox("Select a HIGH risk claim", top["CLAIM_ID"].tolist(), key="fr_pick")
        r = top[top["CLAIM_ID"] == pick].iloc[0]
        a, b = st.columns([2, 1])
        with a:
            bar(pd.DataFrame({"Score": [r["CLAIM_RISK_SCORE"], r["CUSTOMER_RISK_SCORE"],
                                        r["POLICY_RISK_SCORE"], r["FRAUD_HISTORY_SCORE"]]},
                             index=["Claim", "Customer", "Policy", "Fraud history"]))
        with b:
            st.metric("Total risk score", int(r["TOTAL_RISK_SCORE"]))
            st.write(f"**Claim type:** {r['CLAIM_TYPE']}")
            st.write(f"**Claim amount:** {inr(r['CLAIM_AMOUNT'])}")
            st.write(f"**Status:** {r['CLAIM_STATUS']}")
            st.caption(f"Scored at {r['SCORING_TIMESTAMP']}")
        show(top[["CLAIM_ID", "POLICY_ID", "REGION", "CLAIM_TYPE", "CLAIM_AMOUNT", "CLAIM_STATUS",
                  "TOTAL_RISK_SCORE"]])

    st.subheader("⏰ Open investigations older than 30 days")
    aged = fc[is_open & (days_open > 30)].assign(DAYS_OPEN=days_open)
    show(aged[["FRAUD_CASE_ID", "CLAIM_ID", "REGION", "SOURCE_FRAUD_SCORE", "TRIGGER_REASON",
               "INVESTIGATOR_ID", "INVESTIGATION_START_DATE", "DAYS_OPEN"]]
         .sort_values("DAYS_OPEN", ascending=False))

    with st.expander("🔎 Reconciliation - dashboard vs Snowflake (all data)"):
        open_raw = fc_raw["INVESTIGATION_END_DATE"].isna() | (up(fc_raw["INVESTIGATION_STATUS"]) == "OPEN")
        reconcile([
            ("Fraud cases", len(fc_raw), sql_value(f"SELECT COUNT(*) FROM {SC}.VW_FRAUD_DASHBOARD")),
            ("Open investigations", int(open_raw.sum()),
             sql_value(f"SELECT COUNT_IF(INVESTIGATION_END_DATE IS NULL OR UPPER(INVESTIGATION_STATUS) = 'OPEN') "
                       f"FROM {SC}.VW_FRAUD_DASHBOARD")),
            ("High-risk claims", int((up(rs_raw["RISK_CATEGORY"]) == "HIGH").sum()),
             sql_value(f"SELECT COUNT_IF(UPPER(RISK_CATEGORY) = 'HIGH') FROM {SC}.VW_CLAIM_RISK_SCORES")),
        ])


# =====================================================================================
# 4. FRAUD NETWORK - customers linked by shared phone / email / address / nominee / agent / assessor
# =====================================================================================
def fraud_network():
    risk = load("VW_FRAUD_NETWORK_RISK")
    links = load("VW_FRAUD_LINKS")
    risk = risk[risk["REGION"].isin(regions)]

    k = st.columns(4)
    k[0].metric("Linked customers", f"{len(risk):,}")
    k[1].metric("HIGH network risk", int((risk["NETWORK_RISK"] == "HIGH").sum()))
    k[2].metric("MEDIUM network risk", int((risk["NETWORK_RISK"] == "MEDIUM").sum()))
    k[3].metric("Links found", f"{len(links):,}")

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Links by type")
        bar(links.groupby("LINK_TYPE")["CUSTOMER_A"].count() if len(links) else None)
    with c2:
        st.subheader("Network risk mix")
        bar(risk.groupby("NETWORK_RISK")["CUSTOMER_ID"].count() if len(risk) else None)

    st.subheader("🚩 Most connected to fraud")
    if risk.empty:
        st.info("No linked customers in the selected regions.")
        return
    top = risk.sort_values(["LINKED_CONFIRMED_FRAUD", "LINKED_WITH_FRAUD_CASE", "LINKED_CUSTOMERS"],
                           ascending=False)
    show(top.head(50))

    st.subheader("🕸️ Explore a customer's network")
    pick = st.selectbox("Customer", top["CUSTOMER_ID"].head(200).tolist(), key="net_pick")
    direct = links[(links["CUSTOMER_A"] == pick) | (links["CUSTOMER_B"] == pick)]
    nodes = set(direct["CUSTOMER_A"]) | set(direct["CUSTOMER_B"]) | {pick}
    edges = links[links["CUSTOMER_A"].isin(nodes) & links["CUSTOMER_B"].isin(nodes)]
    flags = load("VW_FRAUD_NETWORK_RISK").drop_duplicates("CUSTOMER_ID").set_index("CUSTOMER_ID")

    dot = ["graph G {", "layout=neato; overlap=false;",
           "node [shape=circle style=filled fontname=Helvetica fontsize=9];"]
    for n in sorted(nodes):
        conf = n in flags.index and flags.at[n, "OWN_CONFIRMED"] > 0
        case = n in flags.index and flags.at[n, "OWN_FRAUD_CASES"] > 0
        color = "#E05C5C" if conf else ("#F2A541" if case else "#A7C7E7")
        border = " penwidth=3" if n == pick else ""
        dot.append(f'"{n}" [fillcolor="{color}"{border}];')
    for e in edges.itertuples(index=False):
        dot.append(f'"{e.CUSTOMER_A}" -- "{e.CUSTOMER_B}" [label="{e.LINK_TYPE}" fontsize=7];')
    dot.append("}")
    st.graphviz_chart(chr(10).join(dot), use_container_width=True)
    st.caption("🔴 confirmed fraud · 🟠 has fraud case · 🔵 no fraud case · thick border = selected")


# =====================================================================================
# 5. ALERTS - threshold breaches
# =====================================================================================
def alerts():
    hist = load("VW_ALERT_HISTORY")
    thr = load("VW_ALERT_THRESHOLDS")
    fired = hist[hist["STATUS"] == "FIRED"] if len(hist) else hist
    week = pd.Timestamp(date.today()) - pd.Timedelta(days=7)
    recent = fired[fired["ALERT_TIMESTAMP"] >= week] if len(fired) else fired

    k = st.columns(4)
    k[0].metric("Alerts (last 7 days)", f"{len(recent):,}")
    k[1].metric("HIGH severity (7 days)", int((recent["SEVERITY"] == "HIGH").sum()) if len(recent) else 0)
    k[2].metric("Emails failed", int((~fired["EMAIL_SENT"].fillna(False).astype(bool)).sum()) if len(fired) else 0)
    k[3].metric("Active rules", int(thr["IS_ACTIVE"].fillna(False).astype(bool).sum()) if len(thr) else 0)

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Alerts by metric")
        bar(fired.groupby("METRIC_NAME")["ALERT_ID"].count() if len(fired) else None, "No alerts fired yet.")
    with c2:
        st.subheader("Alerts per day")
        line(period_count(fired, "ALERT_TIMESTAMP", "ALERT_ID", "D"), "No alerts fired yet.")

    st.subheader("Latest alerts")
    if len(hist):
        show(hist.sort_values("ALERT_TIMESTAMP", ascending=False).head(50))
    else:
        st.info("No alerts yet. Run CALL MONITORING.SP_CHECK_THRESHOLDS();")
    st.subheader("Current limits")
    show(thr)
    st.caption("Limits are changed by Data Engineers in MONITORING.ALERT_THRESHOLDS - no code change needed.")


# =====================================================================================
# RENDER
# =====================================================================================
st.title("Insurance Policy Lifecycle - Secure Analytics")
ICON = {"KPI": "📊 KPI Scorecard", "Underwriting": "📑 Underwriting", "Claims": "📋 Claims",
        "Fraud": "🚨 Fraud", "Network": "🕸️ Fraud Network", "Alerts": "🔔 Alerts"}
PAGE_FUNCTIONS = {"KPI": kpi_scorecard, "Underwriting": underwriting, "Claims": claims,
                  "Fraud": fraud, "Network": fraud_network, "Alerts": alerts}
pages = ["KPI"] + allowed + (["Network", "Alerts"] if "Fraud" in allowed else [])
tab_objects = st.tabs([ICON.get(p, p) for p in pages])
for tab_obj, page_key in zip(tab_objects, pages):
    with tab_obj:
        page_function = PAGE_FUNCTIONS.get(page_key)
        if page_function is not None:
            page_function()
$$
);

LIST @INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.APP_STAGE/insurance_app/;

-- create the app as STREAMLIT_APP_ROLE (the app runs with its owner's privileges)
USE ROLE STREAMLIT_APP_ROLE;
USE WAREHOUSE IDMC_COMPUTE_WH;
CREATE OR REPLACE STREAMLIT INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.INSURANCE_LIFECYCLE_DASHBOARD
  ROOT_LOCATION = '@INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.APP_STAGE/insurance_app'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = IDMC_COMPUTE_WH
  TITLE = 'Insurance Lifecycle Dashboard';


/* =====================================================================================
   6. SHARE THE APP WITH THE BUSINESS ROLES (without this they cannot see it)
   ===================================================================================== */
GRANT USAGE ON STREAMLIT INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.INSURANCE_LIFECYCLE_DASHBOARD TO ROLE INSURANCE_ANALYST_ROLE;
GRANT USAGE ON STREAMLIT INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.INSURANCE_LIFECYCLE_DASHBOARD TO ROLE CLAIMS_ANALYST_ROLE;
GRANT USAGE ON STREAMLIT INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.INSURANCE_LIFECYCLE_DASHBOARD TO ROLE FRAUD_MANAGER_ROLE;
GRANT USAGE ON STREAMLIT INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION.INSURANCE_LIFECYCLE_DASHBOARD TO ROLE DATA_ENGINEER_ROLE;


/* =====================================================================================
   7. VALIDATION
   ===================================================================================== */
USE ROLE ACCOUNTADMIN;

-- 7.1 email works (arrives within a minute)
CALL SYSTEM$SEND_EMAIL('INSURANCE_ALERT_EMAIL_INT', '<YOUR_EMAIL>',
     'Insurance alerts - test', 'If you can read this, threshold alerts will work.');

-- 7.2 current value of every metric (check before alerts fire)
SELECT METRIC_NAME, OPERATOR, THRESHOLD_VALUE, SEVERITY, IS_ACTIVE
FROM INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_THRESHOLDS ORDER BY METRIC_NAME;

-- 7.3 first run: breached metrics send emails -> fired > 0
CALL INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.SP_CHECK_THRESHOLDS();

-- 7.4 second run straight away: no duplicate emails -> fired = 0, suppressed > 0
CALL INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.SP_CHECK_THRESHOLDS();

-- 7.5 log: STATUS = FIRED, EMAIL_SENT = TRUE (METRIC_ERROR rows show a broken metric query)
SELECT ALERT_TS, METRIC_NAME, METRIC_VALUE, OPERATOR, THRESHOLD_VALUE, SEVERITY,
       STATUS, EMAIL_SENT, ERROR_MESSAGE
FROM INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_HISTORY ORDER BY ALERT_TS DESC;

-- 7.6 task is scheduled (STATE = started)
SHOW TASKS LIKE 'T_CHECK_THRESHOLDS' IN SCHEMA INSURANCEPOLICY_LIFECYCLE_DB.MONITORING;

-- 7.7 app exists and is shared
SHOW STREAMLITS IN SCHEMA INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION;

/* -------------------------------------------------------------------------------------
   USEFUL COMMANDS
   - Change a limit (no redeploy):
       UPDATE INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_THRESHOLDS
          SET THRESHOLD_VALUE = 15, UPDATED_BY = CURRENT_USER(), UPDATED_TS = CURRENT_TIMESTAMP()
        WHERE METRIC_NAME = 'HIGH_RISK_CLAIMS';
   - Switch one alert off:   ... SET IS_ACTIVE = FALSE WHERE METRIC_NAME = '...';
   - Pause all alerts:       ALTER TASK INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.T_CHECK_THRESHOLDS SUSPEND;
   - Re-send for a demo:     DELETE FROM INSURANCEPOLICY_LIFECYCLE_DB.MONITORING.ALERT_HISTORY;
   ------------------------------------------------------------------------------------- */
