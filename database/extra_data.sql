DO $$
DECLARE
    -- Zmienne pomocnicze
    i INT;
    j INT;
    new_id INT;
    person_new_id INT;
    random_hall INT;
    random_spectacle INT;
    random_user INT;
    random_manager INT;
    seat_rec RECORD;
    counter INT := 0;
BEGIN
    RAISE NOTICE 'Rozpoczynam generowanie dużej ilości danych...';

    -- 1. DODAWANIE UŻYTKOWNIKÓW (1000 sztuk)
    FOR i IN 1..1000 LOOP
        -- Najpierw tworzymy Osobę (Supertyp)
        INSERT INTO persons (first_name, last_name, email)
        VALUES ('Klient', 'Testowy ' || i, 'klient_extra_' || i || '@teatr.pl')
        RETURNING id INTO person_new_id;

        -- Następnie tworzymy Użytkownika (Podtyp)
        INSERT INTO users (person_id, username, password_hash, role, loyalty_points) 
        VALUES (
            person_new_id,
            'klient_extra_' || i, 
            'hash_testowy_123', 
            'client', 
            (random() * 500)::INT
        );
    END LOOP;
    RAISE NOTICE 'Dodano 1000 użytkowników.';

    -- 2. DODAWANIE PRACOWNIKÓW (100 sztuk)
    FOR i IN 1..100 LOOP
        INSERT INTO persons (first_name, last_name, email)
        VALUES ('Pracownik', 'Nadmiarowy-' || i, 'extra.pracownik.' || i || '@teatr.pl')
        RETURNING id INTO person_new_id;

        -- Pobieramy losowego managera (jeśli istnieje), dla pierwszego pracownika będzie NULL
        SELECT person_id INTO random_manager FROM employees ORDER BY random() LIMIT 1;

        INSERT INTO employees (person_id, department_id, manager_id, salary, hire_date)
        VALUES (
            person_new_id,
            (i % 4) + 1, 
            random_manager, 
            3500 + (random() * 4000)::DECIMAL(10,2),
            CURRENT_DATE - (random() * 365 * 5)::INT
        );
    END LOOP;
    RAISE NOTICE 'Dodano 100 pracowników.';

    -- 3. DODAWANIE AKTORÓW (50 sztuk)
    FOR i IN 1..50 LOOP
        INSERT INTO persons (first_name, last_name, email)
        VALUES ('Aktor', 'Wydajnościowy-' || i, 'extra.aktor.' || i || '@teatr.pl')
        RETURNING id INTO person_new_id;

        INSERT INTO actors (person_id, bio, base_salary) 
        VALUES (
            person_new_id,
            'Wygenerowany automatycznie opis aktora nr ' || i, 
            2800 + (random() * 5000)::DECIMAL(10,2)
        );

        -- Dodanie atrybutu wielowartościowego dla kompatybilności
        INSERT INTO actor_skills (actor_id, skill_name) 
        VALUES (person_new_id, 'Gra aktorska');
    END LOOP;
    RAISE NOTICE 'Dodano 50 aktorów.';

    -- 4. DODAWANIE SPEKTAKLI (50 sztuk)
    FOR i IN 1..50 LOOP
        INSERT INTO spectacles (title, description, duration_minutes, genre_id, premiere_date)
        VALUES (
            'Wielki Spektakl Testowy nr ' || i, 
            'Opis mający na celu zajęcie miejsca w bazie danych.', 
            60 + (random() * 120)::INT, 
            (i % 6) + 1, 
            CURRENT_DATE - (random() * 1000)::INT
        ) RETURNING id INTO new_id;

        -- Przypisanie losowych aktorów
        FOR j IN 1..(3 + (random()*3)::INT) LOOP
            BEGIN
                INSERT INTO spectacle_actors (spectacle_id, actor_id, role_name)
                VALUES (
                    new_id, 
                    (SELECT person_id FROM actors ORDER BY random() LIMIT 1), -- Zmiana na poprawne ID
                    'Rola generowana ' || j
                );
            EXCEPTION WHEN unique_violation THEN
                -- Ignorujemy duplikaty
            END;
        END LOOP;
    END LOOP;
    RAISE NOTICE 'Dodano 50 spektakli wraz z obsadą.';

    -- 5. DODAWANIE SEANSÓW (500 sztuk)
    FOR i IN 1..500 LOOP
        random_hall := (random() * 2 + 1)::INT; 
        SELECT id INTO random_spectacle FROM spectacles ORDER BY random() LIMIT 1; 
        
        INSERT INTO seances (spectacle_id, hall_id, start_time, base_price, status)
        VALUES (
            random_spectacle,
            random_hall,
            NOW() + ((random() * 200 - 100) || ' days')::INTERVAL + ((random() * 10) || ' hours')::INTERVAL,
            40 + (random() * 100)::DECIMAL(10,2),
            CASE WHEN random() > 0.9 THEN 'cancelled' ELSE 'scheduled' END
        ) RETURNING id INTO new_id;

        -- 6. REZERWACJE I BILETY (co 3 seans)
        IF i % 3 = 0 THEN
            SELECT person_id INTO random_user FROM users ORDER BY random() LIMIT 1;
            
            INSERT INTO reservations (user_id, seance_id, status) 
            VALUES (random_user, new_id, 'confirmed') 
            RETURNING id INTO j;

            FOR seat_rec IN 
                SELECT id FROM seats WHERE hall_id = random_hall ORDER BY id LIMIT (10 + (random() * 20)::INT)
            LOOP
                INSERT INTO tickets (reservation_id, seat_id, final_price, ticket_token)
                VALUES (
                    j, 
                    seat_rec.id, 
                    (SELECT base_price FROM seances WHERE id = new_id), 
                    md5(random()::text || clock_timestamp()::text)
                );
                counter := counter + 1;
            END LOOP;
        END IF;

    END LOOP;
    RAISE NOTICE 'Dodano 500 seansów oraz ok. % biletów.', counter;
    RAISE NOTICE 'Zakończono sukcesem.';

END $$;