
-- просмотр тарифов развернуто json

SELECT
    t.nn,
    (j.key)::INT    AS city_id,
    (j.value->>'tripCost')::INT AS trip_cost,
    (j.value->>'passCost')::INT AS pass_cost
FROM ct_card_tariffs t
CROSS JOIN LATERAL
    jsonb_each(t.tariffs_json) AS j(key, value)
ORDER BY t.nn, city_id;