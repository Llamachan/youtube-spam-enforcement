/*
SPAM-03: Exploratory analysis of yt_spam.comments (1,953 comments, 1,003 spam)

Top 5 findings

1. Call-to-action phrases are the strongest signal so far: 67.8% of spam uses one vs 0.4% of ham (Q4).
2. Repetition marks spam: comments from repeat authors are 80.8% spam vs 51% overall (Q5), and one
   template line ("check out this video on youtube:") was posted 97 times by 92 different authors (Q10).
3. Spam is about twice as long as ham: median 65 vs 34 characters, average 137 vs 50 (Q2).
4. Links are precise but rare: 19.0% of spam has one vs 1.2% of ham, so a link rule alone misses ~81% of spam (Q3).
5. Shouting and posting hour barely separate spam from ham (Q7, Q8); the Psy spam bursts in Nov 2014
   (Q9) need checking against total comment volume before calling them a campaign.
*/

-- Query 1: Spam amount and rate per vide
SELECT video,
  COUNT(*) AS comments,
  SUM(is_spam) AS spam,
  ROUND(100 * AVG(is_spam), 1) AS spam_pct
FROM yt_spam.comments
GROUP BY video
ORDER BY spam_pct DESC;

/*Row	video	    comments	spam	spam_pct
    1	Eminem	    446	        243	    54.5
    2	LMFAO	    438	        236	    53.9
    3	Psy	        350	        175	    50.0
    4	KatyPerry	350	        175	    50.0
    5	Shakira	    369	        174	    47.2
*/

-- Finding: Spam share ranges from 47.2% (Shakira) to 54.5% (Eminem), so about half the comments on every video are spam. The dataset is roughly balanced, which is far more spam than a real comment feed would have.

-- Query 2: Comment length, spam vs ham
SELECT is_spam,
  ROUND(AVG(LENGTH(content))) AS avg_len,
  APPROX_QUANTILES(LENGTH(content), 100)[OFFSET(50)] AS median_len
FROM yt_spam.comments
GROUP BY is_spam;

/*Row	is_spam	   avg_len	  median_len
    1	    0	    50.0	    34
    2	    1	    137.0	    65	
*/

-- Finding: Spam is about twice as long as ham (median 65 vs 34 characters). The spam average (137) is more than double its median, so a tail of very long self-promotion essays pulls it up (see Q10).

-- Query 3: Share of comments with a link

SELECT is_spam,
  ROUND(100 * AVG(IF(REGEXP_CONTAINS(LOWER(content), r'https?://|www\.'), 1, 0)), 1) AS pct_with_link
FROM yt_spam.comments
GROUP BY is_spam;

/*
Row	    is_spam	    pct_with_link
1	        0	        1.2
2	        1	        19.0
*/

-- Finding: 19.0% of spam contains a link vs 1.2% of ham. A link is a strong sign of spam when present, but 81% of spam has no link, so a link rule alone would miss most of it.

-- Query 4: Share with call-to-action words
SELECT is_spam,
  ROUND(100 * AVG(IF(REGEXP_CONTAINS(LOWER(content),
    r'subscribe|check out|my channel|\bfree\b|\bwin\b'), 1, 0)), 1) AS pct_cta
FROM yt_spam.comments
GROUP BY is_spam;

/*
Row	    is_spam	    pct_cta
1	        0	    0.4
2	        1	    67.8	
*/

-- Finding: 67.8% of spam uses a call-to-action phrase vs only 0.4% of ham. This is the strongest single signal so far: it catches two thirds of spam while flagging almost no genuine comments.

-- Query 5: Repeat authors, in total
WITH repeat_authors AS (
  SELECT author, COUNT(*) AS n, SUM(is_spam) AS spam
  FROM yt_spam.comments
  GROUP BY author
  HAVING COUNT(*) > 1
)
SELECT COUNT(*) AS authors,
  SUM(n) AS their_comments,
  ROUND(100 * SUM(spam) / SUM(n), 1) AS their_spam_pct
FROM repeat_authors;

