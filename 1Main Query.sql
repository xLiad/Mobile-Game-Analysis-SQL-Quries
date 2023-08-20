USE LiadGames;

--- DATA VALIDATION ---

--------------------------------------------------------------------------------------------------------------------------
-- 1 rating given to the game by user id that did not install it (the user_id number is not in the "game_install" table)
--------------------------------------------------------------------------------------------------------------------------

DELETE FROM GamesRatings WHERE rating_id IN 
											(
											SELECT GR.rating_id
											FROM GamesRatings GR LEFT JOIN GameInstalls GI ON GR.user_id = GI.user_id
											WHERE GI.install_date IS NULL
											)

GO
---------------------------------------------------------------------------------------------
-- 2 every user can only rate the game 1 time (removing duplicate user_id in "rating" table)
---------------------------------------------------------------------------------------------

DELETE FROM GamesRatings WHERE rating_id IN 
		(
		SELECT A.rating_id
		FROM    (
				SELECT GR.rating_id, GR.user_id, GR.rating_date, GI.install_date, ROW_NUMBER () OVER (PARTITION BY GR.user_id ORDER BY GR.user_id) AS "RN"
				FROM GamesRatings GR LEFT JOIN GameInstalls GI ON  GR.user_id = GI.user_id
				) A
		WHERE A.RN > 1
		)

