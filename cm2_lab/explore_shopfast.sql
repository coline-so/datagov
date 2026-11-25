-- CM 2 lab (24 Nov) - Explore the ShopFast raw data
-- Run in psql:  docker exec -it shopfast-db psql -U shopfast_admin -d shopfast
-- (or any SQL client: host localhost, port 5432, db shopfast, user/password shopfast_admin)

-- 1. Which tables exist?
\dt raw.*

-- 2. How many rows per table?
SELECT 'customers' AS t, count(*) FROM raw.customers
UNION ALL SELECT 'products', count(*) FROM raw.products
UNION ALL SELECT 'orders', count(*) FROM raw.orders
UNION ALL SELECT 'order_items', count(*) FROM raw.order_items
UNION ALL SELECT 'payments', count(*) FROM raw.payments
UNION ALL SELECT 'support_tickets', count(*) FROM raw.support_tickets
UNION ALL SELECT 'marketing_campaign_export', count(*) FROM raw.marketing_campaign_export;

-- 3. Look at 10 rows of a table (change the name)
SELECT * FROM raw.customers LIMIT 10;

-- 4. How many distinct values does a column have? (good for spotting inconsistent codes)
SELECT country, count(*) FROM raw.customers GROUP BY country ORDER BY 2 DESC;

-- 5. How many empty values?
SELECT count(*) FILTER (WHERE email IS NULL OR email = '') AS empty_emails FROM raw.customers;

-- 6. Is the "id" really unique?
SELECT customer_id, count(*) FROM raw.customers GROUP BY customer_id HAVING count(*) > 1;

-- 7. Your own queries below: try orders.status, orders.order_date, products.category ...
-- 7a. order_items : produits absents du catalogue
SELECT oi.product_id, count(*) AS nb_items
FROM raw.order_items oi
LEFT JOIN raw.products p ON p.product_id = oi.product_id
WHERE p.product_id IS NULL
GROUP BY 1;

-- 7b. payments : commandes sans paiement, par statut de commande
SELECT o.status, count(*) AS nb_orders_without_payment
FROM (SELECT DISTINCT order_id, status FROM raw.orders) o
LEFT JOIN raw.payments p ON p.order_id = o.order_id
WHERE p.order_id IS NULL
GROUP BY 1 ORDER BY 2 DESC;

-- 7c. payments : paiements dont la commande n'existe pas
SELECT count(*) AS payments_without_order
FROM raw.payments p
LEFT JOIN (SELECT DISTINCT order_id FROM raw.orders) o ON o.order_id = p.order_id
WHERE o.order_id IS NULL;

-- 7d. payments : montant identique au total commande, ou x100 (centimes) ?
SELECT count(*) AS compared,
       count(*) FILTER (WHERE p.amount::numeric = o.total_amount_eur::numeric) AS same_as_order,
       count(*) FILTER (WHERE p.amount::numeric = o.total_amount_eur::numeric * 100) AS in_cents,
       max(p.amount::numeric) AS max_amount
FROM raw.payments p
JOIN (SELECT DISTINCT order_id, total_amount_eur FROM raw.orders) o ON o.order_id = p.order_id
WHERE p.amount ~ '^-?[0-9]+(\.[0-9]+)?$'
  AND o.total_amount_eur ~ '^-?[0-9]+(\.[0-9]+)?$';

-- 7e. payments : card_last4 manquant selon le moyen de paiement
SELECT method, count(*) AS total,
       count(*) FILTER (WHERE card_last4 IS NULL OR card_last4 = '') AS missing_card
FROM raw.payments GROUP BY 1 ORDER BY 1;

-- 7f. marketing : valeurs de consentement dans customers
SELECT marketing_consent, count(*)
FROM (SELECT DISTINCT customer_id, marketing_consent FROM raw.customers) c
GROUP BY 1;

-- 7g. marketing : consentement des clients exportés (NULL = client introuvable)
SELECT c.marketing_consent, count(*) AS nb_exported
FROM raw.marketing_campaign_export m
LEFT JOIN (SELECT DISTINCT customer_id, marketing_consent FROM raw.customers) c
       ON c.customer_id = m.customer_id
GROUP BY 1;

-- 7h. support_tickets : données personnelles dans les messages et les notes
SELECT
  count(*) FILTER (WHERE message ~ '\m[A-Z]{2}[0-9]{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\M') AS iban_in_message,
  count(*) FILTER (WHERE message LIKE '%Name on the account%') AS account_holder_name,
  count(*) FILTER (WHERE message LIKE '%@%') AS email_in_message,
  count(*) FILTER (WHERE message LIKE '%call me on%') AS phone_in_message,
  count(*) FILTER (WHERE agent_notes ~ 'born [0-9]{4}-[0-9]{2}-[0-9]{2}') AS birthdate_in_agent_notes,
  count(*) FILTER (WHERE agent_notes IS NULL OR agent_notes = '') AS empty_agent_notes
