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

