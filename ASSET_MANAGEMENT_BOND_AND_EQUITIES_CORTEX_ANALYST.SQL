use database gen_ai_fsi;
create schema if not exists equity_and_bond_analyst;

create stage if not exists semantic_models directory = (enable = true);
create stage if not exists raw_data directory = (enable = true);

use database gen_ai_fsi;
use schema equity_and_bond_analyst;

-- Upload the csv files into stage raw_data
create or replace TABLE equity_holdings (
	AS_OF_DATE DATE,
	PORTFOLIO TEXT,
	BENCHMARK TEXT,
	INSTRUMENT_ID TEXT,
    WEIGHT_PCT FLOAT,
    ACTIVE_WEIGHT_PCT FLOAT,
    BMK_WEIGHT_PCT FLOAT,
    GICS_IND TEXT,
    GICS_IND_GRP TEXT,
    GICS_SECTOR TEXT,
    GICS_SUBIND TEXT,
    CNTRY_OF_RISK TEXT,
    COMPANY_RATING TEXT,
    ASSET_NAME TEXT,
    ISSUER TEXT
);

create or replace TABLE equity_txns (
	TRADE_DT DATE,
	INSTRUMENT_ID TEXT,
	TRADE_PX FLOAT,
	TRADE_QTY FLOAT,
	BUY_SELL TEXT,
    PORTFOLIO TEXT,
    SETTLED_QTY FLOAT,
    ASSET_NAME TEXT,
    ISSUER TEXT
);


create or replace TABLE bond_holdings (
	AS_OF_DATE DATE,
	PORTFOLIO TEXT,
	BENCHMARK TEXT,
	INSTRUMENT_ID TEXT,
    NOTIONAL FLOAT,
    MARKET_VALUE FLOAT,
    COUPON_RATE FLOAT,
    MATURITY_DT DATE,
    ISSUE_DT DATE,
    WEIGHT_PCT FLOAT,
    ACTIVE_WEIGHT_PCT FLOAT,
    BMK_WEIGHT_PCT FLOAT,
    GICS_IND TEXT,
    GICS_IND_GRP TEXT,
    GICS_SECTOR TEXT,
    GICS_SUBIND TEXT,
    CNTRY_OF_RISK TEXT,
    SEC_SP_RTG TEXT,
    SEC_MDY_RTG TEXT,
    ASSET_NAME TEXT,
    ISSUER TEXT,
    INSTRUMENT_TYPE TEXT
);

create or replace TABLE bond_txns (
	TRADE_DT DATE,
	INSTRUMENT_ID TEXT,
	TRADE_PX FLOAT,
	TRADE_NOTIONAL FLOAT,
	BUY_SELL TEXT,
    PORTFOLIO TEXT,
    SETTLED_QTY FLOAT,
    ASSET_NAME TEXT,
    ISSUER TEXT,
    INSTRUMENT_TYPE TEXT,
    GICS_IND TEXT,
    GICS_IND_GRP TEXT,
    GICS_SECTOR TEXT,
    GICS_SUBIND TEXT,
    CNTRY_OF_RISK TEXT,
    SEC_SP_RTG TEXT,
    SEC_MDY_RTG TEXT
);


COPY INTO equity_holdings
FROM @raw_data
FILES = ('EQUITY_HOLDINGS.csv')
FILE_FORMAT = (
    TYPE=CSV,
    SKIP_HEADER=1,
    FIELD_DELIMITER=',',
    TRIM_SPACE=FALSE,
    FIELD_OPTIONALLY_ENCLOSED_BY=NONE,
    REPLACE_INVALID_CHARACTERS=TRUE,
    DATE_FORMAT=AUTO,
    TIME_FORMAT=AUTO,
    TIMESTAMP_FORMAT=AUTO
    EMPTY_FIELD_AS_NULL = FALSE
    error_on_column_count_mismatch=false
)

ON_ERROR=CONTINUE
FORCE = TRUE ;



