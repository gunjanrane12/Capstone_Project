"""
Insurance Policy Lifecycle - Secure Analytics Dashboard
Streamlit in Snowflake

Features:
- KPI Scorecard
- Underwriting Dashboard
- Claims Dashboard
- Fraud Dashboard
- Fraud Network
- Cortex Analyst
- Role-based access
- Secure Consumption views
"""

from datetime import date
from decimal import Decimal
import json

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session
import _snowflake


# =============================================================================
# CONFIGURATION
# =============================================================================

st.set_page_config(
    page_title="Insurance Lifecycle Dashboard",
    page_icon="🛡️",
    layout="wide"
)


# =============================================================================
# VISUAL THEME
# =============================================================================

st.markdown(
    """
    <style>
    :root {
        --navy: #10243a;
        --navy-2: #183752;
        --teal: #0f9d91;
        --teal-soft: #e8f7f5;
        --ink: #172b42;
        --muted: #64748b;
        --line: #e3eaf2;
        --surface: #ffffff;
    }

    .stApp {
        background:
            radial-gradient(circle at 92% 2%, rgba(15,157,145,.09), transparent 25%),
            linear-gradient(180deg, #f5f8fc 0%, #f2f6fb 100%);
        color: var(--ink);
    }

    .block-container {
        max-width: 1540px;
        padding-top: 1.5rem;
        padding-bottom: 2.5rem;
    }

    [data-testid="stSidebar"] {
        background: linear-gradient(180deg, #10243a 0%, #142f49 100%);
        border-right: 1px solid rgba(255,255,255,.08);
    }

    [data-testid="stSidebar"] [data-testid="stMarkdownContainer"],
    [data-testid="stSidebar"] [data-testid="stWidgetLabel"],
    [data-testid="stSidebar"] label,
    [data-testid="stSidebar"] p,
    [data-testid="stSidebar"] span {
        color: #e6eef7;
    }

    [data-testid="stSidebar"] [data-testid="stWidgetLabel"] p {
        color: #d7e4f0;
        font-weight: 600;
    }

    [data-testid="stSidebar"] input,
    [data-testid="stSidebar"] [data-baseweb="select"] > div {
        border-radius: 10px;
    }

    .hero-shell {
        position: relative;
        overflow: hidden;
        padding: 1.55rem 1.75rem;
        margin: 0 0 1.15rem 0;
        border-radius: 20px;
        color: #ffffff;
        background: linear-gradient(115deg, #10243a 0%, #17445a 58%, #087f80 100%);
        box-shadow: 0 14px 34px rgba(16,36,58,.16);
    }

    .hero-shell:after {
        content: '';
        position: absolute;
        width: 300px;
        height: 300px;
        right: -90px;
        top: -175px;
        border: 1px solid rgba(255,255,255,.18);
        border-radius: 50%;
        box-shadow: 0 0 0 28px rgba(255,255,255,.035), 0 0 0 58px rgba(255,255,255,.025);
        pointer-events: none;
    }

    .hero-kicker {
        color: #a9e8df;
        font-size: .70rem;
        font-weight: 800;
        letter-spacing: .16em;
        text-transform: uppercase;
        margin-bottom: .45rem;
    }

    .hero-title {
        color: #ffffff;
        font-size: clamp(1.65rem, 3vw, 2.25rem);
        line-height: 1.15;
        font-weight: 800;
        letter-spacing: -.035em;
        margin: 0;
    }

    .hero-subtitle {
        color: #d4e6ef;
        font-size: .94rem;
        margin-top: .5rem;
    }

    .hero-meta {
        display: flex;
        flex-wrap: wrap;
        gap: .55rem;
        margin-top: 1.1rem;
    }

    .hero-pill {
        display: inline-flex;
        align-items: center;
        padding: .35rem .7rem;
        color: #eafcf8;
        background: rgba(255,255,255,.12);
        border: 1px solid rgba(255,255,255,.19);
        border-radius: 999px;
        font-size: .72rem;
        font-weight: 650;
    }

    [data-testid="stMetric"] {
        background: linear-gradient(145deg, #ffffff 0%, #f9fbfe 100%);
        border: 1px solid var(--line);
        border-radius: 15px;
        padding: 15px 16px 13px 16px;
        box-shadow: 0 5px 16px rgba(21,48,75,.055);
        min-height: 108px;
    }

    [data-testid="stMetricLabel"] {
        color: #64748b;
        font-weight: 650;
        font-size: .79rem;
    }

    [data-testid="stMetricValue"] {
        color: #102b43;
        font-weight: 800;
        letter-spacing: -.025em;
    }

    [data-testid="stMetricDelta"] {
        font-weight: 650;
    }

    [data-testid="stTabs"] [role="tablist"] {
        gap: .35rem;
        border-bottom: 1px solid #dce5ef;
    }

    [data-testid="stTabs"] button[role="tab"] {
        border-radius: 11px 11px 0 0;
        padding: .7rem 1rem;
        font-weight: 700;
        color: #52657a;
    }

    [data-testid="stTabs"] button[role="tab"][aria-selected="true"] {
        color: #087f80;
        background: #e8f7f5;
    }

    [data-testid="stExpander"] {
        background: rgba(255,255,255,.88);
        border: 1px solid var(--line);
        border-radius: 13px;
        overflow: hidden;
    }

    [data-testid="stExpander"] summary {
        min-height: 44px;
        font-size: 1rem !important;
        font-weight: 750 !important;
        color: #17344e !important;
    }

    [data-testid="stExpander"] summary p {
        font-size: 1rem !important;
        font-weight: 750 !important;
        color: #17344e !important;
    }

    div[data-testid="stDataFrame"] {
        border: 1px solid var(--line);
        border-radius: 12px;
        overflow: hidden;
        background: #ffffff;
    }

    .stButton > button,
    [data-testid="stDownloadButton"] > button {
        border-radius: 10px;
        font-weight: 700;
        border: 1px solid #cbd9e6;
        transition: all .15s ease-in-out;
    }

    .stButton > button[kind="primary"] {
        color: #ffffff;
        background: linear-gradient(100deg, #087f80, #0f9d91);
        border: 0;
    }

    .stButton > button:hover,
    [data-testid="stDownloadButton"] > button:hover {
        border-color: #0f9d91;
        color: #087f80;
        box-shadow: 0 4px 12px rgba(15,157,145,.12);
    }

    [data-testid="stTextInput"] input,
    [data-testid="stTextArea"] textarea,
    [data-testid="stDateInput"] input {
        border-radius: 10px;
    }

    h2, h3 {
        color: #17344e;
        letter-spacing: -.02em;
    }

    [data-testid="stCaptionContainer"] {
        color: #718096;
    }

    @media (max-width: 700px) {
        .block-container { padding-left: 1rem; padding-right: 1rem; }
        .hero-shell { padding: 1.2rem; }
    }
    </style>
    """,
    unsafe_allow_html=True
)


