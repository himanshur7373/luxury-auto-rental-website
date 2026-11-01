-- Luxury Auto Rental: PL/SQL database layer (Oracle 12c or later)
-- Author: Himanshu Rathee (26MCA20258)
-- Run the whole script in SQL Developer / SQL*Plus / Oracle APEX SQL Workshop.
-- Daily rates are sample values for demonstration only.

-- 1. Tables
CREATE TABLE cars (
  car_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  car_name      VARCHAR2(60) NOT NULL,
  category      VARCHAR2(10) NOT NULL CHECK (category IN ('sedan','suv','auto')),
  label         VARCHAR2(60),
  seats         NUMBER(2)    NOT NULL,
  fuel          VARCHAR2(10) NOT NULL,
  transmission  VARCHAR2(10) NOT NULL,
  daily_rate    NUMBER(8,2)  NOT NULL CHECK (daily_rate > 0),
  status        VARCHAR2(10) DEFAULT 'available' NOT NULL
                CHECK (status IN ('available','booked'))
);

CREATE TABLE customers (
  customer_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  full_name     VARCHAR2(80) NOT NULL,
  phone         VARCHAR2(15) NOT NULL UNIQUE,
  licence_no    VARCHAR2(30) NOT NULL
);

CREATE TABLE bookings (
  booking_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  car_id        NUMBER NOT NULL REFERENCES cars(car_id),
  customer_id   NUMBER NOT NULL REFERENCES customers(customer_id),
  pickup_date   DATE NOT NULL,
  duration      VARCHAR2(10) NOT NULL
                CHECK (duration IN ('1 Day','Weekend','Weekly','Monthly')),
  notes         VARCHAR2(200),
  status        VARCHAR2(10) DEFAULT 'new' NOT NULL
                CHECK (status IN ('new','confirmed','completed','cancelled')),
  total_amount  NUMBER(10,2),
  created_at    TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE booking_audit (
  audit_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id    NUMBER NOT NULL,
  old_status    VARCHAR2(10),
  new_status    VARCHAR2(10),
  changed_at    TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- 2. Sample data
INSERT INTO cars (car_name, category, label, seats, fuel, transmission, daily_rate)
  VALUES ('Mercedes A-Class', 'sedan', 'Signature Sedan', 5, 'Petrol', 'Automatic', 9000);
INSERT INTO cars (car_name, category, label, seats, fuel, transmission, daily_rate)
  VALUES ('Audi A4', 'sedan', 'Executive Sedan', 5, 'Petrol', 'Manual', 8000);
INSERT INTO cars (car_name, category, label, seats, fuel, transmission, daily_rate)
  VALUES ('VW Virtus GT', 'sedan', '1.5 TSI Modified', 5, 'Petrol', 'Manual', 3500);
INSERT INTO cars (car_name, category, label, seats, fuel, transmission, daily_rate)
  VALUES ('Mahindra Thar', 'suv', 'Off-Road Icon', 4, 'Diesel', 'Manual', 4500);
INSERT INTO cars (car_name, category, label, seats, fuel, transmission, daily_rate)
  VALUES ('Toyota Fortuner', 'suv', 'Off-Road SUV', 7, 'Diesel', 'Automatic', 7000);
INSERT INTO cars (car_name, category, label, seats, fuel, transmission, daily_rate)
  VALUES ('Kia Seltos', 'auto', 'Diesel Queen', 5, 'Diesel', 'Automatic', 4000);
COMMIT;

-- 3. Package specification
CREATE OR REPLACE PACKAGE pkg_rental AS
  e_car_unavailable EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_car_unavailable, -20002);

  FUNCTION fn_duration_days(p_duration IN VARCHAR2) RETURN NUMBER;
  FUNCTION fn_calc_amount(p_car_id IN NUMBER, p_duration IN VARCHAR2)
    RETURN NUMBER;

  PROCEDURE sp_book_car(
    p_car_id     IN  NUMBER,
    p_name       IN  VARCHAR2,
    p_phone      IN  VARCHAR2,
    p_licence    IN  VARCHAR2,
    p_pickup     IN  DATE,
    p_duration   IN  VARCHAR2,
    p_notes      IN  VARCHAR2,
    p_booking_id OUT NUMBER);

  PROCEDURE sp_update_status(p_booking_id IN NUMBER, p_new_status IN VARCHAR2);
END pkg_rental;
/

-- 4. Package body
CREATE OR REPLACE PACKAGE BODY pkg_rental AS

  FUNCTION fn_duration_days(p_duration IN VARCHAR2) RETURN NUMBER IS
    v_days NUMBER;
  BEGIN
    IF p_duration = '1 Day' THEN v_days := 1;
    ELSIF p_duration = 'Weekend' THEN v_days := 2;
    ELSIF p_duration = 'Weekly' THEN v_days := 7;
    ELSIF p_duration = 'Monthly' THEN v_days := 30;
    ELSE
      RAISE_APPLICATION_ERROR(-20004, 'Invalid duration: ' || p_duration);
    END IF;
    RETURN v_days;
  END fn_duration_days;

  FUNCTION fn_calc_amount(p_car_id IN NUMBER, p_duration IN VARCHAR2)
    RETURN NUMBER IS
    v_rate     cars.daily_rate%TYPE;
    v_days     NUMBER;
    v_discount NUMBER := 0;
  BEGIN
    SELECT daily_rate INTO v_rate FROM cars WHERE car_id = p_car_id;
    v_days := fn_duration_days(p_duration);
    IF v_days >= 30 THEN
      v_discount := 0.20;
    ELSIF v_days >= 7 THEN
      v_discount := 0.10;
    END IF;
    RETURN ROUND(v_rate * v_days * (1 - v_discount), 2);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Car not found: ' || p_car_id);
  END fn_calc_amount;

  PROCEDURE sp_book_car(
    p_car_id     IN  NUMBER,
    p_name       IN  VARCHAR2,
    p_phone      IN  VARCHAR2,
    p_licence    IN  VARCHAR2,
    p_pickup     IN  DATE,
    p_duration   IN  VARCHAR2,
    p_notes      IN  VARCHAR2,
    p_booking_id OUT NUMBER) IS
    v_status      cars.status%TYPE;
    v_customer_id customers.customer_id%TYPE;
    v_amount      NUMBER;
  BEGIN
    -- lock the car row so two requests cannot race for the same car
    SELECT status INTO v_status FROM cars WHERE car_id = p_car_id FOR UPDATE;
    IF v_status <> 'available' THEN
      RAISE_APPLICATION_ERROR(-20002, 'Car is currently booked');
    END IF;

    v_amount := fn_calc_amount(p_car_id, p_duration);

    BEGIN
      SELECT customer_id INTO v_customer_id
        FROM customers WHERE phone = p_phone;
      UPDATE customers
         SET full_name = p_name, licence_no = p_licence
       WHERE customer_id = v_customer_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        INSERT INTO customers (full_name, phone, licence_no)
        VALUES (p_name, p_phone, p_licence)
        RETURNING customer_id INTO v_customer_id;
    END;

    INSERT INTO bookings
      (car_id, customer_id, pickup_date, duration, notes, total_amount)
    VALUES
      (p_car_id, v_customer_id, p_pickup, p_duration, p_notes, v_amount)
    RETURNING booking_id INTO p_booking_id;

    COMMIT;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20001, 'Car not found: ' || p_car_id);
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END sp_book_car;

  PROCEDURE sp_update_status(p_booking_id IN NUMBER, p_new_status IN VARCHAR2) IS
  BEGIN
    UPDATE bookings SET status = p_new_status WHERE booking_id = p_booking_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20005, 'Booking not found: ' || p_booking_id);
    END IF;
    COMMIT;
  END sp_update_status;

