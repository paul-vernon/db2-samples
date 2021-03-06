-------------------------------------------------------------------------------
-- (c) Copyright IBM Corp. 2008 All rights reserved.
--
-- The following sample of source code ("Sample") is owned by International
-- Business Machines Corporation or one of its subsidiaries ("IBM") and is
-- copyrighted and licensed, not sold. You may use, copy, modify, and
-- distribute the Sample in any form without payment to IBM, for the purpose of
-- assisting you in the development of your applications.
--
-- The Sample code is provided to you on an "AS IS" basis, without warranty of
-- any kind. IBM HEREBY EXPRESSLY DISCLAIMS ALL WARRANTIES, EITHER EXPRESS OR
-- IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. Some jurisdictions do
-- not allow for the exclusion or limitation of implied warranties, so the above
-- limitations or exclusions may not apply to you. IBM shall not be liable for
-- any damages you suffer as a result of using, copying, modifying or
-- distributing the Sample, even if IBM has been advised of the possibility of
-- such damages.
-------------------------------------------------------------------------------
--
-- SOURCE FILE NAME: CreateCGTT.db2
--
-- SAMPLE: 
--      The sample demonstrates the following:
--       i) Use of Created Temporary table (CGTT) to store intermediate   
--          results. 
--      ii) Use of Created Temporary table with Procedures, Functions, Triggers and Views. 
--
-- PREREQUISITE:
--       1)Sample database is setup on the machine.
--
-- Note: Use following command to execute the sample:
--         db2 -td@ -vf CreateCGTT.db2
--         
-- SQL STATEMENTS USED:
--       1) CREATE GLOBAL TEMPORARY TABLE		
--       2) CREATE INDEX
--       3) CREATE VIEW
--       4) CREATE TRIGGER
--       5) CREATE PROCEDURE
--       6) CREATE FUNCTION
--       7) CALL
--       8) RUNSTATS
--
-------------------------------------------------------------------------------
        
-- Connect to the sample database

CONNECT TO sample@

-- GRANT privileges on 'employee' table to Bob and Joe
GRANT SELECT, INSERT, UPDATE ON TABLE employee TO USER joe@
GRANT SELECT, INSERT, UPDATE ON TABLE employee TO USER bob@

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--       Step1: Create table 'payroll' and populate it.                      --
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-- Create tablespaces 'TbspacePayroll' & 'TbspaceCgtt'. 
-- Table 'Payroll' will be placed in tablespace 'TbspacePayroll' and 
-- 'cgtt.tax_cal' will be placed in tablespace 'TbspaceCgtt'

CREATE BUFFERPOOL BufForSample IMMEDIATE PAGESIZE 4k@
CREATE USER TEMPORARY TABLESPACE TbspaceCgtt PAGESIZE 4k
   BUFFERPOOL BufForSample@
CREATE REGULAR TABLESPACE TbspacePayroll PAGESIZE 4k
   BUFFERPOOL BufForSample@


   
-- Create 'payroll' table to store details about employees income and tax.

CREATE TABLE cgtt.payroll (empid          CHARACTER(6) REFERENCES employee(empno),
                      salaryPA       DECFLOAT,
		          tax_payable    DECFLOAT,
		          tax_exempted   DECFLOAT,
		          tax_proof      DECFLOAT,
		          tax_to_be_paid DECFLOAT,
		          deptno         CHARACTER(3),
		          calculate_tax  INT) IN TbspacePayroll@

-- Insert employee details into 'payroll' table from the employee table of 
-- the sample database  

INSERT INTO cgtt.payroll(empid, deptno, salaryPA)
(SELECT empno,workdept, (salary * 12) AS salary FROM employee)@

-- Initially, the tax exemption for all the employees is 100,000. Update the 
-- 'payroll' table to set the tax_exempted column.