session = get_active_session()

SC = "INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION"

CORTEX_SEMANTIC_VIEW = (
    "INSURANCEPOLICY_LIFECYCLE_DB.GOLD.SV_POLICY_ANALYTICS"
)


# =============================================================================
# ACCESS CONTROL
# =============================================================================

ACCESS = {
    "INSURANCE_ANALYST_USER": ["Underwriting"],
    "CLAIMS_ANALYST_USER": ["Claims"],
    "FRAUD_ANALYST_USER": ["Fraud"],

    "PROJECT_USER_4": [
        "Underwriting",
        "Claims",
        "Fraud"
    ],

    "PROJECT_USER_5": [
        "Underwriting",
        "Claims",
        "Fraud"
    ],

    "SHOYOHINATA": [
        "Underwriting",
        "Claims",
        "Fraud"
    ]
}


PERSONA = {
    "INSURANCE_ANALYST_USER": "Insurance Analyst",
    "CLAIMS_ANALYST_USER": "Claims Analyst",
    "FRAUD_ANALYST_USER": "Fraud Manager",
    "PROJECT_USER_4": "Data Engineer",
    "PROJECT_USER_5": "Data Engineer",
    "SHOYOHINATA": "Project User"
}


VIEWS_FOR = {
    "Underwriting": [
        "VW_UNDERWRITING_DASHBOARD"
    ],

    "Claims": [
        "VW_CLAIMS_DASHBOARD"
    ],

    "Fraud": [
        "VW_FRAUD_DASHBOARD",
        "VW_CLAIM_RISK_SCORES"
    ]
}


# =============================================================================
# BASIC HELPERS
# =============================================================================

_TABLE_RENDER_INDEX = 0


def show(df):
    """Display a table with per-table search, row limits and CSV export."""
    global _TABLE_RENDER_INDEX
    _TABLE_RENDER_INDEX += 1
    table_id = _TABLE_RENDER_INDEX

    if df is None:
        st.info("No records to display.")
        return

    if not isinstance(df, pd.DataFrame):
        df = pd.DataFrame(df)

    display_df = df.copy()

    if display_df.empty:
        st.info("No records match the current selection.")
        return

    search_col, rows_col, export_col = st.columns([2.4, 1, 1])

    with search_col:
        query = st.text_input(
            "Search records",
            key=f"enhanced_table_search_{table_id}",
            placeholder="Search across all columns..."
        )

    if query:
        matches = display_df.astype(str).apply(
            lambda column: column.str.contains(
                query,
                case=False,
                na=False,
                regex=False
            )
        )
        display_df = display_df[matches.any(axis=1)]

    with rows_col:
        row_choice = st.selectbox(
            "Rows to show",
            [10, 25, 50, 100, 250, 500, "All"],
            index=2,
            key=f"enhanced_table_rows_{table_id}"
        )

    row_limit = len(display_df) if row_choice == "All" else int(row_choice)
    visible_df = display_df.head(row_limit)

    with export_col:
        st.download_button(
            "⬇️ Export CSV",
            data=display_df.to_csv(index=False).encode("utf-8"),
            file_name=f"insurance_table_{table_id}.csv",
            mime="text/csv",
            key=f"enhanced_table_download_{table_id}"
        )

    st.caption(
        f"Showing {len(visible_df):,} of {len(display_df):,} matching records"
        + (f" · {len(df):,} total before search" if query else "")
    )

    try:
        st.dataframe(
            visible_df,
            use_container_width=True,
            hide_index=True,
            height=360
        )
    except TypeError:
        st.dataframe(
            visible_df.reset_index(drop=True),
            use_container_width=True
        )


def rerun():
    if hasattr(st, "rerun"):
        st.rerun()
    elif hasattr(st, "experimental_rerun"):
        st.experimental_rerun()


_CHART_RENDER_INDEX = 0
CHART_HEIGHT = 320


def _chart_export(data, chart_type):
    """Offer the data behind each chart as a downloadable CSV."""
    global _CHART_RENDER_INDEX
    _CHART_RENDER_INDEX += 1
    chart_id = _CHART_RENDER_INDEX

    try:
        if isinstance(data, pd.Series):
            export_df = data.to_frame()
        elif isinstance(data, pd.DataFrame):
            export_df = data.copy()
        else:
            export_df = pd.DataFrame(data)

        if export_df.empty:
            return

        st.download_button(
            "⬇️ Download chart data",
            data=export_df.to_csv(index=True).encode("utf-8"),
            file_name=f"{chart_type}_chart_data_{chart_id}.csv",
            mime="text/csv",
            key=f"enhanced_chart_download_{chart_id}"
        )
    except Exception:
        # Chart rendering should not fail just because an export cannot be built.
        pass


def bar(data, empty_msg="No data for the current selection."):
    if data is None or len(data) == 0:
        st.info(empty_msg)
    else:
        try:
            st.bar_chart(data, height=CHART_HEIGHT)
        except TypeError:
            st.bar_chart(data)
        _chart_export(data, "bar")


def line(data, empty_msg="No data for the current selection."):
    if data is None or len(data) == 0:
        st.info(empty_msg)
    else:
        try:
            st.line_chart(data, height=CHART_HEIGHT)
        except TypeError:
            st.line_chart(data)
        _chart_export(data, "line")


def up(series):
    return (
        series
        .fillna("")
        .astype(str)
        .str.strip()
        .str.upper()
    )


def div(a, b):
    try:
        a = float(a)
    except Exception:
        a = 0.0

    try:
        b = float(b)
    except Exception:
        b = 0.0

    if pd.isna(a):
        a = 0.0

    if pd.isna(b):
        b = 0.0

    if b == 0:
        return 0.0

    return a / b


def pct(n, d):
    if d is None:
        return "n/a"

    try:
        d = float(d)
    except Exception:
        return "n/a"

    if d == 0:
        return "n/a"

    value = 100 * div(n, d)

    return f"{value:.1f}%"


def inr(value):
    try:
        value = float(value)
    except Exception:
        value = 0.0

    if pd.isna(value):
        value = 0.0

    if abs(value) >= 10000000:
        return f"₹{value / 10000000:,.2f} Cr"

    if abs(value) >= 100000:
        return f"₹{value / 100000:,.2f} L"

    return f"₹{value:,.0f}"


