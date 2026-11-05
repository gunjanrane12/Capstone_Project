"""
Insurance Policy Lifecycle - Secure Underwriting, Claims & Fraud Dashboard (FINAL)
Streamlit in Snowflake | reads ONLY the SECURE_CONSUMPTION secure views.

Tabs: KPI Scorecard (all 10 business KPIs) + role-based Underwriting / Claims / Fraud.
Deploy: Snowsight -> role STREAMLIT_APP_ROLE -> Projects -> Streamlit -> + Streamlit App
        Location INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION, warehouse IDMC_COMPUTE_WH.
"""
from datetime import date, timedelta
from decimal import Decimal

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Insurance Lifecycle Dashboard", page_icon="🛡️", layout="wide")
session = get_active_session()
SC = "INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION"

# ---------------------------------------------------------------------------
# ACCESS CONTROL
# The app runs with the OWNER role (STREAMLIT_APP_ROLE), not the viewer's role,
# so the app decides which dashboards each viewer gets, by Snowflake user name.
# Add your own user (UPPER CASE) to test everything.
# ---------------------------------------------------------------------------
ACCESS = {
    "PROJECT_USER_1": ["Underwriting"],                     # Insurance Analyst
    "PROJECT_USER_2": ["Claims"],                           # Claims Analyst
    "PROJECT_USER_3": ["Fraud"],                            # Fraud Manager
    "PROJECT_USER_4": ["Underwriting", "Claims", "Fraud"],  # Data Engineer
    "PROJECT_USER_5": ["Underwriting", "Claims", "Fraud"],  # Data Engineer
    # "<YOUR_SNOWFLAKE_USER>": ["Underwriting", "Claims", "Fraud"],
}
PERSONA = {
    "PROJECT_USER_1": "Insurance Analyst", "PROJECT_USER_2": "Claims Analyst",
    "PROJECT_USER_3": "Fraud Manager", "PROJECT_USER_4": "Data Engineer",
    "PROJECT_USER_5": "Data Engineer",
}
VIEWS_FOR = {
    "Underwriting": ["VW_UNDERWRITING_DASHBOARD"],
    "Claims": ["VW_CLAIMS_DASHBOARD"],
    "Fraud": ["VW_FRAUD_DASHBOARD", "VW_CLAIM_RISK_SCORES"],
}


# ---------------------------------------------------------------------------
# COMPATIBILITY HELPERS (work on old and new Streamlit versions in Snowflake)
# ---------------------------------------------------------------------------
def show(df: pd.DataFrame):
    try:
        st.dataframe(df, use_container_width=True, hide_index=True)
    except TypeError:                              # Streamlit < 1.23 has no hide_index
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


def monthly_count(df: pd.DataFrame, date_col: str, id_col: str) -> pd.Series:
    d = df.dropna(subset=[date_col])
    if d.empty:
        return pd.Series(dtype="int64")
    return d.set_index(date_col).resample("MS")[id_col].count()


def viewer_name() -> str:
    # st.user on newer Streamlit, st.experimental_user on older versions (never both -> no deprecation banner)
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


# ---------------------------------------------------------------------------
# DATA ACCESS
# ---------------------------------------------------------------------------
@st.cache_data(ttl=600, show_spinner="Loading secure data...")
def load(view: str) -> pd.DataFrame:
    df = session.table(f"{SC}.{view}").to_pandas()
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
def sql_value(sql: str) -> float:
    v = session.sql(sql).collect()[0][0]
    return float(v) if v is not None else 0.0


def up(s: pd.Series) -> pd.Series:
    return s.fillna("").astype(str).str.strip().str.upper()


def inr(x) -> str:
    x = float(x) if x is not None and not pd.isna(x) else 0.0
    if abs(x) >= 1e7:
        return f"₹{x / 1e7:,.2f} Cr"
    if abs(x) >= 1e5:
        return f"₹{x / 1e5:,.2f} L"
    return f"₹{x:,.0f}"


def div(a, b) -> float:
    a = 0.0 if a is None or pd.isna(a) else float(a)
    b = 0.0 if b is None or pd.isna(b) else float(b)
    return a / b if b else 0.0


def pct(n, d) -> str:
    return f"{100 * div(n, d):.1f}%" if d else "n/a"


def reconcile(rows):
    """rows = [(measure, dashboard_value, snowflake_value)]"""
    df = pd.DataFrame(rows, columns=["Measure", "Dashboard (pandas)", "Snowflake (SQL)"])
    df["Dashboard (pandas)"] = df["Dashboard (pandas)"].astype(float).round(2)
    df["Snowflake (SQL)"] = df["Snowflake (SQL)"].astype(float).round(2)
    df["Result"] = ["✅ MATCH" if abs(a - b) < 0.01 else "❌ MISMATCH"
                    for a, b in zip(df["Dashboard (pandas)"], df["Snowflake (SQL)"])]
    show(df)


# ---------------------------------------------------------------------------
# WHO IS LOOKING + SIDEBAR FILTERS
# ---------------------------------------------------------------------------
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


def apply_filters(df: pd.DataFrame, date_col: str) -> pd.DataFrame:
    out = df[df["REGION"].isin(regions)] if "REGION" in df.columns else df
    if date_col in out.columns:
        dts = out[date_col]
        out = out[dts.isna() | dts.between(pd.Timestamp(d_from), pd.Timestamp(d_to))]
    return out


