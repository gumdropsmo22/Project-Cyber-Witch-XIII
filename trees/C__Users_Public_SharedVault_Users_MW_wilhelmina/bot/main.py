from dotenv import load_dotenv
load_dotenv()

import os, asyncio, discord
from discord.ext import commands

INTENTS = discord.Intents.default()
INTENTS.message_content = False
INTENTS.members = True
INTENTS.voice_states = True

bot = commands.Bot(command_prefix="!", intents=INTENTS)

@bot.event
async def on_ready():
    print(f"Logged in as {bot.user} (latency {bot.latency*1000:.0f}ms)")
    await bot.tree.sync()

async def _load():
    # load only what you have right now
    await bot.load_extension("wilhelmina.cogs.oracles")

def main():
    token = os.getenv("DISCORD_BOT_TOKEN") or os.getenv("DISCORD_TOKEN")
    offline = os.getenv("DEV_OFFLINE") == "1" or not token
    if offline:
        print("Offline dev mode: skipping Discord login.")
        import importlib
        importlib.import_module("wilhelmina.cogs.oracles")
        print("Cogs imported OK.")
        return
    asyncio.run(_load())
    bot.run(token)

if __name__ == "__main__":
    main()