def sql_list(values):
    result = []

    for value in values:
        value = str(value).replace("'", "''")
        result.append("'" + value + "'")

    return ", ".join(result)


def monthly_count(df, date_col, id_col):

    if date_col not in df.columns:
        return pd.Series(dtype="int64")

    if id_col not in df.columns:
        return pd.Series(dtype="int64")

    temp = df.dropna(subset=[date_col])

    if temp.empty:
        return pd.Series(dtype="int64")

    return (
        temp
        .set_index(date_col)
        .resample("MS")[id_col]
        .count()
    )


# =============================================================================
# USER
# =============================================================================

def viewer_name():

    try:
        if hasattr(st, "user"):

            user_obj = st.user

            try:
                name = user_obj.get("user_name")

                if not name:
                    name = user_obj.get("login_name")

                if name:
                    return str(name).upper()

            except Exception:
                pass

    except Exception:
        pass


    try:
        if hasattr(st, "experimental_user"):

            user_obj = st.experimental_user

            try:
                name = user_obj.get("user_name")

                if not name:
                    name = user_obj.get("login_name")

                if name:
                    return str(name).upper()

            except Exception:
                pass

    except Exception:
        pass


    try:
        result = session.sql(
            "SELECT CURRENT_USER()"
        ).collect()

        if result:
            return str(result[0][0]).upper()

    except Exception:
        pass


    return ""


# =============================================================================
# DATA ACCESS
# =============================================================================

@st.cache_data(
    ttl=600,
    show_spinner="Loading secure data..."
)
def load(view):

    df = session.table(
        f"{SC}.{view}"
    ).to_pandas()

    df.columns = [
        str(column).upper()
        for column in df.columns
    ]

    for column in df.columns:

        if column.endswith("_DATE"):

            df[column] = pd.to_datetime(
                df[column],
                errors="coerce"
            )

        elif column.endswith("_TIMESTAMP"):

            df[column] = (
                pd.to_datetime(
                    df[column],
                    errors="coerce",
                    utc=True
                )
                .dt
                .tz_localize(None)
            )

        elif df[column].dtype == object:

            values = df[column].dropna()

            if len(values) > 0:

                try:

                    numeric_values = values.map(
                        lambda x: isinstance(
                            x,
                            (
                                Decimal,
                                int,
                                float
                            )
                        )
                    )

                    if numeric_values.all():

                        df[column] = pd.to_numeric(
                            df[column],
                            errors="coerce"
                        )

                except Exception:
                    pass

    return df


@st.cache_data(ttl=600)
def sql_value(sql):

    result = session.sql(sql).collect()

    if not result:
        return 0.0

    value = result[0][0]

    if value is None:
        return 0.0

    return float(value)


def apply_filters(df, date_column):

    output = df.copy()

    if "REGION" in output.columns:

        output = output[
            output["REGION"].isin(regions)
        ]

    if date_column in output.columns:

        dates = output[date_column]

        output = output[
            dates.isna()
            |
            dates.between(
                pd.Timestamp(d_from),
                pd.Timestamp(d_to)
            )
        ]

    return output


def reconcile(rows):

    df = pd.DataFrame(
        rows,
        columns=[
            "Measure",
            "Dashboard",
            "Snowflake"
        ]
    )

    df["Dashboard"] = (
        df["Dashboard"]
        .astype(float)
        .round(2)
    )

    df["Snowflake"] = (
        df["Snowflake"]
        .astype(float)
        .round(2)
    )

    result = []

    for dashboard_value, snowflake_value in zip(
        df["Dashboard"],
        df["Snowflake"]
    ):

        if abs(
            dashboard_value - snowflake_value
        ) < 0.01:

            result.append("✅ MATCH")

        else:

            result.append("❌ MISMATCH")

    df["Result"] = result

    show(df)


# =============================================================================
# SIDEBAR
# =============================================================================

me = viewer_name()

allowed = ACCESS.get(
    me,
    []
)


st.sidebar.markdown(
    """
    <div style="padding:.8rem .9rem; margin:.15rem 0 .75rem 0; background:rgba(255,255,255,.08); border:1px solid rgba(255,255,255,.12); border-radius:14px;">
      <div style="font-size:.68rem; letter-spacing:.14em; color:#a9e8df; font-weight:800;">
        INSURANCE INTELLIGENCE
      </div>
      <div style="font-size:1.12rem; color:#ffffff; font-weight:800; margin-top:.25rem;">
        🛡️ Lifecycle Suite
      </div>
      <div style="font-size:.75rem; color:#c7d6e4; margin-top:.2rem;">
        Underwriting · Claims · Fraud
      </div>
    </div>
    """,
    unsafe_allow_html=True
)

st.sidebar.title(
    "Workspace filters"
)


st.sidebar.caption(
    f"Signed in as **{me or 'unknown'}** · "
    f"{PERSONA.get(me, 'Unmapped user')}"
)


if not allowed:

    st.error(
        f"Access denied: user {me or '(unknown)'} "
        "is not mapped to any dashboard."
    )

    st.stop()


# =============================================================================
# REGIONS
# =============================================================================

views_needed = {
    "VW_KPI_SUMMARY"
}


for dashboard in allowed:

    for view in VIEWS_FOR[dashboard]:

        views_needed.add(view)


region_values = set()


for view in sorted(views_needed):

    try:

        temp = load(view)

        if "REGION" in temp.columns:

            region_values.update(
                temp["REGION"]
                .dropna()
                .astype(str)
                .unique()
            )

    except Exception:
        pass


# Hide UNKNOWN and blank values from the region dropdown.
all_regions = sorted(
    region
    for region in region_values
    if str(region).strip() != ""
    and str(region).strip().upper() != "UNKNOWN"
)


regions = st.sidebar.multiselect(
    "Region",
    all_regions,
    default=all_regions
)


picked = st.sidebar.date_input(
    "Date range",
    value=(
        date(2021, 1, 1),
        date.today()
    )
)


chart_size = st.sidebar.selectbox(
    "Chart size",
    ["Compact", "Standard", "Expanded"],
    index=1,
    help="Adjust the height of charts throughout the dashboard."
)

CHART_HEIGHT = {
    "Compact": 230,
    "Standard": 320,
    "Expanded": 430
}[chart_size]


if isinstance(picked, (list, tuple)):

    if len(picked) >= 1:
        d_from = picked[0]
    else:
        d_from = date(2000, 1, 1)

    if len(picked) >= 2:
        d_to = picked[1]
    else:
        d_to = date.today()

else:

    d_from = picked
    d_to = date.today()