COPY INTO equity_txns
FROM @raw_data
FILES = ('EQUITY_TXNS.csv')
FILE_FORMAT = (
    TYPE=CSV,
    SKIP_HEADER=1,
    FIELD_DELIMITER=',',
    TRIM_SPACE=FALSE,
    FIELD_OPTIONALLY_ENCLOSED_BY=NONE,
    REPLACE_INVALID_CHARACTERS=TRUE,
    DATE_FORMAT=AUTO,
    TIME_FORMAT=AUTO,
    TIMESTAMP_FORMAT=AUTO
    EMPTY_FIELD_AS_NULL = FALSE
    error_on_column_count_mismatch=false
)

ON_ERROR=CONTINUE
FORCE = TRUE ;


COPY INTO bond_holdings
FROM @raw_data
FILES = ('BOND_HOLDINGS.csv')
FILE_FORMAT = (
    TYPE=CSV,
    SKIP_HEADER=1,
    FIELD_DELIMITER=',',
    TRIM_SPACE=FALSE,
    FIELD_OPTIONALLY_ENCLOSED_BY=NONE,
    REPLACE_INVALID_CHARACTERS=TRUE,
    DATE_FORMAT=AUTO,
    TIME_FORMAT=AUTO,
    TIMESTAMP_FORMAT=AUTO
    EMPTY_FIELD_AS_NULL = TRUE
    error_on_column_count_mismatch=false
)

ON_ERROR=CONTINUE
FORCE = TRUE ;


COPY INTO bond_txns
FROM @raw_data
FILES = ('BOND_TXNS.csv')
FILE_FORMAT = (
    TYPE=CSV,
    SKIP_HEADER=1,
    FIELD_DELIMITER=',',
    TRIM_SPACE=FALSE,
    FIELD_OPTIONALLY_ENCLOSED_BY=NONE,
    REPLACE_INVALID_CHARACTERS=TRUE,
    DATE_FORMAT=AUTO,
    TIME_FORMAT=AUTO,
    TIMESTAMP_FORMAT=AUTO
    EMPTY_FIELD_AS_NULL = TRUE
    error_on_column_count_mismatch=false
)

ON_ERROR=CONTINUE
FORCE = TRUE ;

/************************************************/
/*****************Normalize Data*****************/
/************************************************/
--to highlight our ability to do cross-schema joins, we'll break the GICs data into another dimension in a seperate schema

--create and use a dimension schema
create schema if not exists EQUITY_AND_BOND_ANALYST_DIMS;
use schema EQUITY_AND_BOND_ANALYST_DIMS;

-- create a sequence to use when filling the dimension
CREATE OR REPLACE SEQUENCE GICS START = 1 INCREMENT = 1;

--create a GICS dimension
DROP TABLE GICS;
CREATE TABLE IF NOT EXISTS GICS AS
    WITH DISTINCT_GICS AS 
        ( SELECT DISTINCT 
            GICS_SECTOR, 
            GICS_IND_GRP, 
            GICS_IND, 
            GICS_SUBIND 
        FROM 
            GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.EQUITY_HOLDINGS 
        ) 
    SELECT 
        GICS.nextval as ID, 
        GICS_SECTOR, 
        GICS_IND_GRP, 
        GICS_IND, 
        GICS_SUBIND 
    FROM DISTINCT_GICS 
    WHERE LEN(TRIM(GICS_SECTOR))>0 
    ORDER BY GICS_SECTOR, GICS_IND_GRP, GICS_IND, GICS_SUBIND ASC;

ALTER TABLE GEN_AI_FSI.EQUITY_AND_BOND_ANALYST_DIMS.GICS ADD PRIMARY KEY (ID);

---------------------------------------
/*Update EQUITY_HOLDINGS with GICS_ID*/
---------------------------------------
USE SCHEMA GEN_AI_FSI.EQUITY_AND_BOND_ANALYST;

