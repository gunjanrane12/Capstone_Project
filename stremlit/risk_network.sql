USE ROLE ACCOUNTADMIN;
USE SCHEMA INSURANCEPOLICY_LIFECYCLE_DB.SECURE_CONSUMPTION;

CREATE OR REPLACE SECURE VIEW VW_FRAUD_LINKS AS
WITH ATTR AS (
    SELECT CUSTOMER_ID, 'PHONE' AS LINK_TYPE, PHONE AS LINK_VALUE
      FROM SILVER.CUSTOMERS WHERE PHONE IS NOT NULL
    UNION ALL
    SELECT CUSTOMER_ID, 'EMAIL', LOWER(TRIM(EMAIL))
      FROM SILVER.CUSTOMERS WHERE EMAIL IS NOT NULL
    UNION ALL
    SELECT CUSTOMER_ID, 'ADDRESS', UPPER(TRIM(ADDRESS_LINE)) || '|' || UPPER(TRIM(CITY))
      FROM SILVER.CUSTOMERS WHERE ADDRESS_LINE IS NOT NULL
    UNION ALL
    SELECT CUSTOMER_ID, 'NOMINEE', UPPER(TRIM(NOMINEE_NAME))
      FROM SILVER.POLICIES WHERE NOMINEE_NAME IS NOT NULL
    UNION ALL
    SELECT CUSTOMER_ID, 'AGENT', AGENT_ID
      FROM SILVER.POLICIES WHERE AGENT_ID IS NOT NULL
    UNION ALL
    SELECT CUSTOMER_ID, 'ASSESSOR', ASSESSOR_ID
      FROM SILVER.CLAIMS_SCD2
     WHERE IS_CURRENT = TRUE AND IS_DELETED = FALSE AND ASSESSOR_ID IS NOT NULL
),
DIST AS (SELECT DISTINCT CUSTOMER_ID, LINK_TYPE, LINK_VALUE FROM ATTR),
GRP  AS (SELECT LINK_TYPE, LINK_VALUE, COUNT(*) AS GROUP_SIZE FROM DIST GROUP BY 1, 2)
SELECT a.CUSTOMER_ID AS CUSTOMER_A,
       b.CUSTOMER_ID AS CUSTOMER_B,
       a.LINK_TYPE,
       g.GROUP_SIZE                       -- the shared value itself is NOT exposed (PII)
FROM DIST a
JOIN DIST b ON  b.LINK_TYPE  = a.LINK_TYPE
            AND b.LINK_VALUE = a.LINK_VALUE
            AND a.CUSTOMER_ID < b.CUSTOMER_ID      -- each pair once, no self-links
JOIN GRP  g ON  g.LINK_TYPE  = a.LINK_TYPE
            AND g.LINK_VALUE = a.LINK_VALUE
WHERE g.GROUP_SIZE BETWEEN 2 AND 10;               -- ignore "hubs" (see note below)


CREATE OR REPLACE SECURE VIEW VW_FRAUD_NETWORK_RISK AS
WITH E AS (                                   -- make links two-way
    SELECT CUSTOMER_A AS CUSTOMER_ID, CUSTOMER_B AS NEIGHBOUR, LINK_TYPE FROM VW_FRAUD_LINKS
    UNION ALL
    SELECT CUSTOMER_B, CUSTOMER_A, LINK_TYPE FROM VW_FRAUD_LINKS
),
F AS (
    SELECT CUSTOMER_ID,
           COUNT(*) AS FRAUD_CASES,
           COUNT_IF(UPPER(INVESTIGATION_OUTCOME) LIKE '%CONFIRMED%') AS CONFIRMED
    FROM SILVER.FRAUD_CASES
    GROUP BY 1
)
SELECT E.CUSTOMER_ID,
       COALESCE(c.REGION, 'UNKNOWN')                       AS REGION,
       COALESCE(MAX(own.FRAUD_CASES), 0)                   AS OWN_FRAUD_CASES,
       COALESCE(MAX(own.CONFIRMED), 0)                     AS OWN_CONFIRMED,
       COUNT(DISTINCT E.NEIGHBOUR)                         AS LINKED_CUSTOMERS,
       LISTAGG(DISTINCT E.LINK_TYPE, ', ')                 AS LINK_TYPES,
       COUNT(DISTINCT IFF(nb.FRAUD_CASES > 0, E.NEIGHBOUR, NULL)) AS LINKED_WITH_FRAUD_CASE,
       COUNT(DISTINCT IFF(nb.CONFIRMED  > 0, E.NEIGHBOUR, NULL)) AS LINKED_CONFIRMED_FRAUD,
       CASE WHEN COUNT(DISTINCT IFF(nb.CONFIRMED > 0, E.NEIGHBOUR, NULL)) >= 2 THEN 'HIGH'
            WHEN COUNT(DISTINCT IFF(nb.CONFIRMED > 0, E.NEIGHBOUR, NULL)) = 1
              OR COUNT(DISTINCT IFF(nb.FRAUD_CASES > 0, E.NEIGHBOUR, NULL)) >= 2 THEN 'MEDIUM'
            ELSE 'LOW' END                                 AS NETWORK_RISK