if st.sidebar.button(
    "🔄 Refresh data"
):

    st.cache_data.clear()

    rerun()


st.sidebar.caption(
    "Customer PII is never shown in this app."
)


if not regions:

    st.warning(
        "Select at least one region."
    )

    st.stop()


# =============================================================================
# KPI SCORECARD
# =============================================================================

def kpi_scorecard():

    k = load(
        "VW_KPI_SUMMARY"
    )

    k = k[
        k["REGION"].isin(regions)
    ].copy()

    s = k.sum(
        numeric_only=True
    )


    st.caption(
        "Business KPI scorecard · "
        "aggregated data · no customer PII"
    )


    # -------------------------------------------------------------------------
    # KPI CARDS - 4 + 3 + 3 + 2 LAYOUT
    # All twelve KPIs remain separate. The two largest financial KPIs are last.
    # -------------------------------------------------------------------------

    active_policies = int(
        s.get(
            "ACTIVE_POLICIES",
            0
        )
    )

    active_sum_insured = s.get(
        "ACTIVE_SUM_INSURED",
        0
    )

    premium_collected = s.get(
        "PREMIUM_COLLECTED",
        0
    )

    total_claims = s.get(
        "TOTAL_CLAIMS",
        0
    )

    total_policies = s.get(
        "TOTAL_POLICIES",
        0
    )

    claim_frequency = (
        1000
        * div(
            total_claims,
            total_policies
        )
    )

    total_claim_amount = s.get(
        "TOTAL_CLAIM_AMOUNT",
        0
    )

    average_claim = div(
        total_claim_amount,
        total_claims
    )

    approved_claims = s.get(
        "APPROVED_CLAIMS",
        0
    )

    approval_ratio = pct(
        approved_claims,
        total_claims
    )

    tat_days_sum = s.get(
        "TAT_DAYS_SUM",
        0
    )

    settled_claims = s.get(
        "SETTLED_CLAIMS",
        0
    )

    settlement_tat = div(
        tat_days_sum,
        settled_claims
    )

    net_settlement = s.get(
        "NET_SETTLEMENT_AMOUNT",
        0
    )

    loss_ratio = pct(
        net_settlement,
        premium_collected
    )

    open_investigations = int(
        s.get(
            "OPEN_INVESTIGATIONS",
            0
        )
    )

    fraud_cases = s.get(
        "FRAUD_CASES",
        0
    )

    confirmed_fraud_cases = s.get(
        "CONFIRMED_FRAUD_CASES",
        0
    )

    confirmed_fraud_rate = pct(
        confirmed_fraud_cases,
        fraud_cases
    )

    high_risk_claims = int(
        s.get(
            "HIGH_RISK_CLAIMS",
            0
        )
    )


    # Row 1: four individual KPIs
    r1 = st.columns(4)

    r1[0].metric(
        "① Active policies",
        f"{active_policies:,}"
    )

    r1[1].metric(
        "③ Claims per 1,000 policies",
        f"{claim_frequency:.1f}",
        help="Total claims ÷ total policies × 1,000"
    )

    r1[2].metric(
        "③ Average claim",
        inr(average_claim)
    )

    r1[3].metric(
        "④ Approval ratio",
        approval_ratio,
        help="Approved + Settled claims ÷ all claims"
    )


    # Row 2: three individual KPIs
    r2 = st.columns(3)

    r2[0].metric(
        "⑤ Settlement TAT",
        f"{settlement_tat:.1f} days",
        help="Claim registration → first settlement"
    )

    r2[1].metric(
        "⑧ Open investigations",
        f"{open_investigations:,}"
    )

    r2[2].metric(
        "⑨ Confirmed fraud rate",
        confirmed_fraud_rate
    )


    # Row 3: three individual KPIs
    r3 = st.columns(3)

    r3[0].metric(
        "⑩ High-risk claims",
        f"{high_risk_claims:,}",
        help="Snowpark RISK_CATEGORY = HIGH"
    )

    r3[1].metric(
        "⑦ Loss ratio proxy",
        loss_ratio,
        help="Net settlement ÷ premium collected"
    )

    r3[2].metric(
        "② Premium collected",
        inr(premium_collected),
        help="Sum of PAID premium payments"
    )


    # Row 4: two largest financial KPIs, each taking half the row
    r4 = st.columns(2)

    r4[0].metric(
        "① Active sum insured",
        inr(active_sum_insured)
    )

    r4[1].metric(
        "⑥ Net settlement",
        inr(net_settlement)
    )


    # -------------------------------------------------------------------------
    # REGION TABLE
    # -------------------------------------------------------------------------

    st.subheader(
        "KPIs by region"
    )


    if k.empty:

        st.info(
            "No KPI data for selected regions."
        )

        return


    denominator_claims = k[
        "TOTAL_CLAIMS"
    ].where(
        k["TOTAL_CLAIMS"] != 0
    )


    denominator_policies = k[
        "TOTAL_POLICIES"
    ].where(
        k["TOTAL_POLICIES"] != 0
    )


    denominator_settled = k[
        "SETTLED_CLAIMS"
    ].where(
        k["SETTLED_CLAIMS"] != 0
    )


    denominator_premium = k[
        "PREMIUM_COLLECTED"
    ].where(
        k["PREMIUM_COLLECTED"] != 0
    )


    denominator_fraud = k[
        "FRAUD_CASES"
    ].where(
        k["FRAUD_CASES"] != 0
    )


    k["CLAIMS_PER_1000_POLICIES"] = (
        1000
        * k["TOTAL_CLAIMS"]
        / denominator_policies
    ).round(1)


    k["AVG_CLAIM"] = (
        k["TOTAL_CLAIM_AMOUNT"]
        / denominator_claims
    ).round(0)


    k["APPROVAL_RATIO_%"] = (
        100
        * k["APPROVED_CLAIMS"]
        / denominator_claims
    ).round(1)


    k["SETTLEMENT_TAT_DAYS"] = (
        k["TAT_DAYS_SUM"]
        / denominator_settled
    ).round(1)


    k["LOSS_RATIO_%"] = (
        100
        * k["NET_SETTLEMENT_AMOUNT"]
        / denominator_premium
    ).round(1)


    k["CONFIRMED_FRAUD_%"] = (
        100
        * k["CONFIRMED_FRAUD_CASES"]
        / denominator_fraud
    ).round(1)


    display_columns = [
        "REGION",
        "ACTIVE_POLICIES",
        "ACTIVE_SUM_INSURED",
        "PREMIUM_COLLECTED",
        "CLAIMS_PER_1000_POLICIES",
        "AVG_CLAIM",
        "APPROVAL_RATIO_%",
        "SETTLEMENT_TAT_DAYS",
        "NET_SETTLEMENT_AMOUNT",
        "LOSS_RATIO_%",
        "OPEN_INVESTIGATIONS",
        "CONFIRMED_FRAUD_%",
        "HIGH_RISK_CLAIMS"
    ]


    show(
        k[ display_columns].sort_values("REGION")
    )


    # -------------------------------------------------------------------------
    # CHARTS
    # -------------------------------------------------------------------------

    c1, c2 = st.columns(2)


    with c1:

        st.subheader(
            "Loss ratio proxy by region (%)"
        )

        chart_data = (
            k
            .set_index("REGION")
            ["LOSS_RATIO_%"]
            .dropna()
        )

        bar(chart_data)


    with c2:

        st.subheader(
            "Approval ratio by region (%)"
        )

        chart_data = (
            k
            .set_index("REGION")
            ["APPROVAL_RATIO_%"]
            .dropna()
        )

        bar(chart_data)




