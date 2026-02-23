-- KROK 1: RESET BAZY
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

-- ==========================================
-- KROK 2: TWORZENIE TABEL (ENCJE)
-- ==========================================

-- Tabela: persons (Osoby)
-- Zależności: Hierarchia encji (Supertyp)
CREATE TABLE persons (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE
);

-- Tabela: departments (Działy)
-- Zależności: Brak
CREATE TABLE departments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    budget DECIMAL(12,2) DEFAULT 0.00
);

-- Tabela: employees (Pracownicy)
-- Zależności: 
-- 1. Podtyp tabeli persons (person_id)
-- 2. Udział obowiązkowy w departments (department_id NOT NULL)
-- 3. Związek unarny opcjonalny w employees (manager_id)
CREATE TABLE employees (
    person_id INT PRIMARY KEY REFERENCES persons(id) ON DELETE CASCADE,
    hire_date DATE DEFAULT CURRENT_DATE,
    salary DECIMAL(10,2),
    department_id INT NOT NULL REFERENCES departments(id),
    manager_id INT REFERENCES employees(person_id), 
    CONSTRAINT check_salary_positive CHECK (salary > 0)
);

-- Tabela: users (Użytkownicy)
-- Zależności: Podtyp tabeli persons (person_id)
CREATE TABLE users (
    person_id INT PRIMARY KEY REFERENCES persons(id) ON DELETE CASCADE,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) CHECK (role IN ('admin', 'client', 'staff')) DEFAULT 'client',
    loyalty_points INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Tabela: halls (Sale)
-- Zależności: Brak
CREATE TABLE halls (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    capacity INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE
);

-- Tabela: seat_categories (Kategorie Miejsc)
-- Zależności: Brak
CREATE TABLE seat_categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    base_multiplier DECIMAL(3,2) DEFAULT 1.00,
    description TEXT
);

-- Tabela: seats (Miejsca)
-- Zależności: Udział obowiązkowy w halls (hall_id NOT NULL) i seat_categories (category_id NOT NULL)
CREATE TABLE seats (
    id SERIAL PRIMARY KEY,
    hall_id INT NOT NULL REFERENCES halls(id) ON DELETE CASCADE,
    category_id INT NOT NULL REFERENCES seat_categories(id),
    row_label VARCHAR(5) NOT NULL,
    number INT NOT NULL,
    grid_x INT,
    grid_y INT,
    UNIQUE(hall_id, row_label, number)
);

-- Tabela: actors (Aktorzy)
-- Zależności: Podtyp tabeli persons (person_id)
CREATE TABLE actors (
    person_id INT PRIMARY KEY REFERENCES persons(id) ON DELETE CASCADE,
    bio TEXT,
    base_salary DECIMAL(10,2) DEFAULT 3000.00,
    agency_name VARCHAR(100) DEFAULT 'Freelance'
);

-- Tabela: actor_skills (Umiejętności aktorów)
-- Zależności: Atrybut wielowartościowy dla tabeli actors (actor_id NOT NULL)
CREATE TABLE actor_skills (
    actor_id INT NOT NULL REFERENCES actors(person_id) ON DELETE CASCADE,
    skill_name VARCHAR(50) NOT NULL,
    PRIMARY KEY (actor_id, skill_name)
);

-- Tabela: genres (Gatunki)
-- Zależności: Brak
CREATE TABLE genres (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

-- Tabela: spectacles (Spektakle)
-- Zależności: Udział obowiązkowy w genres (genre_id NOT NULL)
CREATE TABLE spectacles (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    duration_minutes INT NOT NULL,
    poster_url VARCHAR(255) DEFAULT '/images/default-poster.png',
    genre_id INT NOT NULL REFERENCES genres(id),
    premiere_date DATE
);

-- Tabela: spectacle_actors (Obsada)
-- Zależności: Związek z atrybutami, udział obowiązkowy w spectacles (spectacle_id) i actors (actor_id)
CREATE TABLE spectacle_actors (
    spectacle_id INT NOT NULL REFERENCES spectacles(id) ON DELETE CASCADE,
    actor_id INT NOT NULL REFERENCES actors(person_id) ON DELETE CASCADE,
    role_name VARCHAR(100),
    contract_type VARCHAR(50) DEFAULT 'Standard',
    PRIMARY KEY (spectacle_id, actor_id)
);

-- Tabela: seances (Seanse)
-- Zależności: Udział obowiązkowy w spectacles (spectacle_id NOT NULL) i halls (hall_id NOT NULL)
CREATE TABLE seances (
    id SERIAL PRIMARY KEY,
    spectacle_id INT NOT NULL REFERENCES spectacles(id) ON DELETE CASCADE,
    hall_id INT NOT NULL REFERENCES halls(id),
    start_time TIMESTAMP NOT NULL,
    base_price DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'cancelled', 'completed'))
);

