"""
ClaimGuard 360 - Data Cleaning Script
Usage:  python clean_claimguard.py <folder_with_raw_csvs>
Output: <folder>/cleaned/*.csv , <folder>/rejected/*_rejected.csv , <folder>/cleaning_log.csv
Rule: fixable issues are corrected + noted in dq_flags; unfixable rows go to rejected with reject_reason.
"""
import sys, os, re
import pandas as pd
import numpy as np, warnings
warnings.filterwarnings("ignore")

SRC = sys.argv[1] if len(sys.argv) > 1 else "."
OUT_C, OUT_R = os.path.join(SRC, "cleaned"), os.path.join(SRC, "rejected")
os.makedirs(OUT_C, exist_ok=True); os.makedirs(OUT_R, exist_ok=True)
LOG = []

STATE_REGION = {"Tamil Nadu": "South", "Kerala": "South", "Karnataka": "South", "Telangana": "South",
                "Delhi NCR": "North", "Rajasthan": "North", "Gujarat": "West", "Maharashtra": "West",
                "West Bengal": "East"}
HIGH_DATE = "9999-12-31"

# ---------- helpers ----------
def load(name):
    df = pd.read_csv(os.path.join(SRC, name), dtype=str, keep_default_na=False)
    df.columns = [c.strip().lower() for c in df.columns]
    for c in df.columns:
        df[c] = df[c].str.strip().replace({"": np.nan, "NULL": np.nan, "null": np.nan, "NA": np.nan, "N/A": np.nan, "None": np.nan})
    df["dq_flags"] = ""
    return df

def flag(df, mask, text):
    mask = mask.fillna(False)
    df.loc[mask, "dq_flags"] = df.loc[mask, "dq_flags"].apply(lambda s: (s + "|" if s else "") + text)
    return int(mask.sum())

def to_date(s):
    out = pd.to_datetime(s, errors="coerce", format="%Y-%m-%d")
    for fmt in ("%d-%m-%Y", "%d/%m/%Y", "%Y/%m/%d", "%m/%d/%Y", "%d-%b-%Y", "%Y%m%d"):
        m = out.isna() & s.notna()
        if not m.any(): break
        out[m] = pd.to_datetime(s[m], errors="coerce", format=fmt)
    return out

def fix_dates(df, cols, name):
    for c in cols:
        if c not in df: continue
        raw = df[c].copy()
        d = to_date(raw)
        nonstd = raw.notna() & ~raw.fillna("").str.match(r"^\d{4}-\d{2}-\d{2}$")
        n = flag(df, nonstd & d.notna(), f"{c}_format_fixed")
        bad = raw.notna() & d.isna()
        flag(df, bad, f"{c}_unparseable")
        df[c] = d.dt.strftime("%Y-%m-%d")
        if n: LOG.append((name, f"Standardised {c} to YYYY-MM-DD", n))

def to_num(df, cols):
    for c in cols:
        if c in df: df[c] = pd.to_numeric(df[c].str.replace(",", "", regex=False), errors="coerce")

def dedupe(df, pk, name):
    before = len(df)
    df = df.drop_duplicates(subset=[c for c in df.columns if c != "dq_flags"])
    exact = before - len(df)
    if exact: LOG.append((name, "Removed exact duplicate rows", exact))
    df = df.sort_values("source_updated_ts").drop_duplicates(pk, keep="last") if "source_updated_ts" in df else df.drop_duplicates(pk, keep="last")
    pkd = before - exact - len(df)
    if pkd: LOG.append((name, f"Removed duplicate {pk} (kept latest source_updated_ts)", pkd))
    return df.sort_values(pk).reset_index(drop=True)

def split(df, reasons, name):
    """reasons: list of (mask, reason)."""
    rej = pd.Series("", index=df.index)
    for m, r in reasons:
        m = m.fillna(False)
        if m.sum(): LOG.append((name, f"REJECTED: {r}", int(m.sum())))
        rej[m] = rej[m].apply(lambda s: (s + "|" if s else "") + r)
    bad = rej != ""
    rejected = df[bad].copy(); rejected["reject_reason"] = rej[bad]
    return df[~bad].copy(), rejected

def title(df, cols):
    for c in cols:
        if c in df: df[c] = df[c].str.title()

def fill(df, col, val, name):
    if col not in df: return
    m = df[col].isna(); n = flag(df, m, f"{col}_missing")
    df[col] = df[col].fillna(val)
    if n: LOG.append((name, f"Filled missing {col} with '{val}'", n))

def save(name, clean, rej, raw_count):
    clean.to_csv(os.path.join(OUT_C, name), index=False)
    rej.to_csv(os.path.join(OUT_R, name.replace(".csv", "_rejected.csv")), index=False)
    LOG.append((name, "SUMMARY raw -> clean / rejected", f"{raw_count} -> {len(clean)} / {len(rej)}"))
    return clean