# =============================================================================
# UNDERWRITING
# =============================================================================

def underwriting():

    raw = load(
        "VW_UNDERWRITING_DASHBOARD"
    )


    df = apply_filters(
        raw,
        "POLICY_START_DATE"
    )


    insurance_types = sorted(
        df["INSURANCE_TYPE"]
        .dropna()
        .unique()
    )


    selected_types = st.multiselect(
        "Insurance type",
        insurance_types,
        key="uw_types"
    )


    if selected_types:

        df = df[
            df["INSURANCE_TYPE"]
            .isin(selected_types)
        ]


    status = up(
        df["POLICY_STATUS"]
    )


    active = df[
        status == "ACTIVE"
    ]


    # -------------------------------------------------------------------------
    # KPIs - 3 + 2 LAYOUT
    # -------------------------------------------------------------------------

    k = st.columns(3)

    k[0].metric(
        "Active policies",
        f"{len(active):,}"
    )

    k[1].metric(
        "Active sum insured",
        inr(
            active["SUM_INSURED"].sum()
        )
    )

    k[2].metric(
        "Premium collected",
        inr(
            df["PREMIUM_COLLECTED"].sum()
        )
    )

    lapse_count = (
        status == "LAPSED"
    ).sum()

    k2 = st.columns(2)

    k2[0].metric(
        "Lapse rate",
        pct(
            lapse_count,
            len(df)
        )
    )

    k2[1].metric(
        "Reversed payments",
        f"{int(df['REVERSED_PAYMENTS'].sum()):,}"
    )


    # -------------------------------------------------------------------------
    # CHARTS
    # -------------------------------------------------------------------------

    c1, c2 = st.columns(2)

    with c1:

        st.subheader(
            "New policies per month"
        )

        data = monthly_count(
            df,
            "POLICY_START_DATE",
            "POLICY_ID"
        )

        line(data)


    with c2:

        st.subheader(
            "Premium collected by insurance type"
        )

        data = (
            df
            .groupby("INSURANCE_TYPE")
            ["PREMIUM_COLLECTED"]
            .sum()
        )

        bar(data)


    c3, c4 = st.columns(2)

    with c3:

        st.subheader(
            "Policy status by underwriting risk band"
        )

        if df.empty:

            st.info(
                "No data for current selection."
            )

        else:

            data = df.pivot_table(
                index="UNDERWRITING_RISK_BAND",
                columns="POLICY_STATUS",
                values="POLICY_ID",
                aggfunc="count",
                fill_value=0
            )

            bar(data)


    with c4:

        st.subheader(
            "Active sum insured by region"
        )

        data = (
            active
            .groupby("REGION")
            ["SUM_INSURED"]
            .sum()
        )

        bar(data)


    # -------------------------------------------------------------------------
    # EXPIRING POLICIES
    # -------------------------------------------------------------------------

    st.subheader(
        "⏳ Active policies expiring in next 90 days"
    )


    today = pd.Timestamp(
        date.today()
    )


    soon = active[
        active["POLICY_EXPIRY_DATE"].between(
            today,
            today + pd.Timedelta(days=90)
        )
    ]


    show(
        soon[
            [
                "POLICY_ID",
                "PRODUCT_NAME",
                "INSURANCE_TYPE",
                "REGION",
                "POLICY_EXPIRY_DATE",
                "SUM_INSURED",
                "PREMIUM_AMOUNT",
                "UNDERWRITING_RISK_BAND"
            ]
        ]
        .sort_values(
            "POLICY_EXPIRY_DATE"
        )
    )


    # -------------------------------------------------------------------------
    # HIGH RISK CUSTOMERS
    # -------------------------------------------------------------------------

    st.subheader(
        "⚠️ High-risk customers holding active policies"
    )


    high_risk = active[
        up(
            active["CUSTOMER_RISK_CATEGORY"]
        ) == "HIGH"
    ]


    show(
        high_risk[
            [
                "POLICY_ID",
                "CUSTOMER_ID",
                "INSURANCE_TYPE",
                "REGION",
                "SUM_INSURED",
                "UNDERWRITING_RISK_BAND",
                "PREMIUM_COLLECTED"
            ]
        ]
    )




# =============================================================================
# CLAIMS
# =============================================================================

