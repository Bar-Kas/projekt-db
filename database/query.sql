-- ==============================================================================
-- PLIK: query.sql
-- OPIS: Zbiór wszystkich zapytań wykorzystywanych w cyklu życia aplikacji
--       oraz zapytania analityczne udowadniające działanie bazy danych.
-- ==============================================================================

-- ==============================================================================
-- 1. ZAAWANSOWANE ZAPYTANIA ANALITYCZNE I STATYSTYCZNE (Wymóg: Min. 15 zapytań)
-- ==============================================================================

-- 1.1. [HAVING & GROUP BY] Średnia cena biletów dla poszczególnych gatunków, 
-- gdzie średnia cena jest większa niż 30 PLN.
SELECT g.name, AVG(t.final_price) as avg_price
FROM genres g
JOIN spectacles s ON s.genre_id = g.id
JOIN seances se ON se.spectacle_id = s.id
JOIN reservations r ON r.seance_id = se.id
JOIN tickets t ON t.reservation_id = r.id
GROUP BY g.name
HAVING AVG(t.final_price) > 30;

-- 1.2. [EXISTS & PODZAPYTANIE SKORELOWANE] Aktorzy grający w spektaklach 
-- o gatunku 'Dramat'.
SELECT p.first_name, p.last_name 
FROM actors a
JOIN persons p ON a.person_id = p.id
WHERE EXISTS (
    SELECT 1 FROM spectacle_actors sa
    JOIN spectacles s ON sa.spectacle_id = s.id
    JOIN genres g ON s.genre_id = g.id
    WHERE sa.actor_id = a.person_id AND g.name = 'Dramat'
);

-- 1.3. [ALL] Spektakle, które trwają dłużej niż każdy z musicali.
SELECT title, duration_minutes 
FROM spectacles
WHERE duration_minutes > ALL (
    SELECT duration_minutes FROM spectacles 
    JOIN genres ON spectacles.genre_id = genres.id 
    WHERE genres.name = 'Musical'
);

-- 1.4. [PODZAPYTANIE NIESKORELOWANE] Pracownicy zarabiający powyżej średniej.
SELECT p.first_name, p.last_name, e.salary 
FROM employees e
JOIN persons p ON e.person_id = p.id
WHERE e.salary > (SELECT AVG(salary) FROM employees);

-- 1.5. [ANY] (DODANE) Aktorzy, którzy zarabiają więcej (podstawa) niż jakikolwiek 
-- pracownik z 'Zespołu Artystycznego'.
SELECT p.first_name, p.last_name, a.base_salary 
FROM actors a
JOIN persons p ON a.person_id = p.id
WHERE a.base_salary > ANY (
    SELECT e.salary FROM employees e 
    JOIN departments d ON e.department_id = d.id 
    WHERE d.name = 'Zespół Artystyczny'
);

-- 1.6. [LIKE / ILIKE] (DODANE) Wyszukiwanie spektakli po fragmencie tytułu.
SELECT s.*, g.name as genre_name 
FROM spectacles s 
LEFT JOIN genres g ON s.genre_id = g.id 
WHERE s.title ILIKE '%WyszukiwanaFraza%' 
ORDER BY s.premiere_date DESC;

-- 1.7. [IN & NOT IN] Aktorzy, którzy NIE grają w konkretnym spektaklu (ID: 1).
SELECT a.person_id as id, p.first_name, p.last_name 
FROM actors a 
JOIN persons p ON a.person_id = p.id
WHERE a.person_id NOT IN (
    SELECT actor_id FROM spectacle_actors WHERE spectacle_id = 1
)
ORDER BY p.last_name;


-- ==============================================================================
-- 2. ZAPYTANIA RAPORTOWE (Używane przy generowaniu plików PDF)
-- ==============================================================================

-- 2.1. Przychody ze sprzedaży biletów pogrupowane po gatunkach i spektaklach 
-- w danym przedziale czasu.
SELECT g.name as genre, s.title, COUNT(t.id) as tickets, COALESCE(SUM(t.final_price), 0) as income
FROM genres g
JOIN spectacles s ON s.genre_id = g.id
LEFT JOIN seances se ON se.spectacle_id = s.id
LEFT JOIN reservations r ON r.seance_id = se.id
LEFT JOIN tickets t ON t.reservation_id = r.id
WHERE se.start_time >= '2025-01-01' AND se.start_time <= '2025-12-31'
GROUP BY g.name, s.title
ORDER BY g.name, income DESC;