-- Tabela: coupons (Kupony Rabatowe)
-- Zależności: Brak
CREATE TABLE coupons (
    id SERIAL PRIMARY KEY,
    code VARCHAR(20) UNIQUE NOT NULL,
    discount_percent DECIMAL(5,2) CHECK (discount_percent BETWEEN 0 AND 100),
    valid_until TIMESTAMP
);

-- Tabela: reservations (Rezerwacje)
-- Zależności: Udział obowiązkowy w users (user_id NOT NULL) i seances (seance_id NOT NULL). Udział opcjonalny w coupons (coupon_id NULL).
CREATE TABLE reservations (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(person_id),
    seance_id INT NOT NULL REFERENCES seances(id),
    reservation_date TIMESTAMP DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'confirmed',
    coupon_id INT REFERENCES coupons(id)
);

-- Tabela: tickets (Bilety)
-- Zależności: Udział obowiązkowy w reservations (reservation_id NOT NULL) i seats (seat_id NOT NULL)
CREATE TABLE tickets (
    id SERIAL PRIMARY KEY,
    reservation_id INT NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
    seat_id INT NOT NULL REFERENCES seats(id),
    final_price DECIMAL(10,2) NOT NULL,
    ticket_token VARCHAR(64) UNIQUE,
    scanned_at TIMESTAMP
);