def claims():

    raw = load(
        "VW_CLAIMS_DASHBOARD"
    )


    df = apply_filters(
        raw,
        "CLAIM_REGISTRATION_DATE"
    )


    claim_types = sorted(
        df["CLAIM_TYPE"]
        .dropna()
        .unique()
    )


    selected_types = st.multiselect(
        "Claim type",
        claim_types,
        key="cl_types"
    )


    if selected_types:

        df = df[
            df["CLAIM_TYPE"]
            .isin(selected_types)
        ]


    status = up(
        df["CLAIM_STATUS"]
    )


    approved = status.isin(
        [
            "APPROVED",
            "SETTLED"
        ]
    )


    settled = df[
        df["SETTLEMENT_COUNT"] > 0
    ]


    kp = load(
        "VW_KPI_SUMMARY"
    )


    kp = kp[
        kp["REGION"].isin(regions)
    ]


    # -------------------------------------------------------------------------
    # KPIs - 3 + 3 LAYOUT
    # -------------------------------------------------------------------------

    k = st.columns(3)

    k[0].metric(
        "Claims",
        f"{len(df):,}"
    )

    loss_ratio = pct(
        kp["NET_SETTLEMENT_AMOUNT"].sum(),
        kp["PREMIUM_COLLECTED"].sum()
    )

    k[1].metric(
        "Loss ratio proxy",
        loss_ratio
    )

    average_claim = (
        df["CLAIM_AMOUNT"].mean()
        if len(df)
        else 0
    )

    k[2].metric(
        "Average claim",
        inr(average_claim)
    )

    if len(settled):

        avg_tat = (
            settled["SETTLEMENT_TAT_DAYS"]
            .mean()
        )

        tat_text = f"{avg_tat:.1f} days"

    else:

        tat_text = "n/a"

    k2 = st.columns(3)

    k2[0].metric(
        "Approval ratio",
        pct(
            approved.sum(),
            len(df)
        )
    )

    k2[1].metric(
        "Avg settlement TAT",
        tat_text
    )

    k2[2].metric(
        "Net settled",
        inr(
            df["NET_SETTLED"].sum()
        )
    )


    # -------------------------------------------------------------------------
    # CHARTS
    # -------------------------------------------------------------------------

    c1, c2 = st.columns(2)


    with c1:

        st.subheader(
            "Claims registered per month"
        )

        data = monthly_count(
            df,
            "CLAIM_REGISTRATION_DATE",
            "CLAIM_ID"
        )

        line(data)


    with c2:

        st.subheader(
            "Claim status mix"
        )

        data = (
            df
            .groupby("CLAIM_STATUS")
            ["CLAIM_ID"]
            .count()
        )

        bar(data)


    c3, c4 = st.columns(2)


    with c3:

        st.subheader(
            "Claim vs approved amount by claim type"
        )

        data = (
            df
            .groupby("CLAIM_TYPE")
            [
                [
                    "CLAIM_AMOUNT",
                    "APPROVED_AMOUNT"
                ]
            ]
            .sum()
        )

        bar(data)


    with c4:

        st.subheader(
            "Average settlement TAT by insurance type"
        )

        data = (
            settled
            .groupby("INSURANCE_TYPE")
            ["SETTLEMENT_TAT_DAYS"]
            .mean()
            .dropna()
        )

        bar(data)


    # -------------------------------------------------------------------------
    # SETTLEMENT EXCEPTIONS
    # -------------------------------------------------------------------------

    st.subheader(
        "🚩 Settlement exceptions"
    )


    cols = [
        "CLAIM_ID",
        "POLICY_ID",
        "CLAIM_TYPE",
        "REGION",
        "CLAIM_STATUS",
        "CLAIM_AMOUNT",
        "APPROVED_AMOUNT",
        "GROSS_SETTLED",
        "NET_SETTLED",
        "SETTLEMENT_TAT_DAYS"
    ]


    tab1, tab2, tab3 = st.tabs(
        [
            "Settled without approval",
            "Approved but not settled",
            "Net amount mismatch"
        ]
    )


    with tab1:

        exception_df = df[
            (df["SETTLEMENT_COUNT"] > 0)
            &
            status.isin(
                [
                    "REJECTED",
                    "UNDER REVIEW"
                ]
            )
        ]


        st.caption(
            f"{len(exception_df):,} claims paid while "
            "Rejected / Under Review"
        )


        show(
            exception_df[cols]
        )


    with tab2:

        exception_df = df[
            (df["SETTLEMENT_COUNT"] == 0)
            &
            (status == "APPROVED")
        ]


        st.caption(
            f"{len(exception_df):,} approved claims "
            "with no settlement yet"
        )


        show(
            exception_df[cols]
        )


    with tab3:

        exception_df = df[
            df["NET_MISMATCH_COUNT"] > 0
        ]


        st.caption(
            f"{len(exception_df):,} claims where "
            "net ≠ gross − deductible − recovery"
        )


        show(
            exception_df[cols]
        )




# =============================================================================
# FRAUD
# =============================================================================

