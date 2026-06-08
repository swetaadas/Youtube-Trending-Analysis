
--   📺  YOUTUBE TRENDING VIDEO ANALYSIS

--   Author: Sweta Das

-- STEP 0: Start fresh (drop if already exists)


DROP SCHEMA IF EXISTS yt CASCADE;
CREATE SCHEMA yt;
SET search_path = yt;


-- STEP 1: Create a  table to load raw CSV data

-- might have nulls, bad values, or inconsistencies.


CREATE TABLE videos_raw (
    video_id          TEXT,
    title             TEXT,
    channel_name      TEXT,
    category_id       INT,
    publish_date      TEXT,   
    trending_date     TEXT,
    views             BIGINT,
    likes             BIGINT,
    dislikes          BIGINT,
    comment_count     TEXT,   
    comments_disabled TEXT,
    ratings_disabled  TEXT,
    tags              TEXT,
    duration_seconds  INT,
    thumbnail_link    TEXT
);



-- STEP 2: Load the CSV into the staging table

-- Replace the path below with wherever you saved the CSV file.


COPY videos_raw
FROM 'your_path'
WITH (FORMAT csv, HEADER true, NULL '');

-- how many rows did we load?
SELECT COUNT(*) AS total_rows_loaded FROM videos_raw;


-- ============================================================
-- STEP 3: Create Lookup Tables (Categories and Channels)


-- Instead of writing category names like "Music" or "Gaming"
-- again and again in the videos table, we store them once here.
-- Each category gets a unique ID.
-- This saves storage and prevents spelling mistakes.

CREATE TABLE categories (
    category_id   INT PRIMARY KEY,
    category_name TEXT NOT NULL
);

-- Add some sample categories

INSERT INTO categories (category_id, category_name) VALUES
    (1,  'Music'),
    (2,  'Gaming'),
    (3,  'Sports'),
    (4,  'Entertainment'),
    (5,  'Education'),
    (6,  'Comedy'),
    (7,  'Science & Tech'),
    (8,  'News'),
    (9,  'Howto & Style'),
    (10, 'Travel & Events');


-- ============================================================
-- Create Channels Table


-- This table will store all unique channel names.
-- SERIAL automatically generates channel IDs (1, 2, 3, ...).

CREATE TABLE channels (
    channel_id   SERIAL PRIMARY KEY,
    channel_name TEXT UNIQUE NOT NULL
);

-- Copy all unique channel names from the raw data table.
-- DISTINCT removes duplicate channel names.

INSERT INTO channels (channel_name)
SELECT DISTINCT channel_name
FROM videos_raw
ORDER BY channel_name;

-- Check how many unique channels were added.

SELECT COUNT(*) AS total_channels
FROM channels;



-- ============================================================
-- STEP 4: Create the Clean Videos Table


-- This is the main table where we will store our final
-- cleaned and organized video data.
--
-- Foreign keys connect this table to the channels and
-- categories tables using their IDs.

CREATE TABLE videos (
    video_id          TEXT PRIMARY KEY,
    title             TEXT NOT NULL,
    channel_id        INT REFERENCES channels(channel_id),
    category_id       INT REFERENCES categories(category_id),
    publish_date      DATE,
    trending_date     DATE,
    views             BIGINT DEFAULT 0,
    likes             BIGINT DEFAULT 0,
    dislikes          BIGINT DEFAULT 0,
    comment_count     BIGINT,      -- NULL means comments are disabled
    comments_disabled BOOLEAN DEFAULT FALSE,
    ratings_disabled  BOOLEAN DEFAULT FALSE,
    tags              TEXT,
    duration_seconds  INT,
    thumbnail_link    TEXT
);


-- ============================================================
-- STEP 5: Move and Clean Data

-- Copy data from videos_raw into videos.
-- While copying, we clean and convert the data:
--
-- 1. Remove extra spaces from titles
-- 2. Find the correct channel_id from channels table
-- 3. Convert text dates into DATE format
-- 4. Prevent negative values for views, likes, dislikes
-- 5. Convert blank comment counts into NULL
-- 6. Convert TRUE/FALSE text into Boolean values
-- 7. Replace '[none]' tags with NULL
-- 8. Skip duplicate video IDs

INSERT INTO videos
SELECT
    r.video_id,

    -- Remove unwanted spaces from title
    TRIM(r.title) AS title,

    -- Get channel ID from channels table
    (SELECT c.channel_id
     FROM channels c
     WHERE c.channel_name = r.channel_name) AS channel_id,

    r.category_id,

    -- Convert text dates to DATE format
    r.publish_date::DATE AS publish_date,
    r.trending_date::DATE AS trending_date,

    -- Make sure values are not negative
    GREATEST(r.views, 0) AS views,
    GREATEST(r.likes, 0) AS likes,
    GREATEST(r.dislikes, 0) AS dislikes,

    -- Store NULL if comment count is blank
    CASE
        WHEN r.comment_count = ''
          OR r.comment_count IS NULL
        THEN NULL
        ELSE r.comment_count::BIGINT
    END AS comment_count,

    -- Convert text TRUE/FALSE into Boolean values
    (r.comments_disabled = 'TRUE') AS comments_disabled,
    (r.ratings_disabled = 'TRUE') AS ratings_disabled,

    -- Replace '[none]' with NULL
    CASE
        WHEN r.tags = '[none]' THEN NULL
        ELSE r.tags
    END AS tags,

    r.duration_seconds,
    r.thumbnail_link