-- 2.2. Koszty wynagrodzeń aktorów występujących w danym okresie.
SELECT COALESCE(SUM(sub.base_salary), 0) as total_salaries
FROM (
    SELECT DISTINCT a.person_id, a.base_salary
    FROM actors a
    JOIN spectacle_actors sa ON a.person_id = sa.actor_id
    JOIN seances se ON sa.spectacle_id = se.spectacle_id
    WHERE se.start_time >= '2025-01-01' AND se.start_time <= '2025-12-31'
) sub;

-- 2.3. Całkowite koszty wynagrodzeń stałych pracowników.
SELECT COALESCE(SUM(salary), 0) as total_emp_salaries FROM employees;

-- 2.4. Raport struktury organizacyjnej - pracownicy, ich działy i przełożeni.
SELECT p.first_name, p.last_name, p.email, e.salary, 
       pm.last_name as manager_name, pm.first_name as manager_first, d.name as dept
FROM employees e
JOIN persons p ON e.person_id = p.id
LEFT JOIN employees m ON e.manager_id = m.person_id
LEFT JOIN persons pm ON m.person_id = pm.id
JOIN departments d ON e.department_id = d.id
ORDER BY d.name, e.salary DESC;

-- 2.5. Wykres finansowy - Top 5 najlepiej zarabiających spektakli.
SELECT title, SUM(t.final_price) as total
FROM spectacles s
JOIN seances se ON se.spectacle_id = s.id
JOIN reservations r ON r.seance_id = se.id
JOIN tickets t ON t.reservation_id = r.id
GROUP BY title 
ORDER BY total DESC 
LIMIT 5;

-- 2.6. Dzienne przychody w danym okresie (do wykresu słupkowego w panelu admina).
SELECT TO_CHAR(se.start_time, 'YYYY-MM-DD') as day, COALESCE(SUM(t.final_price),0) as revenue
FROM tickets t 
JOIN reservations r ON t.reservation_id = r.id
JOIN seances se ON r.seance_id = se.id
WHERE se.start_time >= '2025-01-01' AND se.start_time <= '2025-12-31'
GROUP BY day 
ORDER BY day ASC;


-- ==============================================================================
-- 3. ZAPYTANIA Z PANELU ADMINISTRATORA (DML: Pobieranie, Edycja, Usuwanie)
-- ==============================================================================

-- 3.1. Symulacja logowania admina
SELECT u.person_id, u.role, p.first_name, p.last_name 
FROM users u 
JOIN persons p ON u.person_id = p.id 
WHERE u.role = 'admin' LIMIT 1;

-- 3.2. Widoki panelu głównego
SELECT s.*, g.name as genre_name FROM spectacles s LEFT JOIN genres g ON s.genre_id = g.id ORDER BY s.id DESC;
SELECT se.id, s.title, se.start_time, se.base_price, h.name as hall FROM seances se JOIN spectacles s ON se.spectacle_id = s.id JOIN halls h ON se.hall_id = h.id ORDER BY se.start_time;
SELECT title, sold_tickets as tickets_sold, revenue FROM v_financial_report ORDER BY revenue DESC LIMIT 10;
SELECT p.first_name, p.last_name, e.* FROM employees e JOIN persons p ON e.person_id = p.id ORDER BY p.last_name LIMIT 5;

-- 3.3. Zarządzanie spektaklami (Zapis)
INSERT INTO spectacles (title, description, duration_minutes, poster_url, genre_id, premiere_date) 
VALUES ('Nowy Spektakl', 'Opis spektaklu', 120, 'temp', 1, NOW()) RETURNING id;

UPDATE spectacles SET poster_url = '/images/poster-123.jpg' WHERE id = 1;
UPDATE spectacles SET title='Tytuł', description='Opis', duration_minutes=100, genre_id=2 WHERE id=1;

DELETE FROM seances WHERE id = 500 AND status = 'cancelled';

-- 3.4. Zarządzanie obsadą
SELECT sa.actor_id, p.first_name, p.last_name, sa.role_name FROM spectacle_actors sa JOIN actors a ON sa.actor_id = a.person_id JOIN persons p ON a.person_id = p.id WHERE sa.spectacle_id = 1;

