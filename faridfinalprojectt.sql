-- 1. COUNTRIES (əsas cədvəl)
CREATE TABLE military_countries (
    country                VARCHAR2(100) PRIMARY KEY,
    region                 VARCHAR2(50),
    gfp_rank               NUMBER,
    military_power_score   NUMBER(10,2),
    military_rank          NUMBER,
    defense_budget_pct_gdp NUMBER(10,2)
);

-- 2. FINANCE
CREATE TABLE military_finance (
    country            VARCHAR2(100) PRIMARY KEY,
    fin_ppp            NUMBER,
    fin_fx_gold        NUMBER,
    fin_defense_budget NUMBER,
    fin_external_debt  NUMBER,
    CONSTRAINT fk_finance FOREIGN KEY (country)
    REFERENCES military_countries(country)
);

-- 3. MANPOWER
CREATE TABLE military_manpower (
    country                       VARCHAR2(100) PRIMARY KEY,
    man_population                NUMBER,
    man_available                 NUMBER,
    man_fit_for_service           NUMBER,
    man_mil_age_annual            NUMBER,
    man_total_personnel           NUMBER,
    man_active                    NUMBER,
    man_reserve                   NUMBER,
    man_paramilitary              NUMBER,
    yearly_mobilization_potential NUMBER,
    mobilization_6_12mos          NUMBER,
    mobilization_year_2           NUMBER,
    mobilization_year_3           NUMBER,
    mobilization_year_4           NUMBER,
    CONSTRAINT fk_manpower FOREIGN KEY (country)
    REFERENCES military_countries(country)
);



-- 5. LAND
CREATE TABLE military_land (
    country                       VARCHAR2(100) PRIMARY KEY,
    land_personnel                NUMBER,
    land_tanks                    NUMBER,
    land_vehicles                 NUMBER,
    land_self_propelled_artillery NUMBER,
    land_towed_artillery          NUMBER,
    land_mlrs                     NUMBER,
    CONSTRAINT fk_land FOREIGN KEY (country)
    REFERENCES military_countries(country)
);

-- 6. NAVAL
CREATE TABLE military_naval (
    country                   VARCHAR2(100) PRIMARY KEY,
    naval_personnel           NUMBER,
    naval_total_assets        NUMBER,
    naval_total_tonnage       NUMBER,
    naval_aircraft_carriers   NUMBER,
    naval_helicopter_carriers NUMBER,
    naval_destroyers          NUMBER,
    naval_frigates            NUMBER,
    naval_corvettes           NUMBER,
    naval_submarines          NUMBER,
    naval_patrol_vessels      NUMBER,
    naval_mine_warfare        NUMBER,
    CONSTRAINT fk_naval FOREIGN KEY (country)
    REFERENCES military_countries(country)
);

-- 7. ENERGY + INFRA
CREATE TABLE military_energy_infra (
    country              VARCHAR2(100) PRIMARY KEY,
    nrg_oil_production   NUMBER,
    nrg_oil_consumption  NUMBER,
    nrg_oil_balance      NUMBER,
    nrg_oil_reserves     NUMBER,
    nrg_gas_production   NUMBER,
    nrg_gas_consumption  NUMBER,
    nrg_gas_balance      NUMBER,
    nrg_gas_reserves     NUMBER,
    nrg_coal_production  NUMBER,
    nrg_coal_consumption NUMBER,
    nrg_coal_balance     NUMBER,
    nrg_coal_reserves    NUMBER,
    infra_internet       NUMBER,
    infra_labor_force    NUMBER,
    infra_merchant_fleet NUMBER,
    infra_ports          NUMBER,
    infra_airports       NUMBER,
    infra_roads          NUMBER,
    infra_railways       NUMBER,
    CONSTRAINT fk_energy FOREIGN KEY (country)
    REFERENCES military_countries(country)
);


CREATE TABLE military_air (
    country                VARCHAR2(100) PRIMARY KEY,
    air_personnel          NUMBER,
    air_aircraft_total     NUMBER,
    air_fighters           NUMBER,
    air_attack_types       NUMBER,
    air_transports         NUMBER,
    air_trainers           NUMBER,
    air_special_mission    NUMBER,
    air_tanker_fleet       NUMBER,
    air_helicopters        NUMBER,
    air_attack_helicopters NUMBER,
    CONSTRAINT fk_air FOREIGN KEY (country)
    REFERENCES military_countries(country)
);
COMMIT;

