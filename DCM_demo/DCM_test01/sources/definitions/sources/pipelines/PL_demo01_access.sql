{# PL_DEMO01固有設定 #}
{% set app_schema = 'PL_DEMO01' %}
{% set object_namespace = database ~ '.' ~ app_schema %}

--------------------------------------------------
-- Schema
--------------------------------------------------

GRANT USAGE
ON SCHEMA {{ object_namespace }}
TO ROLE ETL_TASK_ROLE;


--------------------------------------------------
-- Bronze
-- SP_COPY      : INSERT
-- SP_UPSERT    : SELECT
-- SP_DELETE    : DELETE
--------------------------------------------------

GRANT SELECT, INSERT, DELETE
ON TABLE {{ object_namespace }}.ORDERS_BRONZE
TO ROLE ETL_TASK_ROLE;


--------------------------------------------------
-- Silver
-- SP_UPSERT : SELECT / INSERT / UPDATE
--------------------------------------------------

GRANT SELECT, INSERT, UPDATE
ON TABLE {{ object_namespace }}.ORDERS
TO ROLE ETL_TASK_ROLE;


--------------------------------------------------
-- Stream
-- SP_UNLOADで参照
--------------------------------------------------

GRANT SELECT
ON STREAM {{ object_namespace }}.ORDERS_STREAM
TO ROLE ETL_TASK_ROLE;


--------------------------------------------------
-- Source Stage
-- SP_COPYで参照
--------------------------------------------------

GRANT USAGE
ON STAGE {{ object_namespace }}.SOURCE_STAGE
TO ROLE ETL_TASK_ROLE;


--------------------------------------------------
-- UNLOAD Stage
--------------------------------------------------

GRANT USAGE
ON STAGE {{ object_namespace }}.OUTPUT_STAGE
TO ROLE ETL_TASK_ROLE;