INSERT INTO spectacle_actors (spectacle_id, actor_id, role_name) VALUES (1, 2, 'Główna Rola');
DELETE FROM spectacle_actors WHERE spectacle_id = 1 AND actor_id = 2;

-- 3.5. Zarządzanie Seanse
INSERT INTO seances (spectacle_id, hall_id, start_time, base_price) VALUES (1, 1, '2025-12-12 18:00', 50.00);
UPDATE seances SET spectacle_id=1, hall_id=2, start_time='2025-12-13 19:00', base_price=60.00 WHERE id=1;

-- 3.6. Zarządzanie Aktorami (Dodawanie osoby i aktora w transakcji)
INSERT INTO persons (first_name, last_name, email) VALUES ('Jan', 'Kowalski', 'jan@test.pl') RETURNING id;
INSERT INTO actors (person_id, bio, base_salary) VALUES (1, 'Krótkie bio', 4000);

UPDATE persons SET first_name='Janusz', last_name='Nowak', email='nowak@test.pl' WHERE id=1;
UPDATE actors SET base_salary=4500, bio='Nowe bio' WHERE person_id=1;

SELECT a.person_id as id, p.first_name, p.last_name, a.base_salary, COUNT(sa.spectacle_id) as roles_count 
FROM actors a 
JOIN persons p ON a.person_id = p.id
LEFT JOIN spectacle_actors sa ON a.person_id = sa.actor_id 
GROUP BY a.person_id, p.first_name, p.last_name 
ORDER BY p.last_name ASC;

-- 3.7. Wywołanie procedury składowanej
CALL update_seance_prices(10.0); -- Zmiana cen o +10%


-- ==============================================================================
-- 4. STRONA PUBLICZNA I KLIENCKA (Aplikacja dla widza)
-- ==============================================================================

-- 4.1. Pobranie wszystkich spektakli z gatunkami na stronę główną
SELECT s.*, g.name as genre_name 
FROM spectacles s 
LEFT JOIN genres g ON s.genre_id = g.id 
ORDER BY s.premiere_date DESC;

-- 4.2. Szczegóły spektaklu, jego seanse, obsada i recenzje
SELECT s.*, g.name as genre_name FROM spectacles s LEFT JOIN genres g ON s.genre_id = g.id WHERE s.id=1;
SELECT s.*, h.name as hall_name FROM seances s JOIN halls h ON s.hall_id=h.id WHERE s.spectacle_id=1 AND s.start_time > NOW();
SELECT p.first_name, p.last_name, a.*, sa.role_name FROM actors a JOIN persons p ON a.person_id = p.id JOIN spectacle_actors sa ON a.person_id=sa.actor_id WHERE sa.spectacle_id=1;
SELECT r.*, u.username FROM reviews r JOIN users u ON r.user_id=u.person_id WHERE r.spectacle_id=1;

-- 4.3. Dodawanie recenzji
INSERT INTO reviews (user_id, spectacle_id, rating, comment) VALUES (1, 1, 5, 'Świetny spektakl!');

-- 4.4. Widok Rezerwacji - Pobieranie informacji o miejscach i seansie
SELECT se.*, s.title, h.name as hall_name FROM seances se JOIN spectacles s ON se.spectacle_id = s.id JOIN halls h ON se.hall_id = h.id WHERE se.id=1;
SELECT * FROM seats WHERE hall_id=1 ORDER BY grid_y, grid_x;
SELECT seat_id FROM tickets t JOIN reservations r ON t.reservation_id=r.id WHERE r.seance_id=1;

-- 4.5. Obsługa Rezerwacji Miejsca (Transakcja)
INSERT INTO reservations (user_id, seance_id) VALUES (1, 1) RETURNING id;
SELECT base_price FROM seances WHERE id=1;
INSERT INTO tickets (reservation_id, seat_id, final_price, ticket_token) VALUES (1, 50, 45.00, md5(random()::text));

SELECT t.seat_id, s.row_label, s.number 
FROM tickets t 
JOIN reservations r ON t.reservation_id = r.id 
JOIN seats s ON t.seat_id = s.id
WHERE r.seance_id = (
    SELECT r2.seance_id 
    FROM reservations r2 
    JOIN tickets t2 ON r2.id = t2.reservation_id 
    LIMIT 1
);