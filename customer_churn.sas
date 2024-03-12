
** IMPORT PROJECT DATA TO SAS (PROC IMPORT) **;
PROC IMPORT OUT= WORK.TT 
            DATAFILE= '/home/u63816392/sasuser.v94/Telco_Churn_Data.csv'
            DBMS=CSV REPLACE;
     		GETNAMES=YES;
     		DATAROW=2; 
     		GUESSINGROWS=1000;
RUN;



** DESCRIBE PROPERTIES OF THE PROJECT DATA (PROC CONTENTS) **;
PROC CONTENTS DATA=WORK.TT;
RUN;


/**********************************************************
****** Study Framework (diagram) : Y and X variables ******
***********************************************************/

** CATEGORICAL VARIABLES: IncomeGroup, CreditRating, Occupation, MaritalStatus **;
** CONTINUOUS VARIABLES: MonthlyRevenue, MonthlyMinutes, TotalRecurringCharge, 
                                        OverageMinutes, Handsets, BlockedCalls **;
PROC SQL;
  CREATE TABLE WORK.PROJECT_VARS AS
  SELECT CustomerID,
         Churn,
         IncomeGroup,
         CreditRating,
         Occupation,
         MaritalStatus,
         INPUT(MonthlyRevenue,BEST12.) AS MonthlyRevenue,
         INPUT(MonthlyMinutes,BEST12.) AS MonthlyMinutes,
         INPUT(TotalRecurringCharge,BEST12.) AS TotalRecurringCharge,
         INPUT(OverageMinutes,BEST12.) AS OverageMinutes,
         Handsets,
         BlockedCalls 
  FROM WORK.TT
  WHERE CHURN NE "NA";
QUIT;
/* INPUT(---,BEST12.) is typecasting to num */


PROC CONTENTS DATA= Work.PROJECT_VARS;
RUN;


/*********************************************************
****** Data Validation: missing values and outliers ******
**********************************************************/

** MISSING VALUE DETECTION **;

* CATEGORICAL *;

*ORIGINAL WAY*;
PROC FREQ DATA = WORK.PROJECT_VARS;
  TABLES Churn IncomeGroup CreditRating Occupation MaritalStatus/missing;
run;

***MACRO PROGRAM***;
/*A macro creates reusable pieces of code that starts withe %MACRO  and ends with %MEND.*/

%MACRO MISS_CAT(VARS=, DSN=);
ODS PDF FILE="PROJECT_MISSING_CAT.PDF";
TITLE 'DATASET: &DSN';
TITLE2 'CATEGORICAL VARIABLES';
TITLE3 'MISSING VALUES FOR &VARS';
PROC FREQ DATA=&DSN;
ABLE &VARS / MISSING;
    RUN;
ODS PDF CLOSE;
%MEND MISS_CAT;

/* CALL MACRO PROGRAM */
%MISS_CAT(VARS=Churn IncomeGroup CreditRating Occupation MaritalStatus, DSN=WORK.PROJECT_VARS);

/* ORIGINAL */
PROC MEANS DATA=WORK.PROJECT_VARS MAXDEC=2 N NMISS MIN MEAN STD MAX RANGE;
 VAR MonthlyRevenue MonthlyMinutes TotalRecurringCharge OverageMinutes Handsets BlockedCalls;
RUN;
/* ---------------------------------------------------------- */
***MACRO PROGRAM***;
%MACRO MISS_CONT(VARS=, DSN=);
ODS PDF FILE="PROJECT_MISSING_CONT.PDF";
TITLE 'DATASET: &DSN';
TITLE2 'CONTINUOUS VARIABLES';
TITLE3 'MISSING VALUES FOR &VARS';
    PROC MEANS DATA=&DSN MAXDEC=2 N NMISS MIN MEAN STD MAX RANGE;
      VAR &VARS;
    RUN;
ODS PDF CLOSE;
%MEND MISS_CONT;

%MISS_CONT(VARS=MonthlyRevenue MonthlyMinutes TotalRecurringCharge OverageMinutes Handsets BlockedCalls, DSN=WORK.PROJECT_VARS);

/* MISSING VALUE TREATMENT (MEANS OR MEDIAN) */

/* ONLY FOR CONTINUOUS VARS */
/* REPLACE ALL MISSING VALUES WITH MEAN */
PROC STDIZE DATA=WORK.PROJECT_VARS OUT=WORK.PROJECT METHOD=MEAN REPONLY;
 VAR MonthlyRevenue MonthlyMinutes TotalRecurringCharge OverageMinutes Handsets BlockedCalls;