UPDATE cgtt.payroll SET tax_exempted = 100000@

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--      Step 2: Create the following objects                                  --
--              - Created temporary table 'tax_cal'.					--
--              - View 'ViewOnCgtt' based on 'tax_cal'.                       --
--              - Index 'IndexOnCgtt' based on 'tax_cal'                      --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Create Temporary table (CGTT) to store the intermediate results            --
-- while calculating the tax_payable by an employee based on the tax proof.   --
-- For ease of demonstration, set tax proof submitted by all the employees to --
-- 50,000.                                                                    --  
-- Create CGTT 'cgtt.tax_cal' as join of 'employee'  and 'payroll' table.     --
--------------------------------------------------------------------------------

CREATE GLOBAL TEMPORARY TABLE cgtt.tax_cal AS 
  (SELECT e.empno, e.firstnme, e.lastname, e.birthdate, e.bonus, e.comm, 
          p.salarypa, 
          p.tax_payable, p.tax_exempted,  p.tax_proof, p.tax_to_be_paid,p.deptno 
     FROM employee AS e, cgtt.payroll AS p 
   WHERE e.empno = p.empid) 
   DEFINITION ONLY ON COMMIT PRESERVE ROWS 
   IN TbspaceCgtt@

-- Create INDEX 'IndexOnCgtt' based on 'tax_cal'.
CREATE INDEX cgtt.indexOnId ON cgtt.tax_cal(empno) ALLOW REVERSE SCANS@

-- Create View 'ViewOnCgtt' based on 'tax_cal', to print the IT sheet
CREATE VIEW cgtt.ViewOnCgtt AS
  SELECT empno, firstnme, lastname, birthdate, deptno,bonus, comm, salarypa, 
         tax_to_be_paid
     FROM cgtt.tax_cal@


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--       Step3: Create three procedures and a function                       --
--                1) tax_compute        : Calculates the tax payable by an   --
--                                        employee and returns the value to  -- 
--                                        the CALLER.                        --
--                2) initial_tax_compute: Calculates the tax payable by an   --
--                                        employee initially with a tax      -- 
--                                        exemption of 100,000. This         -- 
--                                        procedure calls the function       -- 
--                                        'tax_compute' to do the calculation.-
--                3) final_tax_compute  : Calculates the tax payable by an   -- 
--                                        employee based on his or her total --
--                                        income (salary + any bonus) and the-- 
--                                        tax proof she or she submits. This --
--                                        procedure calls the function       --
--                                        'tax_compute' to do the calculation.- 
--                4) update             : Updates the created temporary table-- 
--                                        'tax_cal' with the final results,  --
--                                        To update the 'payroll' table to   --
--                                        reflect the created temporary table.-
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-- Create function 'tax_compute' to calculate the tax_payable by an employee.
-- Tax is calculated as follows :
--          100,000   - No tax
--     upto 500,000   - 10 percent tax
--     upto 1,000,000 - 20 percent tax
--    Above 1,000,000 - 30 percent tax
--    Any extra bonus - 30 percent tax on bonus
-- For exemption of tax of 100,000 employee has to submit tax proofs. If not,
-- employee will be exempted only for the amount, for which he submits proofs.

CREATE FUNCTION cgtt.tax_compute(salarypa DECFLOAT,
                            exempted DECFLOAT,awarded_pay DECFLOAT)
SPECIFIC common_calculator
RETURNS DECFLOAT
NO EXTERNAL ACTION
DETERMINISTIC
BEGIN 
  DECLARE payable_tax DECFLOAT;
  SET payable_tax = salarypa - exempted;

  IF payable_tax <= 500000 THEN
    SET payable_tax = payable_tax * 0.10;
  ELSEIF payable_tax > 500000 AND payable_tax <= 1000000 THEN
    SET payable_tax = payable_tax * 0.20;
  ELSEIF payable_tax > 1000000 THEN
    SET payable_tax = payable_tax * 0.30;
  END IF;

  SET payable_tax = payable_tax + (awarded_pay * 0.30);
  RETURN payable_tax;
END@


-- Create procedure 'tax_pay' to calculate the tax payable by the employees.
-- For a finnancial year a tax exemption of 
-- 100,000 is given to all the employees. 
-- This procedure calls the function 'tax_compute' to calculate 
-- tax.