SELECT 'countries' AS tbl, COUNT(*) AS cnt FROM military_countries UNION ALL
SELECT 'finance',          COUNT(*) FROM military_finance UNION ALL
SELECT 'manpower',         COUNT(*) FROM military_manpower UNION ALL
SELECT 'air',              COUNT(*) FROM military_air UNION ALL
SELECT 'land',             COUNT(*) FROM military_land UNION ALL
SELECT 'naval',            COUNT(*) FROM military_naval UNION ALL
SELECT 'energy_infra',     COUNT(*) FROM military_energy_infra;






--  JOIN 
SELECT 
    c.country, c.region, c.gfp_rank, c.military_power_score,
    f.fin_defense_budget, f.fin_ppp,
    m.man_active, m.man_reserve,
    a.air_fighters, a.air_aircraft_total,
    l.land_tanks, l.land_vehicles,
    n.naval_submarines, n.naval_destroyers,
    e.nrg_oil_production
FROM military_countries c
JOIN military_finance f ON c.country = f.country
JOIN military_manpower m ON c.country = m.country
JOIN military_air a ON c.country = a.country
JOIN military_land l ON c.country = l.country
JOIN military_naval n ON c.country = n.country
JOIN military_energy_infra e ON c.country = e.country
ORDER BY c.gfp_rank
FETCH FIRST 10 ROWS ONLY;


-- 2. RANK + PARTITION BY 
SELECT * FROM (
    SELECT 
        c.country, c.region, c.military_power_score,
        f.fin_defense_budget,
        a.air_fighters,
        l.land_tanks,
        n.naval_submarines,
        RANK() OVER (PARTITION BY c.region ORDER BY c.military_power_score DESC) AS region_rank
    FROM military_countries c
    JOIN military_finance f ON c.country = f.country
    JOIN military_air a ON c.country = a.country
    JOIN military_land l ON c.country = l.country
    JOIN military_naval n ON c.country = n.country
)
WHERE region_rank = 1
ORDER BY military_power_score DESC;


-- 3. CTE -- hava + qara + dəniz skoru
WITH scores AS (
    SELECT 
        c.country, c.region,
        (a.air_fighters + a.air_attack_types + a.air_attack_helicopters) AS air_score,
        (l.land_tanks + l.land_vehicles + l.land_mlrs) AS land_score,
        (n.naval_destroyers + n.naval_frigates + n.naval_submarines) AS naval_score
    FROM military_countries c
    JOIN military_air a ON c.country = a.country
    JOIN military_land l ON c.country = l.country
    JOIN military_naval n ON c.country = n.country
),
ranked AS (
    SELECT *,
        RANK() OVER (ORDER BY air_score DESC) AS air_rank,
        RANK() OVER (ORDER BY land_score DESC) AS land_rank,
        RANK() OVER (ORDER BY naval_score DESC) AS naval_rank
    FROM scores
)
SELECT * FROM ranked
ORDER BY air_rank
FETCH FIRST 15 ROWS ONLY;


-- 4. ROLLUP -- region üzrə büdcə cəmi
SELECT 
    COALESCE(c.region, 'TOTAL') AS region,
    COUNT(c.country) AS country_count,
    SUM(f.fin_defense_budget) AS total_budget,
    ROUND(AVG(c.military_power_score), 2) AS avg_score,
    SUM(m.man_active) AS total_active
FROM military_countries c
JOIN military_finance f ON c.country = f.country
JOIN military_manpower m ON c.country = m.country
GROUP BY ROLLUP(c.region)
ORDER BY total_budget DESC NULLS LAST;


-- 5. CORRELATED SUBQUERY -- regionda ortalamadan güclü ölkələr
SELECT 
    c.country, c.region, c.military_power_score,
    f.fin_defense_budget
FROM military_countries c
JOIN military_finance f ON c.country = f.country
WHERE c.military_power_score > (
    SELECT AVG(c2.military_power_score)
    FROM military_countries c2
    WHERE c2.region = c.region
)
ORDER BY c.region, c.military_power_score DESC;