/*
Row	    authors	    their_comments	    their_spam_pct
1	        100	        261	                80.8
*/

-- Finding: 100 authors posted more than once (261 comments), and 80.8% of their comments are spam vs 51% across the whole dataset. Posting repeatedly is a spam signal.

-- Query 6: Ten most active authors

SELECT author, COUNT(*) AS n, SUM(is_spam) AS spam
FROM yt_spam.comments
GROUP BY author
HAVING COUNT(*) > 1
ORDER BY n DESC
LIMIT 10;

/*
Row	author	n	spam
1	M.E.S	8	8
2	Shadrach Grentz	7	7
3	Louis Bryant	7	7
4	5000palo	7	0
5	DanteBTV	6	6
6	LuckyMusiqLive	5	5
7	Hidden Love	5	5
8	Derek Moya	5	5
9	Scott Johnson	4	4
10	RapStarz Coleman	4	4
*/

-- Finding: 9 of the 10 most active authors posted only spam, but one posted 7 comments that were all genuine. Repetition is a strong signal but not proof, so a repeat-count rule needs a second signal to avoid removing real superfans.

-- Query 7: Shouting signals (uppercase share, repeated !!/??, non-ASCII characters)

SELECT is_spam,
  ROUND(AVG(SAFE_DIVIDE(
    LENGTH(REGEXP_REPLACE(content, r'[^A-Z]', '')),
    LENGTH(REGEXP_REPLACE(content, r'[^A-Za-z]', '')))), 3) AS avg_upper_share,
  ROUND(100 * AVG(IF(REGEXP_CONTAINS(content, r'[!?]{2,}'), 1, 0)), 1) AS pct_repeat_punct,
  ROUND(AVG(LENGTH(REGEXP_REPLACE(content, r'[\x00-\x7F]', ''))), 2) AS avg_non_ascii
FROM yt_spam.comments
GROUP BY is_spam;

/*
Row	is_spam	avg_upper_share	pct_repeat_punct	avg_non_ascii
1	0	0.136	9.9	1.4
2	1	0.151	10.1	1.77
*/

-- Finding: Shouting barely differs between spam and ham (uppercase share 0.151 vs 0.136, repeated !!/?? 10.1% vs 9.9%, non-ASCII 1.77 vs 1.40 characters). These are weak signals; leave them out of the SPAM-05 rules.

-- Query 8: Posting hour, spam vs ham

SELECT EXTRACT(HOUR FROM date) AS hour_utc,
  COUNTIF(is_spam = 1) AS spam,
  COUNTIF(is_spam = 0) AS ham
FROM yt_spam.comments
WHERE date IS NOT NULL
GROUP BY hour_utc
ORDER BY hour_utc;

/*
Row	hour_utc	spam	ham
1	0	30	36
2	1	38	44
3	2	28	49
4	3	38	41
5	4	17	22
6	5	25	30
7	6	21	17
8	7	14	32
9	8	16	21
10	9	25	35
11	10	24	28
12	11	30	34
13	12	27	39
14	13	30	45
15	14	33	41
16	15	41	49
17	16	34	46
18	17	50	59
19	18	27	59
20	19	55	52
21	20	46	59
22	21	43	31
23	22	39	49
24	23	29	32
*/

-- Finding: Spam and ham follow the same daily rhythm, both busiest around 17:00 to 20:00 UTC. Spam outnumbers ham only at 06, 19 and 21 UTC, and only slightly, so hour of day is not a useful signal on its own.

-- Query 9: Busiest spam days per video

SELECT DATE(date) AS day, video, COUNTIF(is_spam = 1) AS spam
FROM yt_spam.comments
WHERE date IS NOT NULL
GROUP BY day, video
ORDER BY spam DESC
LIMIT 15;