CREATE  PROCEDURE cgtt.initial_tax_compute()
SPECIFIC initialTax
LANGUAGE SQL
BEGIN
  DECLARE id CHARACTER(6);
  DECLARE at_end SMALLINT DEFAULT 0;
  DECLARE salary DECFLOAT;
  DECLARE payable_tax DECFLOAT;
  DECLARE not_found CONDITION for SQLSTATE '02000';

  DECLARE IterateOverEmpRecord CURSOR WITH HOLD FOR SELECT empid,salaryPA FROM cgtt.payroll;
  DECLARE CONTINUE HANDLER for not_found SET at_end = 1;

  OPEN IterateOverEmpRecord;

  ins_loop: LOOP
    FETCH IterateOverEmpRecord INTO id,salary;

    IF at_end = 1 THEN
      LEAVE ins_loop;
    ELSE

      UPDATE cgtt.payroll SET tax_payable = cgtt.tax_compute(salary,100000,0) WHERE empid = id;
      COMMIT;
      ITERATE ins_loop;
    END IF;
  END LOOP;

  CLOSE IterateOverEmpRecord;
END@

-- Create procedure 'update' to update the CGTT 'cgtt.tax_cal' with the tax 
-- payable by an employee, calculated by the procedure 'final_tax_compute'.

CREATE PROCEDURE cgtt.update()
SPECIFIC updater
LANGUAGE SQL
BEGIN
  DECLARE at_end SMALLINT DEFAULT 0;
  DECLARE id CHARACTER(6);
  DECLARE tax_left DECFLOAT;
  DECLARE tax_p DECFLOAT;
  DECLARE not_found CONDITION FOR SQLSTATE '02000';

  DECLARE UpdateCGTT CURSOR WITH HOLD FOR
              SELECT empno,tax_to_be_paid,tax_payable 
                 FROM cgtt.tax_cal;
  DECLARE UpdatePayroll CURSOR WITH HOLD FOR
              SELECT empno,tax_to_be_paid,tax_payable
                 FROM cgtt.tax_cal;
  DECLARE CONTINUE HANDLER for not_found SET at_end = 1;

  OPEN UpdateCGTT;

  up_loop: LOOP
    FETCH UpdateCGTT INTO id,tax_left,tax_p;

    IF at_end = 1 THEN
      LEAVE up_loop;
    ELSE
      UPDATE cgtt.tax_cal SET tax_payable = tax_left,
                              tax_to_be_paid = tax_left - tax_p 
                          WHERE empno = id;
      ITERATE up_loop;
    END IF;
  END LOOP;

  CLOSE UpdateCGTT;

  SET at_end = 0;
  OPEN UpdatePayroll;

  update_payroll: LOOP
    FETCH UpdatePayroll INTO id,tax_left,tax_p;

    IF at_end = 1 THEN
      LEAVE update_payroll;
    ELSE
      UPDATE cgtt.payroll SET tax_payable = tax_p,
                         tax_to_be_paid = tax_left
                     WHERE empid = id;
    ITERATE update_payroll;
    END IF;
  END LOOP;

  CLOSE UpdatePayroll;


END@

-- Create procedure 'final_tax_compute' to select employee records from the  
-- created temporary table 'cgtt.tax_cal' and call the function 'tax_compute'
-- to calculate the tax.

CREATE  PROCEDURE cgtt.final_tax_compute()
SPECIFIC finalTax
LANGUAGE SQL
BEGIN
  DECLARE id CHARACTER(6);
  DECLARE at_end SMALLINT DEFAULT 0;
  DECLARE salary DECFLOAT;
  DECLARE exempted DECFLOAT;
  DECLARE proof DECFLOAT;
  DECLARE awarded_pay DECFLOAT;
  DECLARE bonus DECFLOAT;
  DECLARE comm DECFLOAT;
  DECLARE not_found CONDITION for SQLSTATE '02000';

  DECLARE IterateOverEmpRecord CURSOR WITH HOLD FOR 
          SELECT empno,bonus,comm,salaryPA,tax_exempted,tax_proof FROM cgtt.tax_cal;
  DECLARE CONTINUE HANDLER for not_found SET at_end = 1;

  OPEN IterateOverEmpRecord;

  ins_loop: LOOP
    FETCH IterateOverEmpRecord INTO id, bonus, comm, salary, exempted, proof;

    IF at_end = 1 THEN
      LEAVE ins_loop;
    ELSE        
      IF exempted > proof THEN
        SET exempted = proof;
      END IF;
      SET awarded_pay = bonus + comm;
  
      UPDATE cgtt.tax_cal SET tax_to_be_paid = cgtt.tax_compute(salary,exempted,awarded_pay) WHERE empno = id;
      ITERATE ins_loop;
    END IF;
  END LOOP;

  CLOSE IterateOverEmpRecord;
  
