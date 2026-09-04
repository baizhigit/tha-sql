
-- вся информация по картам 

SELECT
    t.nn,
    t.title_ru,
    t.title_kk,
    t.title_en,
    c.primary_color,
    c.bg_color,
    c.text_color,
    c.icon_color,
    c.shadow_color,
    (j.key)::INT   AS city_id,
    (j.value->>'tripCost')::INT AS trip_cost,
    (j.value->>'passCost')::INT AS pass_cost
FROM ct_card_titles AS t
LEFT JOIN ct_card_colors AS c
    ON c.nn = t.nn
    AND c.is_virtual = FALSE
JOIN ct_card_tariffs AS tr
    ON tr.nn = t.nn
CROSS JOIN LATERAL jsonb_each(tr.tariffs_json) AS j(key, value)
-- WHERE t.nn = '60.50'
ORDER BY city_id;



SELECT 
    ctc.id,
    ctc."concessionId",
    ctc."cardTypeId",
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
    cc.name AS category
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
LEFT JOIN public.cities ci ON ci.id = cc."cityId";