/*
Row	day	video	spam
1	2014-11-06	Psy	26
2	2014-11-08	Psy	20
3	2014-01-20	Psy	15
4	2014-11-05	Psy	14
5	2014-11-07	Psy	14
6	2014-11-04	Psy	12
7	2014-11-02	Psy	11
8	2013-11-28	Psy	10
9	2014-11-12	Psy	9
10	2014-01-19	Psy	9
11	2014-11-03	Psy	8
12	2014-11-13	Psy	7
13	2014-09-20	KatyPerry	5
14	2014-09-10	KatyPerry	5
15	2014-09-07	KatyPerry	5
*/

-- Finding: 12 of the 15 busiest spam days are on the Psy video, mostly between 2 and 13 Nov 2014 (peak: 26 spam comments on 6 Nov). That looks like a spam wave on one video, but it could also reflect when the data was collected; compare against total comments per day before calling it a campaign.

-- Query 10: Repeated text

SELECT LOWER(TRIM(content)) AS clean_text,
  COUNT(*) AS times,
  COUNT(DISTINCT author) AS authors,
  COUNT(DISTINCT video) AS videos,
  MAX(is_spam) AS is_spam
FROM yt_spam.comments
GROUP BY clean_text
HAVING COUNT(*) > 1
ORDER BY times DESC;

