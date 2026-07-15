{% snapshot customer_snapshot %}

{{
    config(
        target_database='gen_ai_poc_snowflakecoe',
        target_schema='sdlc_wizard',
        unique_key='CUSTID',
        strategy='check',
        check_cols=['NAME', 'EMAILID', 'REGION'],
        invalidate_hard_deletes=True
    )
}}

SELECT
    CUSTID,
    NAME,
    EMAILID,
    REGION
FROM {{ ref('int_customer_clean') }}

{% endsnapshot %}