END@

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--     Step4: Create a function 'printITSheet' to print IT sheet for the     --
--            employees, using data in the created temporary table           --
--            'cgtt.tax_cal' through the view 'ViewOnCgtt'.                  --
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
 
CREATE FUNCTION cgtt.printITSheet()
SPECIFIC ITSheet
RETURNS TABLE (empno           CHARACTER(6),
               firstnme        VARCHAR(12),
               lastname        VARCHAR(15),
               birthdate       DATE,
               bonus           DECFLOAT,
               comm            DECFLOAT,
               salarypa        DECFLOAT,
               tax_to_be_paid  DECFLOAT)
LANGUAGE SQL
NO EXTERNAL ACTION
READS SQL DATA
RETURN
  SELECT empno, firstnme, lastname, birthdate, bonus, comm, salarypa, tax_to_be_paid
    FROM cgtt.ViewOnCgtt@


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--    Step 5: Create Trigger 'tax_update' on 'Payroll' table to start the tax --
--            calculation process.                                            -- 
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- The trigger is invoked on update of calculate_tax column of payroll table. --
-- The trigger populates the created temporary table 'tax_cal' and calls the  -- 
-- procedure 'final_tax_compute' to start tax computation process.            --	 
--------------------------------------------------------------------------------

CREATE TRIGGER cgtt.tax_update AFTER UPDATE OF calculate_tax ON cgtt.payroll
REFERENCING NEW TABLE AS new
FOR EACH STATEMENT
BEGIN ATOMIC

  INSERT INTO cgtt.tax_cal 
   (empno, firstnme, lastname, birthdate, bonus, comm, salarypa, tax_payable,
    tax_exempted, tax_to_be_paid, tax_proof, deptno) 
   (SELECT e.empno, e.firstnme, e.lastname, e.birthdate, e.bonus, e.comm, 
          p.salarypa, p.tax_payable, p.tax_exempted, p.tax_to_be_paid, 
	  p.tax_proof, p.deptno 
     FROM employee AS e, cgtt.payroll AS p 
   WHERE e.empno = p.empid AND p.tax_exempted > 0 AND p.deptno = 
     (SELECT DISTINCT deptno FROM cgtt.payroll WHERE calculate_tax = 1));
  
  CALL cgtt.final_tax_compute();
END@


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--    Compute the tax initially to be paid by the employees                  -- 
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
								
-- Call the procedure 'tax_pay' to calculate the tax_payable 
-- by an employee depending on his income and update the 
-- 'payroll' table
CALL cgtt.initial_tax_compute()@

-- Execute RUNSTATS command to update the created temporary table 'cgtt.tax_cal' 
-- to update statistics
RUNSTATS ON TABLE cgtt.tax_cal FOR indexes cgtt.IndexOnId@

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--    GRANT privileges to Bob and Joe on required database objects           --
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-- GRANT privileges on 'cgtt.payroll' table to Bob and Joe
GRANT SELECT, INSERT, UPDATE ON TABLE cgtt.payroll TO USER joe@
GRANT SELECT, INSERT, UPDATE ON TABLE cgtt.payroll TO USER bob@

-- GRANT privileges on 'cgtt.update' procedure to Bob and Joe
GRANT EXECUTE ON PROCEDURE cgtt.update TO USER joe@
GRANT EXECUTE ON PROCEDURE cgtt.update TO USER bob@

-- GRANT privileges on 'cgtt.printITsheet' function to Bob and Joe
GRANT EXECUTE ON FUNCTION cgtt.printITsheet TO USER joe@
GRANT EXECUTE ON FUNCTION cgtt.printITsheet TO USER bob@








