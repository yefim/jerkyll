---
layout: post
title: Metric Time
---

## The Idea

The metric system is perfectly regimented. Base 10 is such a simple conversion factor. 1 kilometer is 1000 meters, 1 liter is 1000 milliliters, and so on.

A friend and I decided to implement the same schema for time.

We started with the second and aimed to eliminate both minutes and hours.

There are 86400 seconds in a day. Applying traditional metric prefixes, we calculated 86.4 kiloseconds per day. More importantly, this time applying slightly untraditional metric prefixes, we arrived at 8.64 myriaseconds in one day.

8.64 myriaseconds is a very manageable amount of time.

1 myriasecond is a bit less than 3 hours. A lot can be done in 1 myriasecond. I can build out an app prototype, go out to eat, watch a movie, take a nap, and much, much more.

## Implementation

Now that we had a basic unit of metric time measurement, the myriasecond, we had to meld our hour-and-minute-accustomed minds to accept the new metric.

Surprisingly, this feat was not as difficult as we had imagined.

I realized that midday occurred at 4.32 myriaseconds, I wake up at around 3, and I would get home from work at 6.

Although we began by relying solely on mental conversions between units, associating relative times of the day to certain myriaseconds weaned us off memorization and propelled us into the direction of intuitive time-telling.

## Next Steps

My roommates are already on board, confused as they are. Friends and family, next.

I'm also currently reading up on some docs to hack my Pebble watch to display time in myriaseconds. Expect great things.

_I am a rising junior at the university of pennsylvania, majoring in math and computer science. For other quirky thoughts, feel free to follow me, [@yefim](https://twitter.com/yefim)._