--create a temp table with the GICS dimenation ID in place of the GICS columns 
CREATE TEMPORARY TABLE TEMP_FACT AS
    SELECT  
        AS_OF_DATE, 
        PORTFOLIO, 
        BENCHMARK, 
        INSTRUMENT_ID, 
        WEIGHT_PCT, 
        ACTIVE_WEIGHT_PCT, 
        BMK_WEIGHT_PCT, 
        D.ID as GICS_ID,
        --GICS_IND, 
        --GICS_IND_GRP, 
        --GICS_SECTOR, 
        --GICS_SUBIND, 
        CNTRY_OF_RISK, 
        COMPANY_RATING, 
        ASSET_NAME, 
        ISSUER
    FROM 
        GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.EQUITY_HOLDINGS F
    LEFT JOIN 
        GEN_AI_FSI.EQUITY_AND_BOND_ANALYST_DIMS.GICS D ON
        F.GICS_SECTOR =     D.GICS_SECTOR AND 
        F.GICS_IND_GRP =    D.GICS_IND_GRP AND 
        F.GICS_IND =        D.GICS_IND AND
        F.GICS_SUBIND =     D.GICS_SUBIND;

--create EQUITY_HOLDINGS_FACT from the TEMP_FACT
CREATE OR REPLACE TABLE GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.EQUITY_HOLDINGS_FACT AS 
SELECT * FROM TEMP_FACT;

--drop the TEMP_FACT
DROP TABLE TEMP_FACT;

-------------------------------
/*Create an EQUITY_TXNS_FACT */
-------------------------------
--a little bit of a misnomer, there is no GICs in the transactions dataset so I am just creating the transaction fact for clarity
USE SCHEMA GEN_AI_FSI.EQUITY_AND_BOND_ANALYST;

--create a temp table
CREATE TEMPORARY TABLE TEMP_FACT AS
    SELECT  
        TRADE_DT, 
        INSTRUMENT_ID, 
        TRADE_PX, 
        TRADE_QTY, 
        BUY_SELL, 
        PORTFOLIO, 
        SETTLED_QTY, 
        ASSET_NAME, 
        ISSUER
    FROM 
        GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.EQUITY_TXNS F;

--create EQUITY_HOLDINGS_FACT from the TEMP_FACT
CREATE OR REPLACE TABLE GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.EQUITY_TXNS_FACT AS 
SELECT * FROM TEMP_FACT;

--drop the TEMP_FACT
DROP TABLE TEMP_FACT;

---------------------------------------
/*Update BOND_HOLDINGS with GICS_ID*/
---------------------------------------
--the GICS dimension also applies to the BOND_HOLDINGS and BOND_TXNS, let's update those tables with the dimensions
--sanity check: 483 rows in the bond holdings dataset. There are 477 after joining because the cash instrument type doesnt have a GICS
SELECT F.* FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_HOLDINGS F; 

--create a temp table to hold the bond_holdings with a dimensional data
CREATE OR REPLACE TEMPORARY TABLE GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.TEMP_FACT_BOND_HOLDINGS AS
SELECT 
    F.AS_OF_DATE, 
    F.PORTFOLIO, 
    F.BENCHMARK, 
    F.INSTRUMENT_ID, 
    F.NOTIONAL, 
    F.MARKET_VALUE, 
    F.COUPON_RATE, 
    F.MATURITY_DT, 
    F.ISSUE_DT, 
    F.WEIGHT_PCT, 
    F.ACTIVE_WEIGHT_PCT, 
    F.BMK_WEIGHT_PCT, 
    D.ID AS GICS_ID,
    --F.GICS_IND, 
    --F.GICS_IND_GRP, 
    --F.GICS_SECTOR, 
    --F.GICS_SUBIND, 
    F.CNTRY_OF_RISK, 
    F.SEC_SP_RTG, 
    F.SEC_MDY_RTG, 
    F.ASSET_NAME, 
    F.ISSUER, 
    F.INSTRUMENT_TYPE
FROM 
    GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_HOLDINGS F
LEFT JOIN 
    GEN_AI_FSI.EQUITY_AND_BOND_ANALYST_DIMS.GICS D ON 
    F.GICS_SECTOR =     D.GICS_SECTOR AND 
    F.GICS_IND_GRP =    D.GICS_IND_GRP AND 
    F.GICS_IND =        D.GICS_IND AND
    F.GICS_SUBIND =     D.GICS_SUBIND;