# ---------- 1. customers ----------
n = "customers.csv"; df = load(n); raw = len(df)
df = dedupe(df, "customer_id", n)
fix_dates(df, ["date_of_birth", "registration_date"], n)
title(df, ["customer_name", "gender", "city", "occupation", "customer_risk_category"])
df["email"] = df["email"].str.lower()
flag(df, df["email"].notna() & ~df["email"].fillna("").str.match(r"^[\w.+-]+@[\w-]+\.[\w.]+$"), "email_invalid")
digits = df["phone"].fillna("").str.replace(r"\D", "", regex=True).str[-10:]
df["phone"] = np.where(digits.str.len() == 10, "+91" + digits, np.nan)
fill(df, "email", "NOT PROVIDED", n); fill(df, "phone", "NOT PROVIDED", n)
exp_region = df["state"].map(STATE_REGION)
mis = exp_region.notna() & (df["region"] != exp_region)
c = flag(df, mis, "region_corrected_from_state"); df.loc[mis, "region"] = exp_region[mis]
if c: LOG.append((n, "Corrected region to match state", c))
dob = pd.to_datetime(df["date_of_birth"]); reg = pd.to_datetime(df["registration_date"])
age = (pd.Timestamp("today") - dob).dt.days / 365.25
customers, rej = split(df, [(df["customer_id"].isna(), "customer_id missing"),
                            (dob.isna(), "date_of_birth missing/invalid"),
                            ((age < 18) | (age > 100), "age outside 18-100"),
                            (reg < dob, "registration before birth")], n)
customers = save(n, customers, rej, raw)

# ---------- 2. insurance_products ----------
n = "insurance_products.csv"; df = load(n); raw = len(df)
df = dedupe(df, "product_id", n)
to_num(df, ["minimum_sum_insured", "maximum_sum_insured", "grace_period_days"])
title(df, ["insurance_type", "coverage_category", "premium_frequency"])
df["active_flag"] = df["active_flag"].str.lower().map({"true": True, "y": True, "yes": True, "1": True,
                                                       "false": False, "n": False, "no": False, "0": False})
m = df["maximum_sum_insured"].isna(); c = flag(df, m, "max_sum_insured_missing_set_to_min")
df.loc[m, "maximum_sum_insured"] = df.loc[m, "minimum_sum_insured"]
if c: LOG.append((n, "Missing maximum_sum_insured set equal to minimum (flagged)", c))
products, rej = split(df, [(df["product_id"].isna(), "product_id missing"),
                           (df["minimum_sum_insured"] > df["maximum_sum_insured"], "min sum insured > max"),
                           (df["minimum_sum_insured"] <= 0, "non-positive min sum insured")], n)
products = save(n, products, rej, raw)

# ---------- 3. policies ----------
n = "policies.csv"; df = load(n); raw = len(df)
df = dedupe(df, "policy_id", n)
fix_dates(df, ["policy_issue_date", "policy_start_date", "policy_expiry_date"], n)
to_num(df, ["sum_insured", "premium_amount"])
title(df, ["premium_frequency", "policy_status", "nominee_name"])
df["underwriting_risk_band"] = df["underwriting_risk_band"].str.upper()
fill(df, "nominee_name", "NOT PROVIDED", n)
iss, st, ex = (pd.to_datetime(df[c]) for c in ["policy_issue_date", "policy_start_date", "policy_expiry_date"])
flag(df, df["premium_amount"] > df["sum_insured"] * 0.2, "premium_gt_20pct_sum_insured_outlier")
policies, rej = split(df, [(df["policy_id"].isna(), "policy_id missing"),
                           (~df["customer_id"].isin(customers["customer_id"]), "customer_id not in customers"),
                           (~df["product_id"].isin(products["product_id"]), "product_id not in products"),
                           (ex <= st, "expiry date on/before start date"),
                           (st < iss, "start date before issue date"),
                           ((df["sum_insured"] <= 0) | (df["premium_amount"] <= 0), "non-positive amount")], n)
policies = save(n, policies, rej, raw)

# ---------- 4. claims ----------
n = "claims.csv"; df = load(n); raw = len(df)
df = dedupe(df, "claim_id", n)
fix_dates(df, ["claim_registration_date", "loss_date"], n)
to_num(df, ["claim_amount", "approved_amount"])
title(df, ["claim_type", "claim_status"])
fill(df, "assessor_id", "UNASSIGNED", n)
reg, loss = pd.to_datetime(df["claim_registration_date"]), pd.to_datetime(df["loss_date"])
pol = policies.set_index("policy_id")
si = df["policy_id"].map(pol["sum_insured"])
pcust = df["policy_id"].map(pol["customer_id"])
flag(df, df["claim_amount"] > si, "claim_amount_exceeds_sum_insured_outlier")
q1, q3 = df["claim_amount"].quantile([.25, .75]); flag(df, df["claim_amount"] > q3 + 3 * (q3 - q1), "claim_amount_iqr_outlier")
flag(df, (reg - pd.to_datetime(df["policy_id"].map(pol["policy_start_date"]))).dt.days.between(0, 30), "early_claim_within_30_days")
claims, rej = split(df, [(df["claim_id"].isna(), "claim_id missing"),
                         (~df["policy_id"].isin(policies["policy_id"]), "policy_id not in clean policies"),
                         (pcust.notna() & (pcust != df["customer_id"]), "customer_id does not match policy"),
                         (loss > reg, "loss_date after registration date"),
                         (df["approved_amount"] > df["claim_amount"], "approved_amount > claim_amount"),
                         (df["claim_amount"] <= 0, "non-positive claim amount")], n)