FROM raw.support_tickets;

-- 7i. support_tickets : IBAN valides (clé modulo 97)
SELECT count(*) AS iban_valid_mod97
FROM (
  SELECT regexp_replace((regexp_match(message,
         '\m[A-Z]{2}[0-9]{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\M'))[1], '\s', '', 'g') AS iban
  FROM raw.support_tickets
) i
WHERE iban IS NOT NULL
  AND (SELECT string_agg(CASE WHEN ch ~ '[A-Z]' THEN (ascii(ch) - 55)::text ELSE ch END, '' ORDER BY n)
       FROM regexp_split_to_table(substr(iban, 5) || substr(iban, 1, 4), '') WITH ORDINALITY AS t(ch, n)
      )::numeric % 97 = 1;

-- 7l. customers : formats de dates
SELECT 'birth_date' AS col, regexp_replace(birth_date, '[0-9]', '9', 'g') AS format, count(*)
FROM raw.customers GROUP BY 1, 2
UNION ALL
SELECT 'signup_date', regexp_replace(signup_date, '[0-9]', '9', 'g'), count(*)
FROM raw.customers GROUP BY 1, 2
ORDER BY 1, 3 DESC;

-- 7m. colonnes stockées en texte
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'raw'
  AND ((table_name = 'customers' AND column_name IN ('birth_date', 'signup_date'))
    OR (table_name = 'order_items' AND column_name IN ('quantity', 'unit_price_eur')))
ORDER BY 1, 2;

-- 7n. customers : emails invalides par cause
SELECT CASE
         WHEN email <> trim(email) THEN 'leading/trailing space'
         WHEN length(email) - length(replace(email, '@', '')) > 1 THEN 'double @'
         WHEN email LIKE '%@' THEN 'nothing after @'
         ELSE 'other malformed' END AS problem,
       count(*)
FROM raw.customers
WHERE email <> '' AND email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
GROUP BY 1 ORDER BY 2 DESC;

-- 7o. customers : téléphones manquants
SELECT count(*) AS missing_phones FROM raw.customers WHERE phone IS NULL OR phone = '';

-- 7p. customers : date de naissance et adresse présentes ensemble (niveau Restricted)
SELECT count(*) AS rows_with_birth_date_and_address
FROM raw.customers WHERE birth_date <> '' AND address <> '';

-- 7q. products : produits partageant le même sku
SELECT product_id, product_name, sku FROM raw.products WHERE sku = 'SF-FAS-0522';

-- 7r. products : prix manquant ou négatif
SELECT product_id, product_name, unit_price_eur FROM raw.products
WHERE unit_price_eur IS NULL OR unit_price_eur = '' OR NULLIF(unit_price_eur, '')::numeric < 0;

-- 7s. products : catégories avec espace ou mauvaise casse
SELECT product_id, product_name, '[' || category || ']' AS category_raw
FROM raw.products
WHERE category <> trim(category) OR category <> initcap(trim(category));

-- 7t. orders : doublons, dates manquantes, statuts avec espace
SELECT count(*) AS total_rows,
       count(DISTINCT order_id) AS distinct_order_id,
       count(*) - (SELECT count(*) FROM (SELECT DISTINCT * FROM raw.orders) d) AS fully_duplicated_rows,
       count(*) FILTER (WHERE order_date IS NULL OR order_date = '') AS missing_order_date,
       count(*) FILTER (WHERE status <> trim(status)) AS status_with_space
FROM raw.orders;

-- 7u. support_tickets : sujet incohérent avec le message
SELECT subject, count(*) FROM raw.support_tickets
WHERE message LIKE 'Great service%'
  AND subject IN ('Damaged item', 'Refund request', 'Payment declined', 'Delete my account')
GROUP BY 1 ORDER BY 2 DESC;

-- 7v. marketing : emails de l'export différents de ceux de customers
SELECT count(*) AS different_from_customers,
       count(*) FILTER (WHERE c.email IS NULL OR c.email = '') AS source_empty,
       count(*) FILTER (WHERE c.email LIKE '%@') AS source_truncated,
       count(*) FILTER (WHERE c.email LIKE '%@@%') AS source_double_at
FROM raw.marketing_campaign_export m
JOIN (SELECT DISTINCT customer_id, email FROM raw.customers) c USING (customer_id)
WHERE c.email IS DISTINCT FROM m.email;

-- 7w. marketing : emails avec caractères non ASCII
SELECT email FROM raw.marketing_campaign_export WHERE email ~ '[^ -~]';

-- 7x. marketing : colonnes de l'export (y a-t-il une colonne de consentement ?)
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'raw' AND table_name = 'marketing_campaign_export' ORDER BY ordinal_position;