--create EQUITY_HOLDINGS_FACT from the TEMP_FACT
CREATE OR REPLACE TABLE GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_HOLDINGS_FACT AS 
SELECT * FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.TEMP_FACT_BOND_HOLDINGS;

--clean up shop
DROP TABLE GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.TEMP_FACT_BOND_HOLDINGS;

---------------------------------------
/*Update BOND_TXNS with GICS_ID*/
---------------------------------------
--the GICS dimension also applies to the BOND_HOLDINGS and BOND_TXNS, let's update those tables with the dimensions
--sanity check: 177 rows in the bond holdings dataset. There are 177 after joining because the cash instrument type doesnt have a GICS
SELECT F.* FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_TXNS F; 

--create a temp table to hold the bond_holdings with a dimensional data
CREATE OR REPLACE TEMPORARY TABLE GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.TEMP_FACT_BOND_TXNS AS
SELECT 
    F.TRADE_DT, 
    F.INSTRUMENT_ID, 
    F.TRADE_PX, 
    F.TRADE_NOTIONAL, 
    F.BUY_SELL, 
    F.PORTFOLIO, 
    F.SETTLED_QTY, 
    F.ASSET_NAME, 
    F.ISSUER, 
    F.INSTRUMENT_TYPE, 
    D.ID AS GICS_ID,
    --F.GICS_IND, 
    --F.GICS_IND_GRP, 
    --F.GICS_SECTOR, 
    --F.GICS_SUBIND, 
    F.CNTRY_OF_RISK, 
    F.SEC_SP_RTG, 
    F.SEC_MDY_RTG
FROM 
    GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_TXNS F
LEFT JOIN 
    GEN_AI_FSI.EQUITY_AND_BOND_ANALYST_DIMS.GICS D ON 
    F.GICS_SECTOR =     D.GICS_SECTOR AND 
    F.GICS_IND_GRP =    D.GICS_IND_GRP AND 
    F.GICS_IND =        D.GICS_IND AND
    F.GICS_SUBIND =     D.GICS_SUBIND;

--create BOND_TXNS_FACT from the TEMP_FACT
CREATE OR REPLACE TABLE GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_TXNS_FACT AS 
SELECT * FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.TEMP_FACT_BOND_TXNS;

--clean up shop
DROP TABLE GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.TEMP_FACT_BOND_TXNS;

/**************************************/
/*************SANITY CHECKS************/
/**************************************/
--SANITY CHECKS: the fact tables shoudl have the same as the base tables 
--BOND_HOLDINGS
SELECT COUNT(*) FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_HOLDINGS; 
SELECT COUNT(*) FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_HOLDINGS_FACT F
LEFT JOIN GEN_AI_FSI.EQUITY_AND_BOND_ANALYST_DIMS.GICS D ON 
    F.GICS_ID =     D.ID; 
    --all good: 483 and 483

SELECT TOP 1 * FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_HOLDINGS_FACT

--BOND_TXNS
SELECT COUNT(*) FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_TXNS;
SELECT COUNT(*) FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_TXNS_FACT F
LEFT JOIN GEN_AI_FSI.EQUITY_AND_BOND_ANALYST_DIMS.GICS D ON 
    F.GICS_ID =     D.ID;
    --all good: 177 and 177

--EQUITY_HOLDINGS
SELECT COUNT(*) FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.EQUITY_HOLDINGS;
SELECT COUNT(*) FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.EQUITY_HOLDINGS_FACT F
LEFT JOIN GEN_AI_FSI.EQUITY_AND_BOND_ANALYST_DIMS.GICS D ON 
    F.GICS_ID =     D.ID;
    -- all good 476 and 476

/*****************************/
/*************DEMO************/
/*****************************/
SELECT * FROM GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_HOLDINGS_FACT;

SELECT F.*,
    GICS_SECTOR, 
    GICS_IND_GRP, 
    GICS_IND, 
    GICS_SUBIND
FROM 
    GEN_AI_FSI.EQUITY_AND_BOND_ANALYST.BOND_HOLDINGS_FACT  F 
INNER JOIN 
    GEN_AI_FSI.EQUITY_AND_BOND_ANALYST_DIMS.GICS D 
    ON F.GICS_ID = D.ID;