claims = save(n, claims, rej, raw)

# ---------- 5. claim_settlements ----------
n = "claim_settlements.csv"; df = load(n); raw = len(df)
df = dedupe(df, "settlement_id", n)
fix_dates(df, ["settlement_date"], n)
amt = ["gross_settlement_amount", "deductible_amount", "recovery_amount", "net_settlement_amount"]; to_num(df, amt)
title(df, ["settlement_type", "payment_status"])
calc = (df["gross_settlement_amount"] - df["deductible_amount"] - df["recovery_amount"]).round(2)
m = (calc - df["net_settlement_amount"]).abs() > 1
c = flag(df, m, "net_amount_recalculated"); df.loc[m, "net_settlement_amount"] = calc[m]
if c: LOG.append((n, "Recalculated net = gross - deductible - recovery", c))
fill(df, "payment_reference", "PENDING_REFERENCE", n)
cl = claims.set_index("claim_id")
flag(df, df["claim_id"].map(cl["claim_status"]).isin(["Rejected"]), "settlement_on_rejected_claim")
flag(df, df["gross_settlement_amount"] > df["claim_id"].map(cl["approved_amount"]) + 1, "gross_exceeds_approved")
creg = pd.to_datetime(df["claim_id"].map(cl["claim_registration_date"]))
settlements, rej = split(df, [(df["settlement_id"].isna(), "settlement_id missing"),
                              (~df["claim_id"].isin(claims["claim_id"]), "claim_id not in clean claims"),
                              (pd.to_datetime(df["settlement_date"]) < creg, "settlement before claim registration"),
                              ((df[amt] < 0).any(axis=1), "negative amount")], n)
save(n, settlements, rej, raw)

# ---------- 6. fraud_cases ----------
n = "fraud_cases.csv"; df = load(n); raw = len(df)
df = dedupe(df, "fraud_case_id", n)
open_end = df["investigation_end_date"] == HIGH_DATE
c = flag(df, open_end, "open_case_end_date_nulled")
df.loc[open_end, "investigation_end_date"] = np.nan
fix_dates(df, ["investigation_start_date", "investigation_end_date"], n)
if c: LOG.append((n, "Replaced 9999-12-31 placeholder end date with NULL for open cases", c))
to_num(df, ["fraud_score"])
title(df, ["investigation_status", "investigation_outcome"])
fill(df, "investigator_id", "UNASSIGNED", n)
s, e = pd.to_datetime(df["investigation_start_date"]), pd.to_datetime(df["investigation_end_date"])
fraud, rej = split(df, [(df["fraud_case_id"].isna(), "fraud_case_id missing"),
                        (~df["claim_id"].isin(claims["claim_id"]), "claim_id not in clean claims"),
                        ((df["fraud_score"] < 0) | (df["fraud_score"] > 100) | df["fraud_score"].isna(), "fraud_score outside 0-100"),
                        (e < s, "end date before start date"),
                        ((df["investigation_status"] == "Closed") & e.isna(), "closed case without end date")], n)
save(n, fraud, rej, raw)

# ---------- 7. premium_payments ----------
n = "premium_payments.csv"; df = load(n); raw = len(df)
df = dedupe(df, "payment_id", n)
fix_dates(df, ["payment_date"], n)
to_num(df, ["payment_amount"])
title(df, ["payment_status"])
fill(df, "reference_number", "PENDING_REFERENCE", n)
flag(df, df["payment_amount"] > df["policy_id"].map(policies.set_index("policy_id")["premium_amount"]) * 1.5, "payment_gt_150pct_premium_outlier")
payments, rej = split(df, [(df["payment_id"].isna(), "payment_id missing"),
                           (~df["policy_id"].isin(policies["policy_id"]), "policy_id not in clean policies"),
                           (df["payment_amount"] <= 0, "non-positive payment amount")], n)
save(n, payments, rej, raw)

pd.DataFrame(LOG, columns=["file", "action", "rows"]).to_csv(os.path.join(SRC, "cleaning_log.csv"), index=False)
print(pd.DataFrame(LOG, columns=["file", "action", "rows"]).to_string(index=False))
