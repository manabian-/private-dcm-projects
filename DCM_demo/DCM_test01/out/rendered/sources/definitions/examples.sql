define warehouse DCM_DEMO_1_WH_MY_PROJECT_OBJECT
with
    warehouse_size = 'SMALL'
    auto_suspend = 300
    comment = 'For Quickstart Demo of DCM Projects'
;

define database DCM_DEMO_1_MY_PROJECT_OBJECT
    comment = 'This is a Quickstart Demo for DCM Projects Private Preview';

define schema DCM_DEMO_1_MY_PROJECT_OBJECT.ANALYTICS
    comment = 'For Task copying sample data into landing tables';

define table DCM_DEMO_1_MY_PROJECT_OBJECT.ANALYTICS.ALL_ITEMS(
    ITEM_NAME varchar,
    ITEM_ID varchar,
    ITEM_CATEGORY array
)
change_tracking = TRUE;

define dynamic table DCM_DEMO_1_MY_PROJECT_OBJECT.ANALYTICS.DRINKS
    warehouse = DCM_DEMO_1_WH_MY_PROJECT_OBJECT
    target_lag = '6 hours'
    initialize = 'ON_CREATE'
  as
    select
        *
    from
        DCM_DEMO_1_MY_PROJECT_OBJECT.ANALYTICS.ALL_ITEMS
    where
        ARRAY_CONTAINS('DRINKS'::variant, ITEM_CATEGORY)
;

define role DCM_DEMO_1_MY_PROJECT_OBJECT_READ;

grant USAGE on database DCM_DEMO_1_MY_PROJECT_OBJECT to role DCM_DEMO_1_MY_PROJECT_OBJECT_READ;
grant USAGE on schema DCM_DEMO_1_MY_PROJECT_OBJECT.ANALYTICS to role DCM_DEMO_1_MY_PROJECT_OBJECT_READ;
grant SELECT on ALL tables in database DCM_DEMO_1_MY_PROJECT_OBJECT to role DCM_DEMO_1_MY_PROJECT_OBJECT_READ;
grant SELECT on dynamic table DCM_DEMO_1_MY_PROJECT_OBJECT.ANALYTICS.DRINKS to role DCM_DEMO_1_MY_PROJECT_OBJECT_READ;