Monthly polls
=============

*Uses [`composes/monthly-polls.yml`](../../composes/monthly-polls.yml).*

This template runs `qcoumes/monthly-polls`, a Discord bot adding a `!monthly_poll <month>` command: it creates polls
(10 days each) to vote on the days of a month. `<month>` is `current`, `next`, or a year and a month (`2026 12`). Dates
are written in french (`fr_FR` locale).

It has no web interface: no Traefik, no port, the bot only connects to Discord.


## Template structure

```
templates/monthly-polls/
└── .env                        # TOKEN: the Discord bot token
```


## Setup (with `qcoumes-deployment`)

1. Create an application and its bot on the [Discord developer portal](https://discord.com/developers/applications),
   enable the **Message Content** intent of the bot (it reads the `!` commands), and invite it on your server.

2. Copy the template and set the bot token in `.env`:

    ```bash
    cp -r templates/monthly-polls/ live/monthly-polls
    ```

3. Start it: `./bin/up.sh monthly-polls`.

A bot token can only be used by one running bot: to run the bot for several Discord applications, create one
environment per token, e.g. `live/monthly-polls-alice/`, and start it with `./bin/up.sh monthly-polls monthly-polls-alice`.