-- 6. LAG + LEAD -- GFP sıralamasında əvvəlki və növbəti ölkə
SELECT 
    c.country, c.gfp_rank, c.military_power_score,
    f.fin_defense_budget,
    LAG(c.country) OVER (ORDER BY c.gfp_rank) AS prev_country,
    LEAD(c.country) OVER (ORDER BY c.gfp_rank) AS next_country,
    c.military_power_score - LAG(c.military_power_score) 
        OVER (ORDER BY c.gfp_rank) AS score_diff
FROM military_countries c
JOIN military_finance f ON c.country = f.country
ORDER BY c.gfp_rank
FETCH FIRST 20 ROWS ONLY;


-- 7. NTILE -- ölkələri 4 qrupa böl
SELECT 
    c.country, c.region, c.military_power_score,
    f.fin_defense_budget,
    NTILE(4) OVER (ORDER BY c.military_power_score DESC) AS quartile,
    CASE NTILE(4) OVER (ORDER BY c.military_power_score DESC)
        WHEN 1 THEN 'Superpower'
        WHEN 2 THEN 'Strong'
        WHEN 3 THEN 'Medium'
        WHEN 4 THEN 'Weak'
    END AS power_category
FROM military_countries c
JOIN military_finance f ON c.country = f.country
ORDER BY c.military_power_score DESC;


-- 8. CASE WHEN + JOIN -- enerji zənginliyi analizi
SELECT 
    c.country, c.region,
    e.nrg_oil_production, e.nrg_oil_consumption,
    CASE 
        WHEN e.nrg_oil_balance > 0 THEN 'İxracatçı'
        WHEN e.nrg_oil_balance < 0 THEN 'İdxalçı'
        ELSE 'Balansda'
    END AS oil_status,
    CASE
        WHEN e.nrg_oil_production > 1000000 THEN 'Böyük İstehsalçı'
        WHEN e.nrg_oil_production > 100000  THEN 'Orta İstehsalçı'
        WHEN e.nrg_oil_production > 0       THEN 'Kiçik İstehsalçı'
        ELSE 'İstehsal Yoxdur'
    END AS production_category
FROM military_countries c
JOIN military_energy_infra e ON c.country = e.country
ORDER BY e.nrg_oil_production DESC
FETCH FIRST 20 ROWS ONLY;


-- 9. FIRST_VALUE -- regiondakı ən güclü ölkəni hər sətirdə göstər
SELECT 
    c.country, c.region, c.military_power_score,
    l.land_tanks, a.air_fighters, n.naval_submarines,
    FIRST_VALUE(c.country) OVER 
        (PARTITION BY c.region ORDER BY c.military_power_score DESC) AS region_leader
FROM military_countries c
JOIN military_land l ON c.country = l.country
JOIN military_air a ON c.country = a.country
JOIN military_naval n ON c.country = n.country
ORDER BY c.region, c.military_power_score DESC;


-- 10. VIEW 
CREATE OR REPLACE VIEW v_military_full AS
SELECT 
    c.country, c.region, c.gfp_rank,
    c.military_power_score, c.defense_budget_pct_gdp,
    f.fin_ppp, f.fin_defense_budget,
    m.man_active, m.man_reserve,
    a.air_fighters, a.air_aircraft_total, a.air_helicopters,
    l.land_tanks, l.land_vehicles, l.land_mlrs,
    n.naval_submarines, n.naval_destroyers, n.naval_aircraft_carriers,
    e.nrg_oil_production, e.nrg_oil_balance,
    e.infra_airports, e.infra_roads,
    RANK() OVER (ORDER BY c.military_power_score DESC) AS power_rank,
    RANK() OVER (PARTITION BY c.region ORDER BY c.military_power_score DESC) AS region_rank,
    NTILE(4) OVER (ORDER BY c.military_power_score DESC) AS power_quartile
FROM military_countries c
JOIN military_finance f ON c.country = f.country
JOIN military_manpower m ON c.country = m.country
JOIN military_air a ON c.country = a.country
JOIN military_land l ON c.country = l.country
JOIN military_naval n ON c.country = n.country
JOIN military_energy_infra e ON c.country = e.country;

SELECT * FROM v_military_full ORDER BY power_rank;