def fraud():

    fraud_raw = load(
        "VW_FRAUD_DASHBOARD"
    )


    risk_raw = load(
        "VW_CLAIM_RISK_SCORES"
    )


    fraud_df = apply_filters(
        fraud_raw,
        "INVESTIGATION_START_DATE"
    )


    risk_df = apply_filters(
        risk_raw,
        "CLAIM_REGISTRATION_DATE"
    )


    is_open = (
        fraud_df["INVESTIGATION_END_DATE"].isna()
        |
        (
            up(
                fraud_df["INVESTIGATION_STATUS"]
            ) == "OPEN"
        )
    )


    confirmed = (
        up(
            fraud_df["INVESTIGATION_OUTCOME"]
        )
        .str.contains(
            "CONFIRMED",
            na=False
        )
    )


    days_open = (
        pd.Timestamp(date.today())
        -
        fraud_df["INVESTIGATION_START_DATE"]
    ).dt.days


    high_risk = risk_df[
        up(
            risk_df["RISK_CATEGORY"]
        ) == "HIGH"
    ]


    # -------------------------------------------------------------------------
    # KPIs - 3 + 2 LAYOUT
    # -------------------------------------------------------------------------

    k = st.columns(3)

    k[0].metric(
        "Fraud cases",
        f"{len(fraud_df):,}"
    )

    k[1].metric(
        "Open investigations",
        f"{int(is_open.sum()):,}"
    )

    k[2].metric(
        "Confirmed fraud rate",
        pct(
            confirmed.sum(),
            len(fraud_df)
        )
    )

    avg_open = days_open[
        is_open
    ].mean()

    if pd.notna(avg_open):
        avg_open_text = f"{avg_open:.0f}"
    else:
        avg_open_text = "0"

    k2 = st.columns(2)

    k2[0].metric(
        "High-risk claims",
        f"{len(high_risk):,}"
    )

    k2[1].metric(
        "Avg days open",
        avg_open_text
    )


    # -------------------------------------------------------------------------
    # CHARTS
    # -------------------------------------------------------------------------

    c1, c2 = st.columns(2)


    with c1:

        st.subheader(
            "Claim risk category mix"
        )

        data = (
            risk_df
            .groupby("RISK_CATEGORY")
            ["CLAIM_ID"]
            .count()
        )

        bar(data)


    with c2:

        st.subheader(
            "Investigation outcomes"
        )

        data = (
            fraud_df
            .groupby("INVESTIGATION_OUTCOME")
            ["FRAUD_CASE_ID"]
            .count()
        )

        bar(data)


    c3, c4 = st.columns(2)


    with c3:

        st.subheader(
            "Top trigger reasons"
        )

        data = (
            fraud_df
            .groupby("TRIGGER_REASON")
            ["FRAUD_CASE_ID"]
            .count()
            .sort_values(
                ascending=False
            )
            .head(10)
        )

        bar(data)


    with c4:

        st.subheader(
            "Open cases per investigator"
        )

        data = (
            fraud_df[is_open]
            .groupby("INVESTIGATOR_ID")
            ["FRAUD_CASE_ID"]
            .count()
        )

        bar(data)


    # -------------------------------------------------------------------------
    # HIGH RISK EXPLANATION
    # -------------------------------------------------------------------------

    st.subheader(
        "🔍 Why is this claim high risk?"
    )


    if high_risk.empty:

        st.info(
            "No HIGH risk claims in current selection."
        )

    else:

        top = high_risk.sort_values(
            "TOTAL_RISK_SCORE",
            ascending=False
        )


        claim_options = (
            top["CLAIM_ID"]
            .tolist()
        )


        selected_claim = st.selectbox(
            "Select a HIGH risk claim",
            claim_options,
            key="fraud_claim_select"
        )


        selected = top[
            top["CLAIM_ID"] == selected_claim
        ].iloc[0]


        a, b = st.columns(
            [2, 1]
        )


        with a:

            scores = pd.DataFrame(
                {
                    "Score": [
                        selected["CLAIM_RISK_SCORE"],
                        selected["CUSTOMER_RISK_SCORE"],
                        selected["POLICY_RISK_SCORE"],
                        selected["FRAUD_HISTORY_SCORE"]
                    ]
                },
                index=[
                    "Claim",
                    "Customer",
                    "Policy",
                    "Fraud history"
                ]
            )


            bar(scores)


        with b:

            st.metric(
                "Total risk score",
                int(
                    selected["TOTAL_RISK_SCORE"]
                )
            )


            st.write(
                "**Claim type:** "
                + str(
                    selected["CLAIM_TYPE"]
                )
            )


            st.write(
                "**Claim amount:** "
                + inr(
                    selected["CLAIM_AMOUNT"]
                )
            )


            st.write(
                "**Status:** "
                + str(
                    selected["CLAIM_STATUS"]
                )
            )


            st.caption(
                "Scored at "
                + str(
                    selected["SCORING_TIMESTAMP"]
                )
            )


        show(
            top[
                [
                    "CLAIM_ID",
                    "POLICY_ID",
                    "REGION",
                    "CLAIM_TYPE",
                    "CLAIM_AMOUNT",
                    "CLAIM_STATUS",
                    "TOTAL_RISK_SCORE"
                ]
            ]
        )


    # -------------------------------------------------------------------------
    # AGED INVESTIGATIONS
    # -------------------------------------------------------------------------

    st.subheader(
        "⏰ Open investigations older than 30 days"
    )


    aged = (
        fraud_df[
            is_open
            &
            (days_open > 30)
        ]
        .assign(
            DAYS_OPEN=days_open
        )
    )


    show(
        aged[
            [
                "FRAUD_CASE_ID",
                "CLAIM_ID",
                "REGION",
                "SOURCE_FRAUD_SCORE",
                "TRIGGER_REASON",
                "INVESTIGATOR_ID",
                "INVESTIGATION_START_DATE",
                "DAYS_OPEN"
            ]
        ]
        .sort_values(
            "DAYS_OPEN",
            ascending=False
        )
    )




# =============================================================================
# FRAUD NETWORK
# =============================================================================

def fraud_network():

    risk = load("VW_FRAUD_NETWORK_RISK")
    links = load("VW_FRAUD_LINKS")

    risk = risk[
        risk["REGION"].isin(regions)
    ]

    k = st.columns(4)

    k[0].metric(
        "Linked customers",
        f"{len(risk):,}"
    )

    k[1].metric(
        "HIGH network risk",
        int(
            (risk["NETWORK_RISK"] == "HIGH").sum()
        )
    )

    k[2].metric(
        "MEDIUM network risk",
        int(
            (risk["NETWORK_RISK"] == "MEDIUM").sum()
        )
    )

    k[3].metric(
        "Links found",
        f"{len(links):,}"
    )


    c1, c2 = st.columns(2)

    with c1:

        st.subheader("Links by type")

        bar(
            links.groupby("LINK_TYPE")["CUSTOMER_A"].count()
        )

    with c2:

        st.subheader("Network risk mix")

        bar(
            risk.groupby("NETWORK_RISK")["CUSTOMER_ID"].count()
        )


    st.subheader(
        "🚩 Most connected to fraud"
    )

    top = risk.sort_values(
        [
            "LINKED_CONFIRMED_FRAUD",
            "LINKED_WITH_FRAUD_CASE",
            "LINKED_CUSTOMERS"
        ],
        ascending=False
    )

    show(
        top.head(50)
    )

    if top.empty:

        st.info(
            "No linked customers in the selected regions."
        )

        return


    st.subheader(
        "🕸️ Explore a customer's network"
    )

    pick = st.selectbox(
        "Customer",
        top["CUSTOMER_ID"].head(200).tolist(),
        key="net_pick"
    )

    direct = links[
        (links["CUSTOMER_A"] == pick)
        |
        (links["CUSTOMER_B"] == pick)
    ]

    nodes = (
        set(direct["CUSTOMER_A"])
        |
        set(direct["CUSTOMER_B"])
    )

    edges = links[
        links["CUSTOMER_A"].isin(nodes)
        &
        links["CUSTOMER_B"].isin(nodes)
    ]

    flags = risk.set_index("CUSTOMER_ID")

    dot = [
        "graph G {",
        "layout=neato; overlap=false;",
        "node [shape=circle style=filled fontname=Helvetica fontsize=9];"
    ]

    for n in nodes:

        conf = (
            n in flags.index
            and flags.at[n, "OWN_CONFIRMED"] > 0
        )

        case = (
            n in flags.index
            and flags.at[n, "OWN_FRAUD_CASES"] > 0
        )

        color = (
            "#E05C5C"
            if conf
            else "#F2A541"
            if case
            else "#A7C7E7"
        )

        width = (
            "penwidth=3"
            if n == pick
            else ""
        )

        dot.append(
            f'"{n}" [fillcolor="{color}" {width}];'
        )

    for _, e in edges.iterrows():

        dot.append(
            f'"{e.CUSTOMER_A}" -- "{e.CUSTOMER_B}" '
            f'[label="{e.LINK_TYPE}" fontsize=7];'
        )

    dot.append("}")

    st.graphviz_chart(
        "\n".join(dot),
        use_container_width=True
    )

    st.caption(
        "🔴 confirmed fraud · 🟠 has fraud case · "
        "🔵 no fraud case · thick border = selected"
    )


# =============================================================================
# CORTEX ANALYST
# =============================================================================

