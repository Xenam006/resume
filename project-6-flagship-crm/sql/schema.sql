-- ============================================================
--  Кейс 6. CRM для сети фитнес-клубов
--  Модель данных (PostgreSQL DDL)
-- ============================================================
--  Отражает требования из docs/requirements.md:
--  клиенты, абонементы, расписание, записи, посещения, оплаты.
-- ============================================================

DROP TABLE IF EXISTS payments, visits, bookings, class_sessions,
                     memberships, membership_types, clients, trainers, clubs CASCADE;

-- --- Клубы сети ---
CREATE TABLE clubs (
    club_id   SERIAL PRIMARY KEY,
    name      TEXT NOT NULL,
    city      TEXT NOT NULL,
    address   TEXT
);

-- --- Тренеры ---
CREATE TABLE trainers (
    trainer_id  SERIAL PRIMARY KEY,
    full_name   TEXT NOT NULL,
    club_id     INT REFERENCES clubs(club_id)
);

-- --- Клиенты (с домашним клубом, но ходят в любой) ---
CREATE TABLE clients (
    client_id     SERIAL PRIMARY KEY,
    home_club_id  INT NOT NULL REFERENCES clubs(club_id),
    full_name     TEXT NOT NULL,
    phone         TEXT NOT NULL UNIQUE,
    email         TEXT,
    created_at    TIMESTAMP NOT NULL DEFAULT now(),
    consent_pdn   BOOLEAN NOT NULL DEFAULT false   -- согласие на обработку ПДн (152-ФЗ)
);

-- --- Тарифы (шаблоны абонементов) ---
CREATE TABLE membership_types (
    type_id        SERIAL PRIMARY KEY,
    name           TEXT NOT NULL,
    duration_days  INT  NOT NULL CHECK (duration_days > 0),
    visit_limit    INT,                              -- NULL = безлимит
    price          NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    freeze_allowed BOOLEAN NOT NULL DEFAULT true
);

-- --- Абонементы (проданные экземпляры тарифа) ---
CREATE TABLE memberships (
    membership_id    SERIAL PRIMARY KEY,
    client_id        INT  NOT NULL REFERENCES clients(client_id),
    type_id          INT  NOT NULL REFERENCES membership_types(type_id),
    start_date       DATE NOT NULL,
    end_date         DATE NOT NULL,
    visits_remaining INT,                            -- NULL для безлимитных
    status           TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','expired','frozen')),
    CHECK (end_date >= start_date)
);

-- --- Групповые занятия (сессии расписания) ---
CREATE TABLE class_sessions (
    session_id   SERIAL PRIMARY KEY,
    club_id      INT  NOT NULL REFERENCES clubs(club_id),
    trainer_id   INT  REFERENCES trainers(trainer_id),
    title        TEXT NOT NULL,                      -- напр. "Йога", "Сайкл"
    starts_at    TIMESTAMP NOT NULL,
    duration_min INT  NOT NULL DEFAULT 60,
    capacity     INT  NOT NULL CHECK (capacity > 0)
);

-- --- Записи (брони) на занятия ---
CREATE TABLE bookings (
    booking_id  SERIAL PRIMARY KEY,
    client_id   INT NOT NULL REFERENCES clients(client_id),
    session_id  INT NOT NULL REFERENCES class_sessions(session_id),
    created_at  TIMESTAMP NOT NULL DEFAULT now(),
    status      TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','cancelled','attended','no_show')),
    -- один клиент не может записаться на одно занятие дважды (NFR-6)
    UNIQUE (client_id, session_id)
);

-- --- Посещения (факт прихода, check-in) ---
CREATE TABLE visits (
    visit_id      SERIAL PRIMARY KEY,
    client_id     INT NOT NULL REFERENCES clients(client_id),
    session_id    INT REFERENCES class_sessions(session_id),
    membership_id INT NOT NULL REFERENCES memberships(membership_id),
    checked_in_at TIMESTAMP NOT NULL DEFAULT now(),
    -- одно посещение на клиента в рамках занятия (нет двойного списания)
    UNIQUE (client_id, session_id)
);

-- --- Оплаты (продажа/продление абонемента) ---
CREATE TABLE payments (
    payment_id    SERIAL PRIMARY KEY,
    membership_id INT NOT NULL REFERENCES memberships(membership_id),
    amount        NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    method        TEXT NOT NULL DEFAULT 'card'
        CHECK (method IN ('card','cash','online')),
    paid_at       TIMESTAMP NOT NULL DEFAULT now()
);

-- --- Индексы под типовые запросы ---
CREATE INDEX idx_memberships_client   ON memberships(client_id);
CREATE INDEX idx_memberships_end_date ON memberships(end_date);
CREATE INDEX idx_sessions_starts_at   ON class_sessions(starts_at);
CREATE INDEX idx_bookings_session     ON bookings(session_id);
CREATE INDEX idx_visits_client        ON visits(client_id);

-- ============================================================
--  Вспомогательные представления под отчёты (FR-14, FR-15)
-- ============================================================

-- Абонементы, истекающие в ближайшие 7 дней (для продлений)
CREATE OR REPLACE VIEW v_expiring_memberships AS
SELECT m.membership_id, c.client_id, c.full_name, c.phone,
       m.end_date, mt.name AS tariff
FROM memberships m
JOIN clients c          ON c.client_id = m.client_id
JOIN membership_types mt ON mt.type_id = m.type_id
WHERE m.status = 'active'
  AND m.end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days';

-- Загрузка занятий: занято мест vs вместимость
CREATE OR REPLACE VIEW v_session_load AS
SELECT s.session_id, s.club_id, s.title, s.starts_at, s.capacity,
       COUNT(b.booking_id) FILTER (WHERE b.status = 'active') AS booked,
       s.capacity - COUNT(b.booking_id) FILTER (WHERE b.status = 'active') AS free_slots
FROM class_sessions s
LEFT JOIN bookings b ON b.session_id = s.session_id
GROUP BY s.session_id;