FROM E
LEFT JOIN F nb          ON nb.CUSTOMER_ID  = E.NEIGHBOUR
LEFT JOIN F own         ON own.CUSTOMER_ID = E.CUSTOMER_ID
LEFT JOIN SILVER.CUSTOMERS c ON c.CUSTOMER_ID = E.CUSTOMER_ID
GROUP BY E.CUSTOMER_ID, c.REGION;

GRANT SELECT ON VIEW VW_FRAUD_LINKS        TO ROLE FRAUD_MANAGER_ROLE;
GRANT SELECT ON VIEW VW_FRAUD_NETWORK_RISK TO ROLE FRAUD_MANAGER_ROLE;
GRANT SELECT ON VIEW VW_FRAUD_LINKS        TO ROLE STREAMLIT_APP_ROLE;
GRANT SELECT ON VIEW VW_FRAUD_NETWORK_RISK TO ROLE STREAMLIT_APP_ROLE;


--- stremlit
# ===========================================================================
# 4. FRAUD NETWORK - Fraud Manager
# ===========================================================================
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
        bar(links.groupby("LINK_TYPE")["CUSTOMER_A"].count())
    with c2:
        st.subheader("Network risk mix")
        bar(risk.groupby("NETWORK_RISK")["CUSTOMER_ID"].count())

    st.subheader("🚩 Most connected to fraud")
    top = risk.sort_values(["LINKED_CONFIRMED_FRAUD", "LINKED_WITH_FRAUD_CASE", "LINKED_CUSTOMERS"],
                           ascending=False)
    show(top.head(50))
    if top.empty:
        st.info("No linked customers in the selected regions.")
        return

    st.subheader("🕸️ Explore a customer's network")
    pick = st.selectbox("Customer", top["CUSTOMER_ID"].head(200).tolist(), key="net_pick")
    direct = links[(links["CUSTOMER_A"] == pick) | (links["CUSTOMER_B"] == pick)]
    nodes = set(direct["CUSTOMER_A"]) | set(direct["CUSTOMER_B"])
    edges = links[links["CUSTOMER_A"].isin(nodes) & links["CUSTOMER_B"].isin(nodes)]  # also links between neighbours

    flags = risk.set_index("CUSTOMER_ID")
    dot = ["graph G {", "layout=neato; overlap=false;",
           "node [shape=circle style=filled fontname=Helvetica fontsize=9];"]
    for n in nodes:
        conf = n in flags.index and flags.at[n, "OWN_CONFIRMED"] > 0
        case = n in flags.index and flags.at[n, "OWN_FRAUD_CASES"] > 0
        color = "#E05C5C" if conf else "#F2A541" if case else "#A7C7E7"
        width = "penwidth=3" if n == pick else ""
        dot.append(f'"{n}" [fillcolor="{color}" {width}];')
    for _, e in edges.iterrows():
        dot.append(f'"{e.CUSTOMER_A}" -- "{e.CUSTOMER_B}" [label="{e.LINK_TYPE}" fontsize=7];')
    dot.append("}")
    st.graphviz_chart("\n".join(dot), use_container_width=True)
    st.caption("🔴 confirmed fraud · 🟠 has fraud case · 🔵 no fraud case · thick border = selected")



ICON = {"KPI": "📊 KPI Scorecard", "Underwriting": "📑 Underwriting",
        "Claims": "📋 Claims", "Fraud": "🚨 Fraud", "Network": "🕸️ Network"}
RENDER = {"KPI": kpi_scorecard, "Underwriting": underwriting, "Claims": claims,
          "Fraud": fraud, "Network": fraud_network}
pages = ["KPI"] + allowed + (["Network"] if "Fraud" in allowed else [])