END pkg_rental;
/

-- 5. Triggers
CREATE OR REPLACE TRIGGER trg_booking_validate
BEFORE INSERT ON bookings
FOR EACH ROW
BEGIN
  IF :NEW.pickup_date < TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20003, 'Pickup date cannot be in the past');
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_booking_status
AFTER UPDATE OF status ON bookings
FOR EACH ROW
BEGIN
  INSERT INTO booking_audit (booking_id, old_status, new_status)
  VALUES (:OLD.booking_id, :OLD.status, :NEW.status);

  IF :NEW.status = 'confirmed' THEN
    UPDATE cars SET status = 'booked' WHERE car_id = :NEW.car_id;
  ELSIF :NEW.status IN ('completed', 'cancelled') THEN
    UPDATE cars SET status = 'available' WHERE car_id = :NEW.car_id;
  END IF;
END;
/

-- 6. Report procedures (cursors)
CREATE OR REPLACE PROCEDURE sp_dashboard_stats IS
  v_fleet     NUMBER;
  v_available NUMBER;
  v_new       NUMBER;
  v_total     NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_fleet FROM cars;
  SELECT COUNT(*) INTO v_available FROM cars WHERE status = 'available';
  SELECT COUNT(*) INTO v_new FROM bookings WHERE status = 'new';
  SELECT COUNT(*) INTO v_total FROM bookings;

  DBMS_OUTPUT.PUT_LINE('Total fleet     : ' || v_fleet);
  DBMS_OUTPUT.PUT_LINE('Available now   : ' || v_available);
  DBMS_OUTPUT.PUT_LINE('New requests    : ' || v_new);
  DBMS_OUTPUT.PUT_LINE('Total bookings  : ' || v_total);
