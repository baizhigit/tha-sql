SELECT 
    -- ctc.id,
    -- ctc."concessionId",
    -- ctc."cardTypeId",
    c.id AS con_id,
    ci.name AS city,
    ct.name code,
    tl.title_ru,
    rules.types AS type,
    rules.keys AS key,
    rules.values AS value,
    c.name AS concession,
    g.name AS groupName,
    ct."isConcessionRequired" AS isConcession,
    cs.name AS subcategory,
    cc.name AS category,
    cst."issueCost",
    cst."reIssueCost",
    -- tr.tariffs_json,
    (tr.tariffs_json -> cc."cityId"::text ->> 'tripCost')::NUMERIC AS trip_cost,
    (tr.tariffs_json -> cc."cityId"::text ->> 'passCost')::NUMERIC AS passCost,
    CASE WHEN val."validationClass" IS NOT NULL THEN 'yes' ELSE NULL END AS validation
FROM public.card_type_concessions ctc
LEFT JOIN public.card_types ct ON ct.id = ctc."cardTypeId"
LEFT JOIN public.ct_card_titles tl on tl.nn = ct.name
LEFT JOIN public.concessions c ON c.id = ctc."concessionId"
LEFT JOIN public.concession_groups g ON g.id = c."groupId"
LEFT JOIN (
    SELECT 
        "concessionGroupId",
        STRING_AGG(type, ', ' ORDER BY id) AS types,
        STRING_AGG(key, ', ' ORDER BY id) AS keys,
        STRING_AGG(value, ', ' ORDER BY id) AS values
    FROM public.concession_rules
    GROUP BY "concessionGroupId"
) rules ON rules."concessionGroupId" = g.id
LEFT JOIN public.concession_subcategories cs ON cs.id = c."subcategoryId"
LEFT JOIN public.concession_categories cc ON cc.id = cs."concessionCategoryId"
LEFT JOIN public.cities ci ON ci.id = cc."cityId"
LEFT JOIN public.concession_costs cst ON cst."concessionId" = ctc."concessionId" AND cst."cardTypeId" = ctc."cardTypeId"
LEFT JOIN public.ct_card_tariffs tr ON tr.nn = ct.name
LEFT JOIN public.concession_validations val ON val."concessionGroupId" = g.id
WHERE 1=1
-- AND cc."cityId" = 1 -- Алматы
-- AND cc."cityId" = 2 -- Караганда
-- AND cc."cityId" = 4 -- Сарань
-- AND cc."cityId" = 7 -- Темиртау
-- AND cc."cityId" = 5 -- Балхаш
-- AND cc."cityId" = 9 -- Шахтинск
AND cc."cityId" = 10 -- Усть-Каменогорск
-- AND cc."cityId" = 12 -- Текели

-- AND c.name ILIKE '%Гарантия%'
-- AND c.name ILIKE '%22 МРП%'
-- AND c.name ILIKE '%I группы%'
-- AND c.name ILIKE '%Алтын%'
;



SELECT
    ci.id              AS city_id,
    ci.name            AS city_name,
    con_cat.id         AS con_cat_id,
    con_cat.name       AS con_cat_name,
    con_sub.id         AS con_sub_id,
    con_sub.name       AS con_sub_name,
    con_gr.id          AS con_gr_id,
    con_gr.name        AS con_gr_name,
    con.id             AS con_id,
    con.name           AS con_name,
    con."showOnCreate" AS con_is_issue,
    con."isHidden"     AS con_is_hidden
FROM cities                        AS ci
FULL JOIN concession_categories    AS con_cat
    ON ci.id = con_cat."cityId"
FULL JOIN concession_subcategories AS con_sub
    ON con_cat.id = con_sub."concessionCategoryId"
FULL JOIN concessions              AS con
    ON con_sub.id = con."subcategoryId"
FULL JOIN concession_groups        AS con_gr
    ON con."groupId" = con_gr.id
WHERE ci.id != 0
  AND ci.id = 2
ORDER BY
    ci.id      DESC,
    con_cat.id DESC,
    con_sub.id DESC,
    con.id     DESC;


SELECT
    ci.id              AS city_id,
    ci.name            AS city_name,
    con_cat.id         AS con_cat_id,
    con_cat.name       AS con_cat_name,
    con_sub.id         AS con_sub_id,
    con_sub.name       AS con_sub_name,
    con_gr.id          AS con_gr_id,
    con_gr.name        AS con_gr_name,
    con_ru.*,
    con.id             AS con_id,
    con.name           AS con_name,
    con."showOnCreate" AS con_is_issue,
    con."isHidden"     AS con_is_hidden
FROM cities                        AS ci
FULL JOIN concession_categories    AS con_cat
    ON ci.id = con_cat."cityId"
FULL JOIN concession_subcategories AS con_sub
    ON con_cat.id = con_sub."concessionCategoryId"
FULL JOIN concessions              AS con
    ON con_sub.id = con."subcategoryId"
FULL JOIN concession_groups        AS con_gr
    ON con."groupId" = con_gr.id
FULL JOIN concession_rules         AS con_ru
    ON con_gr.id = con_ru."concessionGroupId"
WHERE ci.id != 0
  AND ci.id = 2
--   AND con_sub.id = 30
ORDER BY
    ci.id      DESC,
    con_cat.id DESC,
    con_sub.id DESC,
    con.id     DESC;

SELECT
    *
FROM concession_rules
WHERE "concessionGroupId" = 22


SELECT
    DISTINCT(con_sub.name)
FROM concession_categories AS con_cat
INNER JOIN concession_subcategories AS con_sub
    ON con_cat.id = con_sub."concessionCategoryId"
WHERE con_cat."cityId" = 2


SELECT
    cus.iin,
    con.name,
    cus_ca.pan,
    cus_ca."cardType",
    ct_ti.title_ru
FROM customers AS cus
INNER JOIN customer_concessions AS cus_con
    ON cus.id = cus_con."customerId"
INNER JOIN concessions AS con
    ON cus_con."concessionId" = con.id
INNER JOIN customer_cards AS cus_ca
    ON cus_con.id = cus_ca."customerConcessionId"
INNER JOIN ct_card_titles AS ct_ti
    ON cus_ca."cardType" = ct_ti.nn
WHERE cus.iin IS NOT NULL
AND con.id NOT IN (0, 15, 90, 294, 295)
AND ct_ti.nn = '20.50'


