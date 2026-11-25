-- ==========================================
-- ICT371 QUESTION 10: Scholarship Application
-- ==========================================

-- Clean up existing tables
DROP TABLE IF EXISTS decision_audit, applications, students CASCADE;

-- ---------------------------------------------------------
-- (a) Database and seed data [6 marks]
-- ---------------------------------------------------------
CREATE TABLE students (
  student_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  student_number VARCHAR(20) UNIQUE NOT NULL,
  full_name      VARCHAR(100) NOT NULL
);

CREATE TABLE applications (
  application_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  student_id         INT NOT NULL REFERENCES students(student_id),
  age_at_application INT NOT NULL CHECK (age_at_application > 0),
  monthly_income     NUMERIC(12,2) NOT NULL CHECK (monthly_income >= 0),
  average_mark       NUMERIC(5,2) NOT NULL CHECK (average_mark BETWEEN 0 AND 100),
  submitted_on       DATE NOT NULL,
  status             VARCHAR(10) NOT NULL DEFAULT 'PENDING' 
                     CHECK (status IN ('PENDING','APPROVED','REJECTED'))
);

CREATE TABLE decision_audit (
  audit_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  application_id INT NOT NULL REFERENCES applications(application_id),
  old_status     VARCHAR(10) NOT NULL,
  new_status     VARCHAR(10) NOT NULL,
  changed_at     TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------
-- (b) Function [6 marks]
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INT, p_income NUMERIC, p_mark NUMERIC)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL THEN
    RAISE EXCEPTION 'NULL inputs not allowed'; 
  END IF;
  
  IF p_income < 0 OR p_age <= 0 OR p_mark < 0 OR p_mark > 100 THEN
    RAISE EXCEPTION 'Input out of range'; 
  END IF;
  
  -- Rules: Age 18-25 inclusive, Income <= 3000, Mark >= 70
  RETURN (p_age BETWEEN 18 AND 25) AND (p_income <= 3000) AND (p_mark >= 70);
END $$;

-- ---------------------------------------------------------
-- (c) Procedure [8 marks]
-- ---------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id INT) LANGUAGE plpgsql AS $$
DECLARE v_age INT; v_income NUMERIC; v_mark NUMERIC; v_status VARCHAR;
BEGIN
  SELECT age_at_application, monthly_income, average_mark, status
    INTO v_age, v_income, v_mark, v_status
  FROM applications WHERE application_id = p_application_id;
  
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown application %', p_application_id; END IF;
  IF v_status <> 'PENDING' THEN RAISE EXCEPTION 'Application already assessed'; END IF;
  
  UPDATE applications
     SET status = CASE WHEN fn_scholarship_eligible(v_age, v_income, v_mark)
                       THEN 'APPROVED' ELSE 'REJECTED' END
   WHERE application_id = p_application_id;
END $$;

-- ---------------------------------------------------------
-- (d) Trigger [8 marks]
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_decision_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO decision_audit(application_id, old_status, new_status)
  VALUES (NEW.application_id, OLD.status, NEW.status);
  RETURN NEW;
END $$;

CREATE TRIGGER trg_app_status_audit 
AFTER UPDATE ON applications
FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION trg_decision_audit();

-- ---------------------------------------------------------
-- (e) View [5 marks]
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW v_approved_applicants AS
SELECT s.student_number, s.full_name, a.average_mark, a.status
FROM applications a 
JOIN students s USING (student_id)
WHERE a.status = 'APPROVED';

-- ---------------------------------------------------------
-- (f) Index [5 marks]
-- ---------------------------------------------------------
CREATE INDEX idx_apps_status_submitted ON applications(status, submitted_on);
-- EXPLAIN SELECT * FROM applications WHERE status='PENDING' AND submitted_on BETWEEN '2025-01-01' AND '2025-01-31';

-- ---------------------------------------------------------
-- (g) Scheduled job [6 marks]
-- ---------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_assess_pending() LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
  -- Loop only processes PENDING applications
  FOR r IN SELECT application_id FROM applications WHERE status = 'PENDING' ORDER BY application_id LOOP
    CALL pr_assess_application(r.application_id);
  END LOOP;
END $$;

-- SELECT cron.schedule('scholarship-mon','0 8 * * 1',$$CALL pr_assess_pending()$$);

-- ==========================================
-- SEED DATA & TESTING
-- ==========================================

-- 1. Insert students
INSERT INTO students(student_number, full_name) VALUES ('ST01','Ann'),('ST02','Ben'),('ST03','Cai');

-- 2. Insert 6 PENDING applications (qualifying, non-qualifying, boundaries)
INSERT INTO applications(student_id, age_at_application, monthly_income, average_mark, submitted_on) VALUES
 (1, 18, 3000, 70,   CURRENT_DATE),    -- Boundary (Qualifies)
 (1, 25, 1000, 95,   CURRENT_DATE),    -- Qualifies
 (2, 17, 2000, 80,   CURRENT_DATE),    -- Age fail
 (2, 20, 3500, 80,   CURRENT_DATE),    -- Income fail
 (3, 22, 2900, 69.99,CURRENT_DATE),    -- Mark fail
 (3, 24, 3000, 70,   CURRENT_DATE);    -- Qualifies

-- 3. Run the scheduled job procedure
CALL pr_assess_pending();

-- 4. Check the results
SELECT * FROM applications;
SELECT * FROM decision_audit;
SELECT * FROM v_approved_applicants;