def ask_cortex_analyst(question):

    request_body = {
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": question
                    }
                ]
            }
        ],
        "semantic_view": CORTEX_SEMANTIC_VIEW
    }


    response = _snowflake.send_snow_api_request(
        "POST",
        "/api/v2/cortex/analyst/message",
        {},
        {},
        request_body,
        None
    )


    status_code = response.get(
        "status",
        500
    )


    if status_code >= 400:

        error_message = response.get(
            "content",
            "Unknown Cortex Analyst error"
        )

        raise Exception(
            f"Cortex Analyst error {status_code}: "
            f"{error_message}"
        )


    content = response.get(
        "content",
        ""
    )


    if isinstance(content, str):

        try:
            return json.loads(content)

        except Exception:

            return {
                "raw": content
            }


    return content


def find_sql_and_text(data):

    sql_list_found = []
    text_list_found = []


    def walk(value):

        if isinstance(value, dict):

            for key, child in value.items():

                key_lower = str(
                    key
                ).lower()


                if key_lower in (
                    "text",
                    "message"
                ):

                    if isinstance(
                        child,
                        str
                    ):

                        text_list_found.append(
                            child
                        )


                if key_lower in (
                    "sql",
                    "query",
                    "statement"
                ):

                    if isinstance(
                        child,
                        str
                    ):

                        cleaned = child.strip()


                        upper_sql = (
                            cleaned.upper()
                        )


                        if (
                            upper_sql.startswith(
                                "SELECT"
                            )
                            or
                            upper_sql.startswith(
                                "WITH"
                            )
                        ):

                            sql_list_found.append(
                                cleaned
                            )


                walk(child)


        elif isinstance(value, list):

            for item in value:
                walk(item)


    walk(data)


    unique_sql = []

    for item in sql_list_found:

        if item not in unique_sql:
            unique_sql.append(item)


    unique_text = []

    for item in text_list_found:

        if item not in unique_text:
            unique_text.append(item)


    return unique_text, unique_sql


def cortex_tab():

    st.subheader(
        "🤖 Ask Cortex Analyst"
    )


    st.caption(
        "Ask questions about policies, premiums, "
        "claims, settlements and fraud."
    )


    st.info(
        "Example questions:\n"
        "- Which region has the highest premium collected?\n"
        "- What is the average claim amount by claim type?\n"
        "- Show me high-risk claims.\n"
        "- Which insurance type has the highest claim amount?"
    )


    question = st.text_area(
        "Ask your question",
        placeholder=(
            "Example: Show total claims by region"
        ),
        height=100,
        key="cortex_question"
    )


    ask = st.button(
        "🚀 Ask Cortex Analyst",
        type="primary"
    )


    if not ask:
        return


    if not question.strip():

        st.warning(
            "Please enter a question."
        )

        return


    with st.spinner(
        "Cortex Analyst is generating the answer..."
    ):

        try:

            response = ask_cortex_analyst(
                question.strip()
            )

        except Exception as error:

            st.error(
                "Cortex Analyst failed."
            )

            st.exception(error)

            return


    texts, sql_statements = find_sql_and_text(
        response
    )


    if texts:

        st.subheader(
            "💬 Cortex response"
        )

        for text_value in texts:

            if text_value.strip():

                st.write(
                    text_value
                )


    if not sql_statements:

        st.warning(
            "Cortex Analyst did not return executable SQL."
        )

        with st.expander(
            "Raw Cortex response"
        ):

            st.json(response)

        return


    generated_sql = sql_statements[0]


    with st.expander(
        "🧠 Generated SQL"
    ):

        st.code(
            generated_sql,
            language="sql"
        )


    st.subheader(
        "📊 Query result"
    )


    try:

        result_df = session.sql(
            generated_sql
        ).to_pandas()


        result_df.columns = [
            str(column).upper()
            for column in result_df.columns
        ]


        if result_df.empty:

            st.info(
                "The query returned no records."
            )

        else:

            show(
                result_df
            )


            csv_data = (
                result_df
                .to_csv(index=False)
                .encode("utf-8")
            )


            st.download_button(
                "⬇️ Download CSV",
                data=csv_data,
                file_name="cortex_result.csv",
                mime="text/csv"
            )


    except Exception as error:

        st.error(
            "Generated SQL could not be executed."
        )

        st.exception(error)

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



# =============================================================================
# MAIN RENDERING
# =============================================================================

display_user = me if me else "Unknown user"
display_persona = PERSONA.get(me, "Unmapped user")

period_label = (
    f"{d_from.strftime('%d %b %Y')} – {d_to.strftime('%d %b %Y')}"
)

region_label = f"{len(regions)} region(s) selected"


st.markdown(
    f"""
    <section class='hero-shell'>
      <div class='hero-kicker'>Insurance intelligence · secure analytics workspace</div>
      <div class='hero-title'>Insurance Policy Lifecycle</div>
      <div class='hero-subtitle'>A consolidated view of portfolio performance, claims operations and fraud risk.</div>
      <div class='hero-meta'>
        <span class='hero-pill'>👤 {display_user} · {display_persona}</span>
        <span class='hero-pill'>🗺️ {region_label}</span>
        <span class='hero-pill'>📅 {period_label}</span>
        <span class='hero-pill'>🔒 Secure Consumption</span>
      </div>
    </section>
    """,
    unsafe_allow_html=True
)


ICON = {
    "KPI": "📊 KPI Scorecard",
    "Underwriting": "📑 Underwriting",
    "Claims": "📋 Claims",
    "Fraud": "🚨 Fraud",
     "Network": "🕸️ Network",
    "Alerts": "🔔 Alerts",
    "Cortex": "🤖 Ask Cortex"
}


RENDER = {
    "KPI": kpi_scorecard,
    "Underwriting": underwriting,
    "Claims": claims,
    "Fraud": fraud,
     "Network": fraud_network,
     "Alerts": alerts,
    "Cortex": cortex_tab
}


pages = (
    ["KPI"]
    + allowed
    + ["Cortex"] +(["Network", "Alerts"] if "Fraud" in allowed else [])
)


tab_names = [
    ICON[page]
    for page in pages
]


tabs = st.tabs(
    tab_names
)


for tab, page in zip(
    tabs,
    pages
):

    with tab:

        RENDER[page]()


st.markdown(
    "<div style='text-align:center; padding:1.4rem .2rem .3rem .2rem; "
    "color:#8291a4; font-size:.75rem;'>"
    "Insurance Policy Lifecycle Analytics · Powered by Snowflake and Cortex Analyst"
    "</div>",
    unsafe_allow_html=True
)