RUN;
/* ------------------------------------------------------------------------- */

* CHECK TO MAKE SURE ALL MEANS ARE REPLACED *;
PROC MEANS DATA = WORK.PROJECT MAXDEC=2 N NMISS MIN MEAN STD MAX RANGE;
  VAR MonthlyRevenue MonthlyMinutes TotalRecurringCharge OverageMinutes Handsets BlockedCalls;
RUN;

PROC CONTENTS DATA= WORK.PROJECT;
RUN;


/* statistical graphics */
** OUTLIER DETECTION AND TREATMENT **;
** BOXPLOT, WHISKER PLOT **;
PROC SGPLOT DATA = WORK.PROJECT ;
 VBOX TotalRecurringCharge/DATALABEL= TotalRecurringCharge;
RUN; 

* FIND Q1, Q3, IQR *;
PROC MEANS DATA = WORK.PROJECT MAXDEC=2 N P25 P75 QRANGE;
  VAR TotalRecurringCharge;
RUN;
* Q1 = 30 / Q3 = 60 / IQR = 30 *;
* LOWERLIMIT = Q1-(3*IQR) = -60 *;
* UPPERLIMIT = Q3+(3*IQR) = 150 *;

PROC SQL;
  CREATE TABLE WORK.PROJECT_OUTLIER AS 
  SELECT * 
  FROM WORK.PROJECT
  WHERE (TotalRecurringCharge BETWEEN -60 AND 150);
QUIT;

PROC CONTENTS DATA=WORK.PROJECT_OUTLIER;
RUN;
  

/********************************************************************
****** Data Transformation: continuous to categorical variable ******
*********************************************************************/

** TURN MonthlyMinutes FROM CONTINUOUS TO CATEGORICAL **; 

PROC FORMAT;
  VALUE MINGRP LOW - 300 = "NORMAL"
               301 - 600 = "MEDIUM"
               601 - 1000 = "HIGH"
               1001 - 2000 = "VERY HIGH"
               2001 - HIGH = "EXTREME";
RUN;

PROC FREQ DATA = WORK.PROJECT_OUTLIER;
  TABLE MonthlyMinutes;
  FORMAT MonthlyMinutes MINGRP.;
RUN;


/****************************************************
****** Univariate Analysis: tabular and graphs ******
*****************************************************/


%MACRO UNIVAR(VARS=, DSN=);
ODS PDF FILE="PROJECT_&CONT_VAR._PPT.PDF";
    PROC MEANS DATA=&DSN MAXDEC=2 N NMISS MIN MEAN MEDIAN MAX STD CLM STDERR;
    TITLE " UNIVARIATE ANALYSIS OF " %UPCASE(&VARS);
     VAR &VARS;
    RUN;

    PROC SGPLOT DATA=&DSN;
    TITLE " DISTRIBUTION OF " %UPCASE(&VARS);
     HISTOGRAM &VARS;
     DENSITY &VARS;
    RUN;

    PROC SGPLOT DATA=&DSN;
    TITLE " DISTRIBUTION OF " %UPCASE(&VARS);
     VBOX &VARS;
    RUN;

    PROC UNIVARIATE DATA=&DSN;
    TITLE "COMPREHENSIVE UNIVARIATE ANALYSIS OF " %UPCASE(&VARS);
     VAR &VARS;
    RUN;
ODS PDF CLOSE;
%MEND UNIVAR;

%UNIVAR(VARS=TotalRecurringCharge, DSN=WORK.PROJECT_OUTLIER);


/***********************************************************************************
****** Bivariate Descriptive Analysis: categorical vs continuous /categorical ******
************************************************************************************/

%LET VAR1=Occupation;
%LET VAR2=MonthlyMinutes;

ODS PDF FILE="PROJECT_BIVAR_&VAR1._&VAR2._PPT.PDF";
PROC FREQ DATA=WORK.PROJECT_OUTLIER;
  TITLE "RELATIONSHIP BETWEEN BETWEEN &VAR1. AND &VAR2.";
  TABLE &VAR1. * &VAR2. / CHISQ NOROW NOCOL;
  FORMAT MonthlyMinutes MINGRP.;
RUN;

PROC SGPLOT DATA=WORK.PROJECT_OUTLIER;
  TITLE "RELATIONSHIP BETWEEN BETWEEN &VAR1. AND &VAR2.";
  VBAR &VAR1. / GROUP=&VAR2.;
  FORMAT MonthlyMinutes MINGRP.;