/*
Row	clean_text	times	authors	videos	is_spam
1	check out this video on youtube:﻿	97	92	3	1
2	check out this playlist on youtube:﻿	21	21	3	1
3	check out the new hot video by dante b called riled up	6	1	1	1
4	wow	6	6	1	0
5	hey music fans i really appreciate any of you who will take the time to read this, and check my music out! i&#39;m just a 15 year old boy dreaming of being a successful musician in the music world. i do lots of covers, and piano covers. but i don&#39;t have money to advertise. a simple thumbs up to my comment, a comment on my videos or a subscription would be a step forward! it will only be a few seconds of your life that you won&#39;t regret!!! thank u to all the people who just give me a chance! :)	5	1	1	1
6	nice song﻿	4	4	2	0
7	hi. check out and share our songs.	4	1	1	1
8	awesome﻿	4	4	2	0
9	hey its m.e.s here i&#39;m a young up and coming rapper and i wanna get my music heard i know spam wont get me fame. but at the moment i got no way of getting a little attention so please do me a favour and check out my channel and drop a sub if you enjoy yourself. im just getting started so i really appreciate those who take time to leave constructive criticism i already got 200 subscribers and 4000 views on my first vid ive been told i have potential	4	1	1	1
10	shakira :-*	4	1	1	0
11	like﻿	4	4	1	0
12	waka waka﻿	3	3	1	0
13	katy perry - roar (official): http://youtu.be/cevxzvsjlk8﻿	3	3	1	0
14	i love this song﻿	3	3	2	0
15	**check out my new mixtape**** **check out my new mixtape**** **check out my new mixtape*** ***check out my new mixtape******check out my new mixtape**** **check out my new mixtape**** **check out my new mixtape*** ***check out my new mixtape******check out my new mixtape**** **check out my new mixtape**** **check out my new mixtape*** ***check out my new mixtape******check out my new mixtape**** **check out my new mixtape**** **check out my new mixtape*** ***check out my new mixtape****	3	1	1	1
16	hello everyone :) i know most of you probably pass up these kind of comments, but for those who are still reading this, thanks! i don’t have any money for advertisements, no chance of getting heard, nothing. i live in such a small town... if this comes off as spam, sorry. i’m an instrumental songwriter from columbus, mississippi. please go to my channel and check out my original music. it would be highly appreciated if you thumbs up this comment so my music can be heard! thank you, adam whitney	3	1	1	1
17	love this song makes me wanna dance! ﻿	3	2	1	0
18	cool﻿	3	3	2	0
19	hello guys...i found a way to make money online you can get paid to mess around on facebook and twitter! get paid upto $25 to $35 an hour...only at 4netjobs.com work from the comfort of your home... they are currently hiring people from all over the world, for a wide range of social media jobs on sites such as facebook,twitter and youtube you don&#39;t need any prior skills or experience and you can begin work immediately! you can easily make $4000 to $5000+ monthly income…only at 4netjobs.com	3	2	1	1
20	love this song﻿	3	3	3	0
21	i know that maybe no one will read this but please type in &quot;deazy99&quot; i&#39;m a rapper with a dream. i know you must see like millions of those on here everyday but please check out my music and subscribe if you&#39;d like thank you, i would love nothing more than to have a decent following on youtube from people if anyone reading this could give it a &quot;thumbs up&quot; because what some might see as just a simple button press could make my dream come true..thank you again for your time &amp; may god bless you	3	1	1	1
22	amazing song﻿	3	3	2	0
23	check out this playlist on youtube:<br /><br />﻿	2	2	1	1
24	psy - gangnam style (강남스타일) m/v: http://youtu.be/9bzkp7q19f0﻿	2	2	1	0
25	she is perfect	2	1	1	0
26	i love song ﻿	2	2	1	0
27	:)	2	2	1	0
28	hi everyone! do you like music? then why not check out my music channel.  the lexis band will be uploading their own songs and covers soon so don't  miss out. please subscribe too as it does help us out a lot. just takes one  click. -&gt;﻿	2	1	2	1
29	people, here is a new network like fb...you register also free, the  difference is only that you get paid for sharing, commenting and liking  posts and so one...don't waste your time on fb for sharing and not being  paid!! register here to make also money with your everyday posts!!  https://www.tsu.co/slema13 wellcome to everyone! ;)﻿	2	1	2	1
30	subscribe to my channel﻿	2	2	2	1
31	take a look at this video on youtube:﻿	2	2	2	1
32	check out this video on youtube: ﻿	2	2	2	1
33	is that megan fox?﻿	2	2	1	0
34	check out this playlist on youtube:a﻿	2	2	1	1
35	like this comment for no reason﻿	2	2	1	1
36	subscribe﻿	2	2	1	1
37	everyone please subscribe to my channel or can you all just go look at my videos ﻿	2	1	1	1
38	hahahahah ♥♥♥♥ :d like vines ?  subscribe to me for daily vines	2	1	2	1
39	like this comment then type 1337	2	1	1	1
40	love song﻿	2	2	2	0
41	subscribe to my feed	2	1	2	1
42	check out my sexy video :*	2	1	1	1
43	:d subscribe to me for daily vines	2	1	2	1
44	best song﻿	2	2	1	0
45	check out our bands page on youtube killtheclockhd - check out some of our original songs including &quot;your disguise&quot;	2	1	2	1
46	love﻿	2	2	1	0
47	i hope everyone is in good spirits i&#39;m a hard working student who&#39;s also a passionate singer i look foward to the day when i can make my own music to share but for now i&#39;ve just been doing covers. check out my channel, i&#39;ve done covers of miley cyrus, imagine dragons, lana del rey, drake, macklemore, pink and countless others.  subscribe only if you want to. my goal isn&#39;t to become famous but to  inspire fyi this isn&#39;t spamming, everyone has a right to freedom of speech. thanks	2	1	2	1
48	please check out my video called &quot;we love mind master it&quot; thanks	2	1	2	1
49	stop wasting up your time and  get paid to mess around on facebook and twitter!  get paid upto $25 to $35 an hour... only at 4netjobs.com  work from the comfort of your home... we are currently hiring people from all over the world,  for a wide range of social media jobs on sites such as facebook,twitter and youtube.  you don&#39;t need any prior skills or experience and you can begin work immediately!  you can easily make $4000 to $5000+ monthly income…only at 4netjobs.com	2	1	1	1
50	the best song ever!﻿	2	1	1	0
*/

-- Finding: Repeated text shows three distinct patterns. (1) Many accounts, one template: "check out this video on youtube:" appears 97 times from 92 authors across 3 videos, and the playlist version 21 times from 21 authors; this looks like YouTube's own share-button text, so it may be automated or low-effort sharing rather than one spammer. (2) One account, many copies: long self-promotion essays and money scams (e.g. a work-from-home site) posted 2 to 5 times by the same author. (3) Repeated ham is short generic praise ("wow", "nice song", "love this song") from different authors, so repeated text alone is not spam; it needs a promo phrase or link alongside it.
