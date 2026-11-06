Best Tables for Snowflake Cortex Analyst — Your Insurance Project

For your Insurance Policy Lifecycle, Claims, Fraud & Risk Analytics capstone project, I recommend using the Gold-layer analytical views as the primary input for Snowflake Cortex Analyst.

Your screenshot shows 12 views, divided into:

4 analytical marts
4 dimension views
4 fact views

My recommendation: Start with the 4 analytical marts, then add dimension and fact views only when needed.

Cortex Analyst allows users to ask natural-language questions about structured Snowflake data without writing SQL.

1. Which Views Should You Select?
Priority 1 — Select These Four Views
View Name	Purpose	PriorityMART_POLICY_PORTFOLIO	Policy portfolio analysis	⭐⭐⭐
MART_CLAIMS_PERFORMANCE	Claims performance analysis	⭐⭐⭐
MART_FRAUD_RISK	Fraud risk analysis	⭐⭐⭐
MART_SETTLEMENT_RECONCILIATION	Claim settlement analysis	⭐⭐⭐

These four marts align directly with your project's main business objectives.

Why these four?

1. MART_POLICY_PORTFOLIO

Use it for questions such as:

How many active policies are there?
What is the total sum insured?
Which insurance products have the highest policy count?
How does the policy portfolio vary by insurance type?

2. MART_CLAIMS_PERFORMANCE

Use it for:

What is the total number of claims?
What is the average claim amount?
What is the claim approval ratio?
Which policies have the highest claim amounts?

3. MART_FRAUD_RISK

Use it for:

How many fraud investigations are open?
How many fraud cases are classified as high risk?
What is the average fraud score?
Which fraud categories require attention?

4. MART_SETTLEMENT_RECONCILIATION

Use it for:

What is the total net settlement amount?
What is the difference between approved and settled amounts?
Which claims have settlement discrepancies?
What is the average settlement turnaround time?

These questions are examples of what your Cortex Analyst could answer, provided the necessary fields and metrics exist in the selected views.

2. Should You Select All 12 Views?

No. I would not recommend selecting all 12 views initially.

Your screenshot also shows:

Dimension Views
VW_DIM_CUSTOMER
VW_DIM_DATE
VW_DIM_INSURANCE_PRODUCT
VW_DIM_POLICY
Fact Views
VW_FACT_CLAIM
VW_FACT_CLAIM_SETTLEMENT
VW_FACT_FRAUD_CASE
VW_FACT_PREMIUM_PAYMENT

These are useful for more detailed analysis, but they introduce additional relationships and potential join complexity.

For example, if you combine claims, settlements and fraud cases without defining the correct relationships and table grains, you could accidentally double-count claim amounts.

Start with the four marts because they are intended for business reporting.

3. Recommended Cortex Analyst Configuration

I recommend creating a semantic model or semantic view for:

Insurance Lifecycle Analytics

Use the following four marts:

Plain Text
INSURANCEPOLICY_LIFECYCLE_DB
|
v
GOLD
|
+-- MART_POLICY_PORTFOLIO
|
+-- MART_CLAIMS_PERFORMANCE
|
+-- MART_FRAUD_RISK
|
+-- MART_SETTLEMENT_RECONCILIATION
|
v
CORTEX ANALYST
|
v
Natural Language Questions
|
v
Generated SQL + Results
Important configuration

When defining your semantic layer:

Select the appropriate Gold views.
Describe each view's business purpose.
Define important dimensions.
Define business metrics.
Specify relationships only where valid.
Add verified example questions and SQL queries.

Verified queries help improve Cortex Analyst's accuracy.

4. What About Premium Payment Analysis?

Your project also requires premium collection analytics.

Your screenshot contains:

VW_FACT_PREMIUM_PAYMENT

I recommend adding this view if MART_POLICY_PORTFOLIO does not contain the premium-payment metrics you need.

For example:

Total premiums collected.
Paid versus reversed transactions.
Premium collection by month.
Payment method distribution.
Recommended Additional Views
View	When to AddVW_FACT_PREMIUM_PAYMENT	Premium collection analysis
VW_DIM_DATE	Monthly, quarterly and yearly trends
VW_DIM_INSURANCE_PRODUCT	Insurance product comparisons
VW_DIM_POLICY	Policy-level drill-down
VW_DIM_CUSTOMER	Customer segmentation

Add these only after defining the correct relationships.

5. Best Setup for Your SME Demonstration

For a clear demonstration, I recommend starting with four separate business domains rather than building one complicated semantic model immediately.

Cortex Analysis Domain	Input ViewPolicy Analytics	MART_POLICY_PORTFOLIO
Claims Analytics	MART_CLAIMS_PERFORMANCE
Fraud Risk Analytics	MART_FRAUD_RISK
Settlement Analytics	MART_SETTLEMENT_RECONCILIATION

Then demonstrate questions from each domain.

Suggested SME Demo Questions

Policy

How many active insurance policies are there?

Claims

What is the average claim amount?

Fraud

How many high-risk fraud cases are there?

Settlement

What is the total net settlement amount?

Premium

What is the total premium amount collected?

For the premium question, include VW_FACT_PREMIUM_PAYMENT if necessary.

6. My Final Recommendation

For your project, use this priority order:

Order	View	Recommendation1	MART_POLICY_PORTFOLIO	✅ Select
2	MART_CLAIMS_PERFORMANCE	✅ Select
3	MART_FRAUD_RISK	✅ Select
4	MART_SETTLEMENT_RECONCILIATION	✅ Select
5	VW_FACT_PREMIUM_PAYMENT	✅ Add for premium analytics
6	Other fact/dimension views	Add later if required
One important point

Because you have already implemented RBAC and Secure Views, make sure Cortex Analyst uses only data that the intended user role is authorized to access. Do not expose customer contact information or restricted Bronze/Audit records through the semantic model.

Final Answer

Start with these four Gold views:

MART_POLICY_PORTFOLIO
MART_CLAIMS_PERFORMANCE
MART_FRAUD_RISK
MART_SETTLEMENT_RECONCILIATION

Then add VW_FACT_PREMIUM_PAYMENT for premium collection analysis.

This will give your SME a clear demonstration of how natural-language questions can generate SQL and retrieve meaningful insurance business insights using Snowflake Cortex Analyst.