# ===========================================================================
# 0. KPI SCORECARD - all 10 KPIs from the business document (every role)
# ===========================================================================
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
                 f"{100 * div(s.get('TOTAL_CLAIMS'), s.get('TOTAL_POLICIES')):.1f} / 100 policies",
                 help="Claims ÷ policies × 100")
    r1[4].metric("③ Average claim", inr(div(s.get("TOTAL_CLAIM_AMOUNT"), s.get("TOTAL_CLAIMS"))))
    r2 = st.columns(5)
    r2[0].metric("④ Approval ratio", pct(s.get("APPROVED_CLAIMS"), s.get("TOTAL_CLAIMS")),
                 help="Approved + Settled claims ÷ all claims (status-based)")
    r2[1].metric("⑤ Settlement TAT", f"{div(s.get('TAT_DAYS_SUM'), s.get('SETTLED_CLAIMS')):.1f} days",
                 help="Claim registration → first settlement")
    r2[2].metric("⑥ Net settlement", inr(s.get("NET_SETTLEMENT_AMOUNT", 0)))
    r2[3].metric("⑦ Loss ratio proxy", pct(s.get("NET_SETTLEMENT_AMOUNT"), s.get("PREMIUM_COLLECTED")),
                 help="Net settlement ÷ premium collected")
    r2[4].metric("⑧ Open investigations", f"{int(s.get('OPEN_INVESTIGATIONS', 0)):,}")
    r3 = st.columns(5)
    r3[0].metric("⑨ Confirmed fraud rate", pct(s.get("CONFIRMED_FRAUD_CASES"), s.get("FRAUD_CASES")))
    r3[1].metric("⑩ High-risk claims", f"{int(s.get('HIGH_RISK_CLAIMS', 0)):,}",
                 help="Snowpark RISK_CATEGORY = HIGH")

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
        reconcile([
            ("Active policies", s.get("ACTIVE_POLICIES", 0),
             sql_value(f"SELECT COALESCE(SUM(ACTIVE_POLICIES),0) FROM {SC}.VW_KPI_SUMMARY "
                       f"WHERE REGION IN ({', '.join(repr(r) for r in regions)})")),
            ("Premium collected", s.get("PREMIUM_COLLECTED", 0),
             sql_value(f"SELECT COALESCE(SUM(PREMIUM_COLLECTED),0) FROM {SC}.VW_KPI_SUMMARY "
                       f"WHERE REGION IN ({', '.join(repr(r) for r in regions)})")),
        ])


# ===========================================================================
# 1. UNDERWRITING DASHBOARD - Insurance Analyst
# ===========================================================================
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
    k[2].metric("Premium collected", inr(df["PREMIUM_COLLECTED"].sum()), help="Sum of PAID payments")
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
        line(monthly_count(df, "POLICY_START_DATE", "POLICY_ID"))

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


# ===========================================================================
# 2. CLAIMS DASHBOARD - Claims Analyst
# ===========================================================================
def claims():
    raw = load("VW_CLAIMS_DASHBOARD")
    df = apply_filters(raw, "CLAIM_REGISTRATION_DATE")
    types = st.multiselect("Claim type", sorted(df["CLAIM_TYPE"].dropna().unique()), key="cl_types")
    if types:
        df = df[df["CLAIM_TYPE"].isin(types)]

    status = up(df["CLAIM_STATUS"])
    approved = status.isin(["APPROVED", "SETTLED"])   # status-based: rejected claims still carry approved_amount
    settled = df[df["SETTLEMENT_COUNT"] > 0]
    kp = load("VW_KPI_SUMMARY")
    kp = kp[kp["REGION"].isin(regions)]

    k = st.columns(6)
    k[0].metric("Claims", f"{len(df):,}")
    k[1].metric("Loss ratio proxy", pct(kp["NET_SETTLEMENT_AMOUNT"].sum(), kp["PREMIUM_COLLECTED"].sum()),
                help="Net settlement ÷ premium collected (selected regions, all dates)")
    k[2].metric("Average claim", inr(df["CLAIM_AMOUNT"].mean() if len(df) else 0))
    k[3].metric("Approval ratio", pct(approved.sum(), len(df)), help="Approved + Settled ÷ all claims")
    k[4].metric("Avg settlement TAT",
                f"{settled['SETTLEMENT_TAT_DAYS'].mean():.1f} days" if len(settled) else "n/a")
    k[5].metric("Net settled", inr(df["NET_SETTLED"].sum()))

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Claims registered per month")
        line(monthly_count(df, "CLAIM_REGISTRATION_DATE", "CLAIM_ID"))
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
        st.caption(f"{len(x):,} claims paid while Rejected / Under Review")
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


# ===========================================================================
# 3. FRAUD DASHBOARD - Fraud Manager
# ===========================================================================
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
    k[3].metric("High-risk claims", f"{len(high):,}", help="Snowpark TOTAL_RISK_SCORE category")
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


# ===========================================================================
# RENDER - KPI scorecard for everyone + only the dashboards this user may see
# ===========================================================================
st.title("Insurance Policy Lifecycle - Secure Analytics")
ICON = {"KPI": "📊 KPI Scorecard", "Underwriting": "📑 Underwriting",
        "Claims": "📋 Claims", "Fraud": "🚨 Fraud"}
RENDER = {"KPI": kpi_scorecard, "Underwriting": underwriting, "Claims": claims, "Fraud": fraud}
pages = ["KPI"] + allowed
for tab, name in zip(st.tabs([ICON[p] for p in pages]), pages):
    with tab:
        RENDER[name]()