FROM videos_raw r

-- Ignore rows if the video_id already exists
ON CONFLICT (video_id) DO NOTHING;


-- Check how many cleaned records were inserted

SELECT COUNT(*) AS clean_videos_loaded
FROM videos;


-- ============================================================
-- STEP 6: Check if the Data Cleaning Worked


-- 6A: Check for empty or missing video titles.
-- If cleaning was successful, the result should be 0.

SELECT COUNT(*) AS blank_titles
FROM videos
WHERE title IS NULL
   OR TRIM(title) = '';



-- 6B: Count how many videos have comments disabled.
-- GROUP BY creates separate counts for TRUE and FALSE.

SELECT
    comments_disabled,
    COUNT(*) AS video_count
FROM videos
GROUP BY comments_disabled;



-- 6C: Check the range of dates in our dataset.
-- MIN() gives the earliest date.
-- MAX() gives the latest date.

SELECT
    MIN(publish_date) AS earliest_video,
    MAX(publish_date) AS latest_video,
    MIN(trending_date) AS first_trending,
    MAX(trending_date) AS last_trending
FROM videos;



-- ============================================================
-- STEP 7: Using JOINs to Combine Tables


-- JOINs allow us to combine data from multiple tables.
-- Since channel names and category names are stored in
-- separate tables, we use JOINs to bring everything together.


-- ============================================================
-- 7A: INNER JOIN


-- Show video details along with channel name
-- and category name.
--
-- INNER JOIN only returns rows where matching data
-- exists in both tables.

SELECT
    v.video_id,
    v.title,
    ch.channel_name,
    cat.category_name,
    v.views,
    v.likes
FROM videos v
INNER JOIN channels ch
    ON v.channel_id = ch.channel_id
INNER JOIN categories cat
    ON v.category_id = cat.category_id
ORDER BY v.views DESC
LIMIT 20;


-- ============================================================
-- 7B: LEFT JOIN


-- Show all channels and count how many videos
-- belong to each channel.
--
-- LEFT JOIN keeps all records from the left table
-- (channels), even if there is no matching video.

SELECT
    ch.channel_name,
    COUNT(v.video_id) AS videos_trending
FROM channels ch
LEFT JOIN videos v
    ON ch.channel_id = v.channel_id
GROUP BY ch.channel_name
ORDER BY videos_trending DESC;

-- ============================================================
-- STEP 8: Analysis Queries


-- These queries help us understand trends, popularity,
-- engagement, and viewer behavior in the dataset.



-- ============================================================
-- 8A: Top 10 Most Viewed Videos


-- Show the videos with the highest number of views.
-- Also display channel name, category, likes, and trending date.

SELECT
    v.title,
    ch.channel_name,
    cat.category_name,
    v.views,
    v.likes,
    v.trending_date
FROM videos v
JOIN channels ch
    ON v.channel_id = ch.channel_id
JOIN categories cat
    ON v.category_id = cat.category_id
ORDER BY v.views DESC
LIMIT 10;



-- ============================================================
-- 8B: Most Popular Categories


-- Find out which category has the most trending videos.
-- Also calculate average views, total views, and average likes.

SELECT
    cat.category_name,
    COUNT(v.video_id) AS trending_videos,
    ROUND(AVG(v.views)) AS avg_views,
    SUM(v.views) AS total_views,
    ROUND(AVG(v.likes)) AS avg_likes
FROM videos v
JOIN categories cat
    ON v.category_id = cat.category_id
GROUP BY cat.category_name
ORDER BY trending_videos DESC;



-- ============================================================
-- 8C: Engagement Rate of Videos


-- Engagement Rate =
-- (Likes + Comments) / Views × 100
--
-- This shows how actively viewers interact with a video.

SELECT
    v.title,
    ch.channel_name,
    v.views,
    v.likes,
    COALESCE(v.comment_count, 0) AS comments,

    ROUND(
        (v.likes + COALESCE(v.comment_count, 0))::NUMERIC
        / NULLIF(v.views, 0) * 100,
        2
    ) AS engagement_rate_pct

FROM videos v
JOIN channels ch
    ON v.channel_id = ch.channel_id

WHERE v.views > 500000

ORDER BY engagement_rate_pct DESC
LIMIT 15;



-- ============================================================
-- 8D: Days Taken to Trend


-- Calculate how many days passed between
-- publishing and appearing on the trending list.

SELECT
    v.title,
    ch.channel_name,
    v.publish_date,
    v.trending_date,
    (v.trending_date - v.publish_date) AS days_to_trend,
    v.views
FROM videos v
JOIN channels ch
    ON v.channel_id = ch.channel_id