RUN;

take out Other;
PROC SGPLOT DATA=WORK.PROJECT_OUTLIER;
  TITLE "RELATIONSHIP BETWEEN BETWEEN &VAR1. AND &VAR2.";
  TITLE2 "(WITHOUT OTHER)";
  VBAR &VAR1. / GROUP=&VAR2.;
  WHERE Occupation NE 'Other';
  FORMAT MonthlyMinutes MINGRP.;
RUN;

*take out Other and *;

PROC SGPLOT DATA=WORK.PROJECT_OUTLIER;
  TITLE "RELATIONSHIP BETWEEN BETWEEN &VAR1. AND &VAR2.";
  TITLE2 "(WITHOUT OTHER AND PROFESSIONAL)";
  VBAR &VAR1. / GROUP=&VAR2.;
  WHERE (Occupation NE 'Other') AND (Occupation NE 'Professional');
  FORMAT MonthlyMinutes MINGRP.;
RUN;

QUIT;
ODS PDF CLOSE;

/************************************
****** Hypothesis testing ************
************************************/

/* Convert Churn to numeric first */
DATA WORK.FINAL;
  SET WORK.PROJECT_OUTLIER;
  IF Churn EQ 'Yes' THEN NUMChurn=1;
  ELSE NUMChurn=0;
RUN;

/* Churn ~ Occupation */
/* Churn ~ MonthlyMinutes */
/* PEARSONS */
/* H0: no association/correlation */
/* HA: MonthlyRevenue and MonthlyMinutes are associated with Score */
/* IF P <= 0.05 THEN REJECT H0 */
TITLE "Conducting Pearson Correlation";
PROC CORR DATA=WORK.FINAL;
  VAR MonthlyRevenue MonthlyMinutes;
  WITH NUMChurn;
RUN;

/* ------------------------------------------------------------------------- */
/* Split the data into training and testing sets */

/* Split the data into train and test data set */
PROC SURVEYSELECT DATA=WORK.FINAL OUT=WORK.TRAIN METHOD=SRS SAMPRATE=0.8;
RUN;

DATA WORK.TEST;
   MERGE WORK.FINAL(IN=A) WORK.TRAIN(IN=B);
   BY CustomerID;
   IF A AND NOT B;
RUN;

/* Fit the logistic regression model using the training data and save the model */
PROC LOGISTIC DATA=WORK.TRAIN OUTMODEL=WORK.LOGISTIC_MODEL;
    CLASS CreditRating Occupation MaritalStatus (param=ref);
    MODEL Churn(event='Yes') = IncomeGroup CreditRating Occupation MaritalStatus MonthlyRevenue MonthlyMinutes / LINK=LOGIT;
RUN;




/* Score the testing data using the logistic model trained on the training data */
PROC LOGISTIC INMODEL=WORK.LOGISTIC_MODEL;
    SCORE DATA=WORK.TEST OUT=WORK.SCORED;
RUN;


/* Calculate metrics */
DATA WORK.PRED;
    SET WORK.SCORED;
    PREDPROB = P_1_;
RUN;

/* Print the scored data */
PROC PRINT DATA=WORK.PRED;
RUN;
/* --------------------------------- */
/* Calculate metrics */
DATA WORK.EVAL;
   SET WORK.SCORED;
   PREDICTED = (P_1_ >= 0.5); /* Convert probability to predicted binary outcome */
RUN;

/* Calculate confusion matrix */
PROC FREQ DATA=WORK.EVAL;
   TABLES Churn * PREDICTED / AGREE;
RUN;

/* Calculate metrics */
DATA WORK.METRICS;
   SET WORK.EVAL;
   TP = (Churn='Yes' AND PREDICTED=1);
   FP = (Churn='No' AND PREDICTED=1);
   TN = (Churn='No' AND PREDICTED=0);
   FN = (Churn='Yes' AND PREDICTED=0);

   ACCURACY = (TP + TN) / (TP + FP + TN + FN);
   PRECISION = TP / (TP + FP);
   RECALL = TP / (TP + FN);
   F1_SCORE = 2 * (PRECISION * RECALL) / (PRECISION + RECALL);
RUN;

/* Print metrics */
PROC PRINT DATA=WORK.METRICS;
   VAR ACCURACY PRECISION RECALL F1_SCORE;
RUN;