-- Tabela: reviews (Recenzje)
-- Zależności: Udział obowiązkowy w users (user_id NOT NULL) i spectacles (spectacle_id NOT NULL)
CREATE TABLE reviews (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(person_id) ON DELETE CASCADE,
    spectacle_id INT NOT NULL REFERENCES spectacles(id) ON DELETE CASCADE,
    rating INT CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Tabela: audit_logs (Logi Systemowe)
-- Zależności: Brak
CREATE TABLE audit_logs (
    id SERIAL PRIMARY KEY,
    action_type VARCHAR(50),
    details TEXT,
    log_time TIMESTAMP DEFAULT NOW()
);

-- ==========================================
-- KROK 3: WIDOKI, PROCEDURY I WYZWALACZE
-- ==========================================

-- Widok: v_financial_report
CREATE VIEW v_financial_report AS
SELECT 
    sp.title, 
    g.name AS genre, 
    COUNT(t.id) AS sold_tickets, 
    COALESCE(SUM(t.final_price), 0) AS revenue
FROM spectacles sp
JOIN genres g ON sp.genre_id = g.id
JOIN seances se ON se.spectacle_id = sp.id
LEFT JOIN reservations r ON r.seance_id = se.id
LEFT JOIN tickets t ON t.reservation_id = r.id
GROUP BY sp.title, g.name;

-- Procedura: update_seance_prices
CREATE OR REPLACE PROCEDURE update_seance_prices(percentage DECIMAL)
LANGUAGE plpgsql AS $$
DECLARE
    rec RECORD;
    new_price DECIMAL(10,2);
BEGIN
    FOR rec IN SELECT id, base_price FROM seances WHERE start_time > NOW() LOOP
        BEGIN
            new_price := rec.base_price * (1 + percentage / 100);
            IF new_price > 500 THEN
                RAISE NOTICE 'Cena dla seansu ID % byłaby za wysoka (% PLN). Pomijam.', rec.id, new_price;
            ELSE
                UPDATE seances SET base_price = new_price WHERE id = rec.id;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO audit_logs (action_type, details) 
            VALUES ('ERROR', 'Błąd przy aktualizacji ceny seansu ' || rec.id);
        END;
    END LOOP;
END;
$$;

-- Wyzwalacz i funkcja: trg_loyalty_points
CREATE OR REPLACE FUNCTION add_loyalty_points() RETURNS TRIGGER AS $$
DECLARE
    points_to_add INT;
BEGIN
    points_to_add := 10;
    UPDATE users SET loyalty_points = loyalty_points + points_to_add WHERE person_id = NEW.user_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_loyalty_points
AFTER INSERT ON reservations
FOR EACH ROW EXECUTE FUNCTION add_loyalty_points();

-- Wyzwalacz i funkcja: trg_log_price_updates
CREATE OR REPLACE FUNCTION log_price_change() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.base_price <> NEW.base_price THEN
        INSERT INTO audit_logs (action_type, details)
        VALUES ('PRICE_CHANGE', 'Zmiana ceny seansu ID ' || NEW.id || ' z ' || OLD.base_price || ' na ' || NEW.base_price);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_price_updates
AFTER UPDATE ON seances
FOR EACH ROW EXECUTE FUNCTION log_price_change();

-- Procedura: generate_seats_for_hall
CREATE OR REPLACE PROCEDURE generate_seats_for_hall(p_hall_id INT, p_rows INT, p_seats_per_row INT)
LANGUAGE plpgsql AS $$
DECLARE
    r INT;
    s INT;
BEGIN
    FOR r IN 1..p_rows LOOP
        FOR s IN 1..p_seats_per_row LOOP
            INSERT INTO seats (hall_id, category_id, row_label, number, grid_x, grid_y)
            VALUES (p_hall_id, 1, CHR(64 + r), s, s, r);
        END LOOP;
    END LOOP;
    UPDATE halls SET capacity = (p_rows * p_seats_per_row) WHERE id = p_hall_id;
END;
$$;


DO $$
DECLARE
    i INT;
    last_id INT;
    mgr_id INT;
    person_new_id INT;
BEGIN
    RAISE NOTICE 'Generowanie danych początkowych...';

    -- 1. Działy
    INSERT INTO departments (name, budget) VALUES 
    ('Administracja', 50000), ('Obsługa Techniczna', 30000), ('Marketing', 20000), ('Zespół Artystyczny', 150000);

    -- 2. Pracownicy (Min. 15)
    -- Szef (brak managera)
    INSERT INTO persons (first_name, last_name, email) VALUES ('Jan', 'Dyrektor', 'dyr@teatr.pl') RETURNING id INTO person_new_id;
    INSERT INTO employees (person_id, department_id, manager_id, salary)
    VALUES (person_new_id, 1, NULL, 15000) RETURNING person_id INTO mgr_id;

    -- Podwładni
    FOR i IN 1..20 LOOP
        INSERT INTO persons (first_name, last_name, email) 
        VALUES ('Pracownik', 'Nr-' || i, 'pracownik' || i || '@teatr.pl') RETURNING id INTO person_new_id;
        
        INSERT INTO employees (person_id, department_id, manager_id, salary)
        VALUES (person_new_id, (i % 4) + 1, mgr_id, 3000 + (i * 100));
    END LOOP;

    -- 3. Użytkownicy (Min. 20)
    INSERT INTO persons (first_name, last_name, email) VALUES ('Administrator', 'Systemu', 'admin@teatr.pl') RETURNING id INTO person_new_id;
    INSERT INTO users (person_id, username, password_hash, role) VALUES (person_new_id, 'admin', 'admin123', 'admin');
    
    FOR i IN 1..20 LOOP
        INSERT INTO persons (first_name, last_name, email) 
        VALUES ('Klient', 'Nr-'||i, 'klient'||i||'@teatr.pl') RETURNING id INTO person_new_id;
        
        INSERT INTO users (person_id, username, password_hash, role, loyalty_points) 
        VALUES (person_new_id, 'user'||i, 'pass'||i, 'client', i*5);
    END LOOP;

    -- 4. Sale i Miejsca
    INSERT INTO halls (name) VALUES ('Duża Scena'), ('Scena Kameralna'), ('Sala Prób');
    INSERT INTO seat_categories (name) VALUES ('Standard'), ('VIP'), ('Balkon');
    
    CALL generate_seats_for_hall(1, 10, 15); -- 150 miejsc
    CALL generate_seats_for_hall(2, 5, 10);  -- 50 miejsc

    -- 5. Aktorzy (Min. 20) oraz Atrybut Wielowartościowy
    FOR i IN 1..20 LOOP
        INSERT INTO persons (first_name, last_name, email) 
        VALUES (
            CASE (i%3) WHEN 0 THEN 'Anna' WHEN 1 THEN 'Piotr' ELSE 'Krzysztof' END, 
            'Nazwisko-'||i, 
            'aktor'||i||'@teatr.pl'
        ) RETURNING id INTO person_new_id;
        
        INSERT INTO actors (person_id, bio, base_salary) 
        VALUES (person_new_id, 'Absolwent szkoły teatralnej z numerem dyplomu '||i, 2500 + (i * 150));
        
        -- Spełnienie wymogu: Atrybut wielowartościowy (wiele umiejętności przypisanych do 1 aktora)
        INSERT INTO actor_skills (actor_id, skill_name) VALUES (person_new_id, 'Gra dramatyczna');
        IF i % 2 = 0 THEN
            INSERT INTO actor_skills (actor_id, skill_name) VALUES (person_new_id, 'Śpiew');
        END IF;
        IF i % 3 = 0 THEN
            INSERT INTO actor_skills (actor_id, skill_name) VALUES (person_new_id, 'Taniec współczesny');
        END IF;
    END LOOP;

    -- 6. Gatunki
    INSERT INTO genres (name) VALUES ('Dramat'), ('Komedia'), ('Musical'), ('Thriller'), ('Opera'), ('Balet');

    -- 7. Spektakle (Min. 15)
    FOR i IN 1..15 LOOP
        INSERT INTO spectacles (title, description, duration_minutes, genre_id, premiere_date)
        VALUES (
            'Sztuka numer '||i, 
            'Bardzo ciekawy opis fabuły spektaklu numer '||i, 
            80 + (i*2), 
            (i % 6) + 1,
            NOW() - (i * 30 || ' days')::INTERVAL
        );
    END LOOP;

    -- 8. Obsada (Asocjacja)
    FOR i IN 1..15 LOOP
        -- Każdy spektakl ma przynajmniej 2 aktorów. Pobieramy dynamicznie ID aktora na podstawie przesunięcia (OFFSET)
        INSERT INTO spectacle_actors (spectacle_id, actor_id, role_name) 
        VALUES (i, (SELECT person_id FROM actors ORDER BY person_id LIMIT 1 OFFSET (i % 20)), 'Główna rola');
        
        INSERT INTO spectacle_actors (spectacle_id, actor_id, role_name) 
        VALUES (i, (SELECT person_id FROM actors ORDER BY person_id LIMIT 1 OFFSET ((i+1) % 20)), 'Druga rola');
    END LOOP;

    -- 9. Seanse (Min. 30 - mieszane daty)
    FOR i IN 1..30 LOOP
        INSERT INTO seances (spectacle_id, hall_id, start_time, base_price)
        VALUES (
            (i % 15) + 1,
            1,
            NOW() + (i - 15 || ' days')::INTERVAL,
            40.00 + (i % 5) * 10
        );
    END LOOP;

    -- 10. Kupony
    FOR i IN 1..15 LOOP
        INSERT INTO coupons (code, discount_percent, valid_until) 
        VALUES ('RABAT'||i, 10.0 + i, NOW() + '1 year'::INTERVAL);
    END LOOP;

    -- 11. Rezerwacje i Bilety (Min. 50 biletów)
    FOR i IN 1..25 LOOP
        -- Rezerwacja (Pobieramy ID losowego klienta)
        INSERT INTO reservations (user_id, seance_id) 
        VALUES (
            (SELECT person_id FROM users WHERE role = 'client' ORDER BY person_id LIMIT 1 OFFSET (i%20)), 
            (i%30)+1
        ) RETURNING id INTO last_id;
        
        -- Tworzymy po 2 bilety dla każdej rezerwacji = 50 biletów
        INSERT INTO tickets (reservation_id, seat_id, final_price, ticket_token)
        VALUES (last_id, i, 50.00, md5(random()::text));
        
        INSERT INTO tickets (reservation_id, seat_id, final_price, ticket_token)
        VALUES (last_id, i+25, 50.00, md5(random()::text || 'b'));
    END LOOP;

    -- 12. Recenzje (Min. 15)
    FOR i IN 1..20 LOOP
        INSERT INTO reviews (user_id, spectacle_id, rating, comment)
        VALUES (
            (SELECT person_id FROM users WHERE role = 'client' ORDER BY person_id LIMIT 1 OFFSET (i%20)), 
            (i % 15) + 1, 
            (i % 5) + 1, 
            'Recenzja testowa numer ' || i
        );
    END LOOP;

END $$;