ORDER BY days_to_trend ASC
LIMIT 15;



-- ============================================================
-- 8E: Best Month for Trending Videos


-- Find which month had the most trending videos.
-- TO_CHAR() converts the month number into a month name.

SELECT
    TO_CHAR(trending_date, 'Month') AS month_name,
    EXTRACT(MONTH FROM trending_date) AS month_num,
    COUNT(*) AS videos_trended,
    ROUND(AVG(views)) AS avg_views
FROM videos
GROUP BY month_name, month_num
ORDER BY month_num;



-- ============================================================
-- 8F: Categorize Videos by Views


-- CASE works like an IF-ELSE statement.
-- Videos are grouped into popularity levels.

SELECT
    v.title,
    v.views,

    CASE
        WHEN v.views >= 10000000 THEN 'Mega Viral'
        WHEN v.views >= 5000000  THEN 'Super Trending'
        WHEN v.views >= 1000000  THEN 'Trending'
        WHEN v.views >= 100000   THEN 'Moderate'
        ELSE 'Low Reach'
    END AS video_tier

FROM videos v
ORDER BY v.views DESC;



-- ============================================================
-- 8G: Videos With Tags vs Without Tags


-- Compare the performance of videos that have tags
-- with videos that do not have tags.

SELECT
    CASE
        WHEN tags IS NULL THEN 'No Tags'
        ELSE 'Has Tags'
    END AS tag_status,

    COUNT(*) AS video_count,
    ROUND(AVG(views)) AS avg_views,
    ROUND(AVG(likes)) AS avg_likes

FROM videos
GROUP BY tag_status;



-- ============================================================
-- 8H: Performance Based on Video Length


-- Group videos by duration and compare
-- average views and likes.

SELECT
    CASE
        WHEN duration_seconds < 60   THEN '< 1 Minute (Shorts)'
        WHEN duration_seconds < 300  THEN '1 - 5 Minutes'
        WHEN duration_seconds < 600  THEN '5 - 10 Minutes'
        WHEN duration_seconds < 1200 THEN '10 - 20 Minutes'
        ELSE '20+ Minutes'
    END AS duration_bucket,

    COUNT(*) AS video_count,
    ROUND(AVG(views)) AS avg_views,
    ROUND(AVG(likes)) AS avg_likes

FROM videos
GROUP BY duration_bucket
ORDER BY avg_views DESC;


-- ============================================================
-- STEP 11: SQL Views


-- A VIEW is a virtual table created from a query.
-- It does not store data separately.
-- Instead, it saves a query that can be used again and again.
--
-- Views make reporting and dashboard creation easier.



-- ============================================================
-- 11A: Video Performance View


-- This view combines data from videos, channels,
-- and categories into one easy-to-use report.

CREATE OR REPLACE VIEW v_video_performance AS

SELECT
    v.video_id,
    v.title,
    ch.channel_name,
    cat.category_name,
    v.views,
    v.likes,
    v.dislikes,

    -- Replace NULL comments with 0
    COALESCE(v.comment_count, 0) AS comment_count,

    -- Calculate Like Rate Percentage
    ROUND(
        v.likes::NUMERIC
        / NULLIF(v.views, 0) * 100,
        2
    ) AS like_rate_pct,

    -- Number of days taken to trend
    (v.trending_date - v.publish_date) AS days_to_trend,

    v.trending_date,

    -- Categorize videos based on views
    CASE
        WHEN v.views >= 10000000 THEN 'Mega Viral'
        WHEN v.views >= 5000000  THEN 'Super Trending'
        WHEN v.views >= 1000000  THEN 'Trending'
        ELSE 'Moderate'
    END AS tier

FROM videos v
JOIN channels ch
    ON v.channel_id = ch.channel_id
JOIN categories cat
    ON v.category_id = cat.category_id;



-- Example: Display all Mega Viral videos

SELECT *
FROM v_video_performance
WHERE tier = 'Mega Viral'
ORDER BY views DESC;



-- ============================================================
-- 11B: Channel Leaderboard View
=

-- This view summarizes channel performance.
-- It calculates total views, likes, average views,
-- and trending statistics for each channel.

CREATE OR REPLACE VIEW v_channel_leaderboard AS

SELECT
    ch.channel_name,

    COUNT(v.video_id) AS trending_count,

    SUM(v.views) AS total_views,

    ROUND(AVG(v.views))
        AS avg_views_per_video,

    SUM(v.likes) AS total_likes,

    ROUND(AVG(v.likes))
        AS avg_likes_per_video,

    MIN(v.trending_date)
        AS first_trended,

    MAX(v.trending_date)
        AS last_trended

FROM videos v
JOIN channels ch
    ON v.channel_id = ch.channel_id

GROUP BY ch.channel_name;



-- Example: Top 10 channels by total views

SELECT *
FROM v_channel_leaderboard
ORDER BY total_views DESC
LIMIT 10;


-- ============================================================
-- FINAL CLEANUP: Remove the raw staging table
-- (We don't need it anymore all data is in 'videos')


DROP TABLE videos_raw;