GO
----------------------------------------------------------------------------------------------------------------------------------------------
-- 3 giving rating to the game before installing it (the date in "rate_date" column is older then the "install_date" date for this users_id's)
----------------------------------------------------------------------------------------------------------------------------------------------

DELETE FROM GamesRatings WHERE rating_id IN 
(
SELECT GR.rating_id
FROM GamesRatings GR JOIN GameInstalls GI ON GR.user_id = GI.user_id
WHERE GI.install_date > GR.rating_date
)


GO
-------------------------------------------------------------------------------------------------------------------------------------------
-- 4 logging in to a game before installing it (the date in "log_in_date" column is older then the "install_date" date for this users_id's)
-------------------------------------------------------------------------------------------------------------------------------------------

WITH cte_first_install
AS
		(
		SELECT user_id, min(install_date) AS "FirstInstall"
		FROM GameInstalls
		GROUP BY user_id
		)
DELETE FROM Log_In WHERE log_id IN 
	(
	SELECT L.log_id
	FROM cte_first_install FI JOIN Log_In L ON FI.user_id = L.user_id
	WHERE FI.FirstInstall > L.log_in_date
	)

GO
---------------------------------------------------------------------------------------------------------
-- 5 a log in to the game by user_id that did not install it (user_id number not in the "install" table)
---------------------------------------------------------------------------------------------------------

DELETE FROM Log_In WHERE user_id NOT IN 
		(
		SELECT user_id
		FROM GameInstalls
		)

GO

-------------------------------------------------------------------
-- 6 premuim item purchase by a user_id that did not install table
-------------------------------------------------------------------

DELETE FROM Purchases WHERE purchase_id IN
										(
										SELECT purchase_id
										FROM Purchases
										EXCEPT 
										SELECT P.purchase_id
										FROM Purchases P JOIN GameInstalls GI ON P.user_purchased = GI.user_id
										)
GO

------------------------------------------------------------------
-- 7 purchasing premuim item from game before installing the game
------------------------------------------------------------------

WITH cte_first_install2
AS
		(
		SELECT user_id, min(install_date) AS "FirstInstall"
		FROM GameInstalls
		GROUP BY user_id
		)
DELETE FROM Purchases WHERE purchase_id IN 
	(
	SELECT P.purchase_id
	FROM cte_first_install2 FI JOIN Purchases P ON FI.user_id = P.user_purchased
	WHERE FI.FirstInstall > P.purchase_date
	)

GO


--------------- ANALYSIS -----------------

-------------------------------------------------
--Average Revenue Per Daily Active User (ARPDAU)
-------------------------------------------------

-- DAU

SELECT A.Month AS "Month",
       A.Day AS "Day",
	   A.Count
FROM       
			(
			SELECT MONTH(log_in_date) AS "Month",
				   DAY (log_in_date) AS "Day",
				   COUNT (DISTINCT user_id) AS "Count"
			FROM Log_In
			GROUP BY MONTH(log_in_date), DAY (log_in_date)
			) A
ORDER BY 1,2


-- Revnue

SELECT CAST ('2020'+'/'+ CAST(A.Month AS VARCHAR(MAX))+'/'+ CAST (A.Day AS varchar (MAX)) AS date) AS "Date",
       A.Revenue
FROM    
		(
		SELECT MONTH(P.purchase_date) AS "Month",
			   DAY(P.purchase_date) AS "Day",
			   SUM(PI.cost) AS "Revenue"
		FROM Purchases P JOIN PremuimItems PI ON P.purchased_item_id = PI.premuim_item_id
		WHERE YEAR (purchase_date) = '2020'
		GROUP BY MONTH(P.purchase_date), DAY(P.purchase_date) 
        ) A
ORDER BY 1

-------------------------------------
--Average Minutes VS Times Logged In
-------------------------------------

-- Total Minutes

SELECT user_id, SUM([minutes played]) AS "Sum Minutes"
FROM Log_In
GROUP BY user_id

-- Times Logged In

SELECT user_id, COUNT (*) AS "TimesLoggedIn"
FROM Log_In
GROUP BY user_id

---------------
-- Churn Rate
---------------

SELECT B.Week, COUNT (B.user_id) AS "Count Active Player"
FROM    (
		SELECT A.user_id,
			   A.NextWeekLogged AS "Week",
			   CASE WHEN A.WeekLog + 1 = A.NextWeekLogged OR A.WeekLog = A.NextWeekLogged THEN 'Active Player'
					WHEN A.WeekLog + 1 <> A.NextWeekLogged THEN 'Churn'
					ELSE NULL END AS "Status"
		FROM        (
					SELECT user_id,
						   log_in_date,
						   DATEPART(WEEK,log_in_date) AS "WeekLog",
						   LEAD (log_in_date) OVER (PARTITION BY user_id ORDER BY log_in_date) AS "NextTimeLoggeD",
						   LEAD (DATEPART(WEEK,log_in_date)) OVER (PARTITION BY user_id ORDER BY DATEPART(WEEK,log_in_date)) AS "NextWeekLogged"
					FROM Log_In
					WHERE YEAR(log_in_date) = '2020'
					) A
		) B
WHERE B.Status IS NOT NULL AND B.Status = 'Active Player'
GROUP BY B.Week




-- Total Distinct User By Week


SELECT A.Week, COUNT (DISTINCT A.user_id) AS "Count"
FROM 
	(
	SELECT log_id,
	       user_id,
		   log_in_date,
		   log_off_date,
		   [minutes played],
		   DATEPART(WEEK,log_in_date) AS "Week"
	FROM Log_In
	) A
GROUP BY A.Week

--------------------
-- Conversion Rate
--------------------

-- Distinct Users That Made a Purchases

SELECT MONTH (purchase_date) AS "Month", 
       COUNT (DISTINCT user_purchased) AS "Count"
FROM Purchases
WHERE YEAR(purchase_date) = '2020' 
GROUP BY MONTH (purchase_date)

-- Distinct Users That Had The Ability To Purchases

SELECT MONTH (log_in_date) AS "Month",
       COUNT (DISTINCT user_id) AS "Count"
FROM Log_In
WHERE YEAR(log_in_date) = '2020'
GROUP BY MONTH (log_in_date)


--------------------
-- Game Sinks Check
--------------------

-- User And His Purchases

SELECT user_id, SUM (effect) AS "Total"
FROM user_actions
WHERE effect < 0 AND user_id IN ((SELECT DISTINCT user_id
								 FROM user_actions
								 WHERE effect > 0))
GROUP BY user_id


-- User And His Currency Generating Actions

SELECT user_id, SUM (effect) AS "Total"
FROM user_actions
WHERE effect > 0 AND user_id IN (SELECT DISTINCT user_id
								 FROM user_actions
								 WHERE effect < 0)
GROUP BY user_id

------------------------------
-- All Purchases Made by Users
------------------------------

SELECT P.purchase_id, 
       P.user_purchased, 
	   PI.premuim_item_name, 
	   PI.[item genre], PI.cost
FROM Purchases P JOIN PremuimItems PI ON P.purchased_item_id = PI.premuim_item_id
WHERE YEAR(P.purchase_date) = '2020'
                 
---------------------------
-- Total Minutes VS Rating
---------------------------

-- Users And Their Rating

SELECT user_id, rate
FROM GamesRatings
ORDER BY user_id

-- Users And Their Total Minutes Played

SELECT user_id, SUM([minutes played]) AS "Minutes Played"
FROM Log_In
WHERE user_id IN 
					(
					SELECT user_id
					FROM GamesRatings
					)
AND YEAR (log_in_date) = '2020'
GROUP BY user_id
ORDER BY user_id

---------------
-- Retenation
---------------

-- Retantion Players (Weekly Basis)

SELECT B.WeekNumber ,COUNT (DISTINCT B.user_id) AS "Count"
FROM        (
			SELECT    A.user_id,
					  A.NextTimeLoggeD,
					  DATEPART (WEEK,A.log_in_date) AS "WeekNumber",
					  DATEDIFF (WEEK, A.log_in_date, A.NextTimeLoggeD) AS "HowManyWeeksToNextLogIn"
			FROM    (
					SELECT log_id, 
							log_in_date,
							log_off_date,
							[minutes played],
							user_id,
							LEAD (log_in_date) OVER (PARTITION BY user_id ORDER BY log_in_date) AS "NextTimeLoggeD"
					FROM Log_In
					WHERE YEAR(log_in_date) = '2020'
					) A
			) B
WHERE B.NextTimeLoggeD IS NOT NULL AND B.HowManyWeeksToNextLogIn = 1
GROUP BY B.WeekNumber


-- Total Distinct Players (Weekly Basis)

SELECT DATEPART(WEEK,log_in_date) AS "WeekNumber", COUNT (DISTINCT user_id) AS "Count"
FROM Log_In
WHERE YEAR(log_in_date) = '2020'
GROUP BY DATEPART(WEEK,log_in_date)


------------------------------------------------
-- Total Game Currency In Over The Year By Month 
------------------------------------------------
;
WITH cte_running_total
AS
	(
	SELECT MONTH(action_date) AS "Month1", 
		   SUM (effect) AS "Sum"
	FROM user_actions
	GROUP BY MONTH(action_date)
	)
SELECT c2.Month1, (SELECT SUM(c1.Sum)
                   FROM cte_running_total c1
				   WHERE c1.Month1 <= c2.Month1) AS "Total Crab Coins"
FROM cte_running_total c2
ORDER BY Month1
;

-----------------------------------------------
-- Sum Total Minutes (All Users) Per Rating
------------------------------------------------

SELECT gr.rate, SUM (L.[minutes played]) AS "Total_Minutes"
FROM GamesRatings GR JOIN Log_In L ON GR.user_id = L.user_id
GROUP BY GR.rate
ORDER BY 1