END sp_dashboard_stats;
/

CREATE OR REPLACE PROCEDURE sp_booking_report(p_status IN VARCHAR2 DEFAULT NULL) IS
  CURSOR c_bookings(cp_status VARCHAR2) IS
    SELECT b.booking_id, cu.full_name, c.car_name, b.pickup_date,
           b.duration, b.status, b.total_amount
      FROM bookings b
      JOIN customers cu ON cu.customer_id = b.customer_id
      JOIN cars c       ON c.car_id = b.car_id
     WHERE cp_status IS NULL OR b.status = cp_status
     ORDER BY b.created_at DESC;
  v_count NUMBER := 0;
BEGIN
  FOR r IN c_bookings(p_status) LOOP
    v_count := v_count + 1;
    DBMS_OUTPUT.PUT_LINE(
      RPAD(r.booking_id, 5) || RPAD(r.full_name, 18) || RPAD(r.car_name, 20) ||
      RPAD(TO_CHAR(r.pickup_date, 'DD-MON-YYYY'), 14) || RPAD(r.duration, 9) ||
      RPAD(r.status, 11) || 'Rs ' || r.total_amount);
  END LOOP;
  IF v_count = 0 THEN
    DBMS_OUTPUT.PUT_LINE('No bookings found.');
  END IF;
END sp_booking_report;
/

-- 7. Test run
SET SERVEROUTPUT ON;

DECLARE
  v_id NUMBER;
BEGIN
  pkg_rental.sp_book_car(1, 'Himanshu Rathee', '9050737373', 'HR13 200654',
                         TRUNC(SYSDATE) + 3, 'Weekend', 'Pickup from Gurugram', v_id);
  DBMS_OUTPUT.PUT_LINE('Booking created, id = ' || v_id);
  pkg_rental.sp_update_status(v_id, 'confirmed');
END;
/

EXEC sp_dashboard_stats;
EXEC sp_booking_report;
SELECT * FROM booking_audit;

-- error handling demo: car 1 is now booked, so this must fail
DECLARE
  v_id NUMBER;
BEGIN
  pkg_rental.sp_book_car(1, 'Test User', '9999999999', 'DL01 123456',
                         TRUNC(SYSDATE) + 5, '1 Day', NULL, v_id);
EXCEPTION
  WHEN pkg_rental.e_car_unavailable THEN
    DBMS_OUTPUT.PUT_LINE('Rejected: car is currently booked');
END;
/
