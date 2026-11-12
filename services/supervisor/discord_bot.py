"""Discord bot of the Babylon13 cluster. It runs in the supervisor process.

Features (BABYLON_DISCORD_FEATURES, see modular_babylon/CLUSTER.md):
  link     /link and /unlink: bind a Discord account to a BYOND account
  roles    self-assignable role buttons (custom_id babylon:role:<role id>)
  voice    join-to-create voice rooms from the voice lobby channel
  logs     member, message, voice and moderation logs
  status   a live status message, refreshed every minute
  gamelog  supervisor events (world starts, stops, saves, joins) in a channel
  tickets  support tickets: a button in a read-only channel opens a private
           channel for the member and the staff; closing it sends a .txt
           transcript to the member and to the ticket log
/status and the moderators' /whois are always available.
"""
import asyncio
from collections import deque
import io
import json
import re
from pathlib import Path
import threading
import time

import discord
from discord import app_commands

from logstream import emit, subscribe

FEATURES = ("link", "roles", "voice", "logs", "status", "gamelog", "tickets")
ROLE_BUTTON = "babylon:role:"
COLOR_BUTTON = "babylon:color:"
TICKET_OPEN, TICKET_ADD, TICKET_CLOSE = "babylon:ticket:open", "babylon:ticket:add", "babylon:ticket:close"
# babylon:ahelp:reply:<run id>:<ckey> and babylon:ahelp:close:<run id>:<ticket>, at most 83
# characters (Discord allows 100).
AHELP_REPLY, AHELP_CLOSE = "babylon:ahelp:reply:", "babylon:ahelp:close:"
VOICE_KICK, VOICE_BAN, VOICE_UNBAN = "babylon:voice:kick", "babylon:voice:ban", "babylon:voice:unban"
VOICE_LIMIT, VOICE_UNLIMIT = "babylon:voice:limit", "babylon:voice:unlimit"
VOICE_RENAME, VOICE_TRANSFER = "babylon:voice:rename", "babylon:voice:transfer"
VOICE_BUTTONS = (VOICE_KICK, VOICE_BAN, VOICE_UNBAN, VOICE_LIMIT, VOICE_UNLIMIT, VOICE_RENAME, VOICE_TRANSFER)
TEAL, RED, AMBER, GREY = 0x7DD3C7, 0xE5534B, 0xF0A04B, 0x8A94A6


def log(text):
    emit("discord", text)


def clip(text, limit=1000):
    text = str(text or "")
    return text if len(text) <= limit else text[:limit - 1] + "…"


def md(text):
    """Player-written text shown in Discord Markdown: no formatting, no masked links."""
    return discord.utils.escape_markdown(str(text or ""), as_needed=False)


def running_worlds_label(snapshot):
    """Running worlds against the limit; admin worlds run outside it and show as "(+1)"."""
    label = f"{snapshot['running_worlds']}/{snapshot['max_running_worlds']}"
    return label + (f" (+{snapshot['admin_worlds']})" if snapshot.get("admin_worlds") else "")


def status_embed(snapshot, settings, online=True):
    """The status message; private worlds are shown without their name."""
    if not online:
        return discord.Embed(title="Babylon13 status", color=RED,
                             description="🔴 **Offline.** The server is restarting or under maintenance.")
    worlds = snapshot["worlds"]
    running = [w for w in worlds if w["state"] in ("starting", "running")]
    lines = []
    for world in running:
        name = f"**{md(world['name'])}**" if world["name"] else "*A private world*"
        state = "starting" if world["state"] == "starting" else f"{world['players']}/{world['max_players']} players"
        kind = "admin world" if world.get("admin") else world["visibility"]
        lines.append(f"• {name} ({kind}): {state}")
    embed = discord.Embed(title="Babylon13 status", color=TEAL, description="🟢 **Online**")
    join = settings.get("join_url")
    address = settings.get("address")
    if join or address:
        embed.add_field(name="Join", value="\n".join(filter(None, [f"[Join page]({join})" if join else None,
                                                                    f"`{address}`" if address else None])),
                        inline=False)
    embed.add_field(name="Players in worlds", value=str(snapshot["players"]))
    embed.add_field(name="Running worlds", value=running_worlds_label(snapshot))
    embed.add_field(name="Worlds", value=str(snapshot["total_worlds"]))
    embed.add_field(name="Now running", value="\n".join(lines)[:1024] if lines else "No world is running. Start one from the lobby!",
                    inline=False)
    embed.set_footer(text="Updated every minute")
    embed.timestamp = discord.utils.utcnow()
    return embed


def audit_target(entry):
    """The entry's target as a mention. discord.py resolves entry.target lazily and raises
    for entries without a target id, so the lookup must never break the handler."""
    try:
        target_id = getattr(entry.target, "id", None)
    except (TypeError, ValueError, AttributeError):
        target_id = None
    return f"<@{target_id}>" if target_id else "unknown"


def ahelp_entry(event):
    """The Discord message for one adminhelp event, and its Reply button for player messages."""
    who = md(event["key"] or event["ckey"])
    text = clip(md(event["message"]), 3500) or "*(no text)*"
    number = f"#{event['ticket']}" if event["ticket"] is not None else "(no ticket)"
    kind = event["kind"]
    if kind == "new":
        embed = discord.Embed(title=clip(f"🆘 Adminhelp {number} from {event['key'] or event['ckey']}", 256), color=AMBER, description=text)
        embed.add_field(name="World", value=clip(md(event["world"]), 1024))
        embed.add_field(name="Player", value=f"`{event['ckey']}`")
        embed.set_footer(text="Reply with the button; the player gets it as an admin PM. The conversation continues in the thread.")
    elif kind == "admin":
        embed = discord.Embed(color=TEAL, description=f"🛡️ **{md(event['sender'] or 'An admin')}** (in game) → **{who}**: {text}")
    else:
        label = "replied" if kind == "reply" else "wrote"
        embed = discord.Embed(color=AMBER, description=f"💬 **{who}** {label}: {text}")
    buttons = []
    if kind != "admin" and event["ckey"]:
        buttons.append({"type": 2, "style": 1, "label": "Reply", "emoji": {"name": "📨"},
                        "custom_id": f"{AHELP_REPLY}{event['run']}:{event['ckey']}"})
    if kind != "admin" and event["ticket"] is not None:
        buttons.append({"type": 2, "style": 4, "label": "Close ticket", "emoji": {"name": "🔒"},
                        "custom_id": f"{AHELP_CLOSE}{event['run']}:{event['ticket']}"})
    return embed, ([{"type": 1, "components": buttons}] if buttons else [])


def chunk_lines(lines, limit=1900):
    """Group log lines into code blocks below Discord's message size."""
    blocks, current = [], ""
    for line in lines:
        line = clip(line, limit - 10).replace("```", "'''")
        if len(current) + len(line) + 1 > limit:
            blocks.append(current)
            current = ""
        current += line + "\n"
    if current:
        blocks.append(current)
    return ["```\n" + block + "```" for block in blocks]


class BabylonBot(discord.Client):
    def __init__(self, settings, supervisor, presences=False):
        self.settings = settings
        self.features = set(settings["features"])
        self.supervisor = supervisor
        intents = discord.Intents.none()
        intents.guilds = True
        intents.voice_states = bool(self.features & {"voice", "logs"})
        # Privileged: enable "Server Members Intent" in the developer portal.
        intents.members = bool(self.features & {"link", "logs", "ahelp"})
        # Privileged: "Presence Intent", to count online admins for the in-game ahelp notice.
        intents.presences = presences
        if "logs" in self.features:
            # Privileged: "Message Content Intent", for the content of edited/deleted messages.
            intents.guild_messages = True
            intents.message_content = True
            intents.moderation = True
        super().__init__(intents=intents, allowed_mentions=discord.AllowedMentions.none())
        self.guild_object = discord.Object(id=settings["guild_id"])
        self.tree = app_commands.CommandTree(self)
        self.game_lines = deque(maxlen=500)
        self.voice_file = Path(settings["data_directory"]) / "discord-voice-rooms.json"
        self.voice_rooms = self.load_voice_rooms()
        self.voice_lock = asyncio.Lock()
        self.status_message = None
        # (run id, ticket number or ckey) -> thread id of that adminhelp in the ahelp channel, and
        # (run id, ckey) -> the player's latest thread, where replies from the Reply button go.
        self.ahelp_threads = {}
        self.ahelp_player_threads = {}
        # One lock per ticket: two events of a new ticket must not both create a thread.
        self.ahelp_locks = {}
        self.ticket_file = Path(settings["data_directory"]) / "discord-tickets.json"
        self.tickets = self.load_tickets()
        self.ticket_lock = asyncio.Lock()
        self.add_commands()

    # --- plumbing --------------------------------------------------------------

    def channel(self, key):
        channel_id = self.settings["channels"].get(key)
        return self.get_channel(channel_id) if channel_id else None

    async def send(self, key, **message):
        channel = self.channel(key)
        if channel:
            try:
                await channel.send(**message)
            except discord.HTTPException as error:
                log(f"Could not post to the {key} channel: {error}")

    @property
    def guild(self):
        return self.get_guild(self.settings["guild_id"])

    async def setup_hook(self):
        self.loop_ref = asyncio.get_running_loop()
        try:
            synced = await self.tree.sync(guild=self.guild_object)
            log(f"Registered {len(synced)} slash commands")
        except discord.HTTPException as error:
            log(f"Registering slash commands failed: {error}")
        if "gamelog" in self.features:
            subscribe(self.capture_game_line)
            self.loop_ref.create_task(self.game_log_loop())
        if "link" in self.features:
            self.supervisor.discord_link_changed = self.link_changed_threadsafe
        if "ahelp" in self.features:
            self.supervisor.ahelp_relay = self.ahelp_threadsafe
            self.supervisor.ahelp_admins_online = self.admins_online_threadsafe
            self.supervisor.discord_membership = self.is_member

    async def on_ready(self):
        guild = self.guild
        if not guild:
            log(f"The bot is not on the configured guild {self.settings['guild_id']}; invite it first")
            return
        log(f"Connected as {self.user} to {guild.name} (features: {', '.join(sorted(self.features)) or 'none'})")
        if "status" in self.features and not getattr(self, "status_task", None):
            self.status_task = self.loop_ref.create_task(self.status_loop())
        # Each step runs on its own, so one failing step cannot keep the others from running.
        steps = [("announce", self.send("bot_log", embed=discord.Embed(
            color=TEAL, description=f"🟢 Bot started. Features: {', '.join(sorted(self.features))}")))]
        if "voice" in self.features:
            steps.append(("voice rooms", self.cleanup_voice_rooms()))
        if "tickets" in self.features:
            steps.append(("ticket panel", self.ensure_ticket_panel()))
        for name, step in steps:
            try:
                await step
            except Exception as error:
                log(f"Startup step {name} failed: {error!r}")
                await self.on_error(f"on_ready ({name})")

    async def on_error(self, event, *args, **kwargs):
        import traceback
        trace = traceback.format_exc()
        log(f"Error in {event}: {trace}")
        await self.send("bot_log", embed=discord.Embed(color=RED, title=f"Error in {event}",
                                                       description=f"```\n{clip(trace, 3900)}\n```"))

    def is_member(self, discord_id):
        """Membership from the cache only; None while the cache is not ready."""
        guild = self.guild
        if not guild or not self.is_ready() or not guild.chunked:
            return None
        return guild.get_member(int(discord_id)) is not None

    async def shutdown(self):
        if "status" in self.features:
            await self.update_status(online=False)
        await self.send("bot_log", embed=discord.Embed(color=GREY, description="⚪ Bot stopping."))
        await self.close()

    # --- commands --------------------------------------------------------------

    def add_commands(self):
        guild = self.guild_object

        if "link" in self.features:
            @self.tree.command(name="link", description="Link your Discord account to your BYOND account", guild=guild)
            @app_commands.describe(code="The code shown by Link Discord in the Babylon13 lobby")
            async def link(interaction: discord.Interaction, code: str):
                try:
                    account = await asyncio.to_thread(self.supervisor.redeem_discord_code, code,
                                                      interaction.user.id, interaction.user.name)
                except ValueError as error:
                    await interaction.response.send_message(f"❌ {error}", ephemeral=True)
                    return
                await interaction.response.send_message(
                    f"✅ Linked to the BYOND account **{account}**. Reopen the lobby window to see it.", ephemeral=True)
                await self.send("member_log", embed=discord.Embed(
                    color=TEAL, description=f"🔗 {interaction.user.mention} linked the BYOND account **{account}**"))

            @self.tree.command(name="unlink", description="Unlink your Discord account from your BYOND account", guild=guild)
            async def unlink(interaction: discord.Interaction):
                removed = await asyncio.to_thread(self.supervisor.unlink_discord, None, interaction.user.id)
                if not removed:
                    await interaction.response.send_message("Your Discord account is not linked.", ephemeral=True)
                    return
                await interaction.response.send_message(f"Unlinked from the BYOND account **{removed['ckey']}**.", ephemeral=True)
                await self.send("member_log", embed=discord.Embed(
                    color=GREY, description=f"⛓️‍💥 {interaction.user.mention} unlinked the BYOND account **{removed['ckey']}**"))

            @self.tree.command(name="whois", description="Show the BYOND account linked to a member", guild=guild)
            @app_commands.default_permissions(moderate_members=True)
            async def whois(interaction: discord.Interaction, member: discord.Member):
                link = await asyncio.to_thread(self.supervisor.discord_link_by_id, member.id)
                text = f"{member.mention} is linked to **{link['ckey']}** since <t:{int(link['linked'])}:D>." if link \
                    else f"{member.mention} has no linked BYOND account."
                await interaction.response.send_message(text, ephemeral=True)

        @self.tree.command(name="status", description="Show the Babylon13 server status", guild=guild)
        async def status(interaction: discord.Interaction):
            snapshot = await asyncio.to_thread(self.supervisor.status_snapshot)
            await interaction.response.send_message(embed=status_embed(snapshot, self.settings), ephemeral=True)

    # --- role buttons ----------------------------------------------------------

    async def on_interaction(self, interaction: discord.Interaction):
        if interaction.type != discord.InteractionType.component:
            return
        custom_id = (interaction.data or {}).get("custom_id", "")
        if "ahelp" in self.features and custom_id.startswith((AHELP_REPLY, AHELP_CLOSE)):
            await self.ahelp_button(interaction, custom_id)
            return
        if "tickets" in self.features and custom_id in (TICKET_OPEN, TICKET_ADD, TICKET_CLOSE):
            await self.ticket_button(interaction, custom_id)
            return
        if "voice" in self.features and custom_id in VOICE_BUTTONS:
            await self.voice_button(interaction, custom_id)
            return
        if "roles" in self.features and custom_id.startswith(COLOR_BUTTON):
            await self.color_button(interaction, custom_id[len(COLOR_BUTTON):])
            return
        if "roles" not in self.features or not custom_id.startswith(ROLE_BUTTON):
            return
        try:
            role_id = int(custom_id[len(ROLE_BUTTON):])
        except ValueError:
            return
        member = interaction.user
        role = interaction.guild.get_role(role_id) if interaction.guild else None
        if role_id not in self.settings["self_roles"] or not role or not isinstance(member, discord.Member):
            await interaction.response.send_message("This role can't be picked here.", ephemeral=True)
            return
        try:
            if role in member.roles:
                await member.remove_roles(role, reason="Role button")
                text = f"Removed **{role.name}**."
            else:
                await member.add_roles(role, reason="Role button")
                text = f"You now have **{role.name}**."
        except discord.Forbidden:
            text = "I'm not allowed to manage that role. Please tell the staff."
        await interaction.response.send_message(text, ephemeral=True)

    async def color_button(self, interaction, value):
        """Name colours are exclusive: picking one removes the others; "none" removes all."""
        member = interaction.user
        if not isinstance(member, discord.Member):
            return
        colors = [role for role in (member.guild.get_role(r) for r in self.settings["color_roles"]) if role]
        chosen = None
        if value != "none":
            chosen = next((role for role in colors if str(role.id) == value), None)
            if not chosen:
                await interaction.response.send_message("This colour can't be picked here.", ephemeral=True)
                return
        try:
            remove = [role for role in colors if role in member.roles and role != chosen]
            if remove:
                await member.remove_roles(*remove, reason="Name colour button")
            if chosen and chosen not in member.roles:
                await member.add_roles(chosen, reason="Name colour button")
        except discord.Forbidden:
            await interaction.response.send_message("I'm not allowed to manage that role. Please tell the staff.", ephemeral=True)
            return
        await interaction.response.send_message(f"Your name colour is now **{chosen.name}**." if chosen
                                                else "Your name colour was removed.", ephemeral=True)

    # --- linked role -----------------------------------------------------------

    def link_changed_threadsafe(self, account, discord_id, linked):
        asyncio.run_coroutine_threadsafe(self.apply_linked_role(int(discord_id), linked), self.loop_ref)

    async def apply_linked_role(self, discord_id, linked):
        role_id = self.settings.get("linked_role")
        guild = self.guild
        if not role_id or not guild or not guild.get_role(role_id):
            return
        member = guild.get_member(discord_id)
        if not member:
            return
        try:
            if linked:
                await member.add_roles(guild.get_role(role_id), reason="BYOND account linked")
            else:
                await member.remove_roles(guild.get_role(role_id), reason="BYOND account unlinked")
        except discord.HTTPException as error:
            log(f"Updating the linked role failed: {error}")

    # --- join-to-create voice --------------------------------------------------
    # Each room is {"owner": member id, "joined": {member id: time}, "banned": [ids]}.
    # The bot enforces ownership; owners get no Discord permissions, so a room can
    # be handed over by changing one field.

    def load_voice_rooms(self):
        try:
            rooms = json.loads(self.voice_file.read_text())
        except (OSError, ValueError):
            return {}
        result = {}
        for channel_id, room in rooms.items():
            if isinstance(room, int):  # older format: just the owner
                room = {"owner": room}
            result[int(channel_id)] = {"owner": int(room["owner"]),
                                       "joined": {int(k): v for k, v in room.get("joined", {}).items()},
                                       "banned": [int(b) for b in room.get("banned", [])]}
        return result

    def save_voice_rooms(self):
        try:
            self.voice_file.write_text(json.dumps({str(k): {"owner": v["owner"], "banned": v["banned"],
                                                            "joined": {str(m): t for m, t in v["joined"].items()}}
                                                   for k, v in self.voice_rooms.items()}))
        except OSError as error:
            log(f"Saving voice rooms failed: {error}")

    async def cleanup_voice_rooms(self):
        """Delete empty rooms left over from before a restart; resync the others."""
        async with self.voice_lock:
            for channel_id, room in list(self.voice_rooms.items()):
                channel = self.get_channel(channel_id)
                if not channel:
                    self.voice_rooms.pop(channel_id)
                elif not channel.members:
                    await self.delete_room(channel)
                else:
                    now = time.time()
                    present = {m.id for m in channel.members}
                    room["joined"] = {m: room["joined"].get(m, now) for m in present}
                    if room["owner"] not in present:
                        await self.transfer_room(channel, room)
            self.save_voice_rooms()

    async def delete_room(self, channel):
        self.voice_rooms.pop(channel.id, None)
        try:
            await channel.delete(reason="Voice room empty")
        except discord.NotFound:
            pass
        except discord.HTTPException as error:
            log(f"Deleting voice room {channel.name} failed: {error}")

    async def transfer_room(self, channel, room, new_owner=None):
        """Give the room to new_owner, or to whoever has been in it the longest."""
        if new_owner is None:
            present = [m for m in channel.members if not m.bot]
            if not present:
                return
            new_owner = min(present, key=lambda m: room["joined"].get(m.id, time.time()))
        room["owner"] = new_owner.id
        try:
            await channel.send(f"👑 {new_owner.mention} now owns this room and can use the controls above.",
                               allowed_mentions=discord.AllowedMentions(users=True))
        except discord.HTTPException:
            pass

    async def post_voice_controls(self, channel, owner):
        embed = discord.Embed(title="Room controls", color=TEAL, description=(
            f"👑 Owner: {owner.mention}\n"
            "Only the owner (and the staff) can use these buttons. When the owner leaves, the member who has been "
            "here the longest becomes the owner. The room is deleted when it is empty."))
        rows = [{"type": 1, "components": [
            {"type": 2, "style": 2, "label": "Kick", "custom_id": VOICE_KICK, "emoji": {"name": "👢"}},
            {"type": 2, "style": 4, "label": "Ban", "custom_id": VOICE_BAN, "emoji": {"name": "🔨"}},
            {"type": 2, "style": 2, "label": "Unban", "custom_id": VOICE_UNBAN, "emoji": {"name": "🕊️"}}]},
            {"type": 1, "components": [
            {"type": 2, "style": 2, "label": "Set limit", "custom_id": VOICE_LIMIT, "emoji": {"name": "🔢"}},
            {"type": 2, "style": 2, "label": "Remove limit", "custom_id": VOICE_UNLIMIT, "emoji": {"name": "♾️"}},
            {"type": 2, "style": 2, "label": "Rename", "custom_id": VOICE_RENAME, "emoji": {"name": "✏️"}},
            {"type": 2, "style": 2, "label": "Hand over", "custom_id": VOICE_TRANSFER, "emoji": {"name": "👑"}}]}]
        try:
            await self.post_components(channel, embed, rows)
        except discord.HTTPException as error:
            log(f"Posting voice room controls failed: {error}")

    async def handle_voice_rooms(self, member, before, after):
        lobby = self.settings["channels"].get("voice_lobby")
        async with self.voice_lock:
            if after.channel and after.channel.id == lobby:
                room_id = next((c for c, room in self.voice_rooms.items() if room["owner"] == member.id), None)
                room = self.get_channel(room_id) if room_id else None
                if not room:
                    lobby_channel = after.channel
                    name = self.settings["voice_room_name"].replace("{name}", member.display_name)[:100]
                    room = await member.guild.create_voice_channel(
                        name, category=lobby_channel.category, overwrites=dict(lobby_channel.overwrites),
                        bitrate=lobby_channel.bitrate, position=lobby_channel.position + 1,
                        reason=f"Voice room for {member}")
                    self.voice_rooms[room.id] = {"owner": member.id, "joined": {}, "banned": []}
                    await self.post_voice_controls(room, member)
                try:
                    await member.move_to(room, reason="Join-to-create voice room")
                except discord.HTTPException:
                    if not room.members:
                        await self.delete_room(room)
            if after.channel and after.channel.id in self.voice_rooms and before.channel != after.channel:
                self.voice_rooms[after.channel.id]["joined"].setdefault(member.id, time.time())
            if before.channel and before.channel.id in self.voice_rooms and before.channel != after.channel:
                room = self.voice_rooms[before.channel.id]
                room["joined"].pop(member.id, None)
                if not [m for m in before.channel.members if not m.bot]:
                    await self.delete_room(before.channel)
                elif room["owner"] == member.id:
                    await self.transfer_room(before.channel, room)
            self.save_voice_rooms()

    async def voice_button(self, interaction, custom_id):
        channel = interaction.channel
        room = self.voice_rooms.get(interaction.channel_id)
        if not room or not isinstance(channel, discord.VoiceChannel):
            await interaction.response.send_message("This room is not managed by me any more.", ephemeral=True)
            return
        if interaction.user.id != room["owner"] and not self.is_staff(interaction.user):
            await interaction.response.send_message(f"Only the room's owner (<@{room['owner']}>) can do that.", ephemeral=True)
            return
        if custom_id in (VOICE_LIMIT, VOICE_RENAME):
            await interaction.response.send_modal(VoiceModal(self, channel, custom_id == VOICE_LIMIT))
        elif custom_id == VOICE_UNLIMIT:
            await channel.edit(user_limit=0, reason=f"Room limit removed by {interaction.user}")
            await interaction.response.send_message("♾️ The room has no member limit any more.")
        else:
            prompts = {VOICE_KICK: "Who should be kicked from the room?", VOICE_BAN: "Who should be banned from the room?",
                       VOICE_UNBAN: "Who should be unbanned?", VOICE_TRANSFER: "Who should own the room?"}
            await interaction.response.send_message(prompts[custom_id], ephemeral=True,
                                                    view=VoiceMemberView(self, channel.id, custom_id))

    async def voice_members(self, interaction, channel_id, action, users):
        channel = self.get_channel(channel_id)
        room = self.voice_rooms.get(channel_id)
        if not channel or not room:
            await interaction.response.edit_message(content="This room is gone.", view=None)
            return
        if interaction.user.id != room["owner"] and not self.is_staff(interaction.user):
            await interaction.response.edit_message(content="You no longer own this room.", view=None)
            return
        done = []
        for user in users:
            member = channel.guild.get_member(user.id)
            if not member or member.id == interaction.user.id or member.bot:
                continue
            if action == VOICE_TRANSFER:
                if member in channel.members:
                    await self.transfer_room(channel, room, member)
                    done.append(member.mention)
                break
            if action in (VOICE_KICK, VOICE_BAN) and self.is_staff(member) and not self.is_staff(interaction.user):
                continue
            if action == VOICE_BAN:
                await channel.set_permissions(member, connect=False, reason=f"Banned from the room by {interaction.user}")
                if member.id not in room["banned"]:
                    room["banned"].append(member.id)
            elif action == VOICE_UNBAN:
                await channel.set_permissions(member, overwrite=None, reason=f"Unbanned from the room by {interaction.user}")
                room["banned"] = [b for b in room["banned"] if b != member.id]
            if action in (VOICE_KICK, VOICE_BAN) and member in channel.members:
                await member.move_to(None, reason=f"Removed from the room by {interaction.user}")
            done.append(member.mention)
        self.save_voice_rooms()
        verb = {VOICE_KICK: "Kicked", VOICE_BAN: "Banned", VOICE_UNBAN: "Unbanned", VOICE_TRANSFER: "New owner"}[action]
        await interaction.response.edit_message(content=f"{verb}: {', '.join(done) or 'nobody'}", view=None)
        if done and action != VOICE_TRANSFER:
            await channel.send(f"{verb} by {interaction.user.mention}: {', '.join(done)}")

    # --- logs ------------------------------------------------------------------

    async def on_voice_state_update(self, member, before, after):
        if member.guild.id != self.settings["guild_id"]:
            return
        if "voice" in self.features and self.settings["channels"].get("voice_lobby"):
            await self.handle_voice_rooms(member, before, after)
        if "logs" not in self.features or before.channel == after.channel:
            return
        if not before.channel:
            text, color = f"🔊 {member.mention} joined {after.channel.mention}", TEAL
        elif not after.channel:
            text, color = f"🔇 {member.mention} left {before.channel.mention}", GREY
        else:
            text, color = f"🔀 {member.mention} moved {before.channel.mention} → {after.channel.mention}", AMBER
        await self.send("voice_log", embed=discord.Embed(color=color, description=text))

    async def on_member_join(self, member):
        if member.guild.id != self.settings["guild_id"]:
            return
        if "link" in self.features:
            link = await asyncio.to_thread(self.supervisor.discord_link_by_id, member.id)
            if link:
                await self.apply_linked_role(member.id, True)
        if "logs" in self.features:
            embed = discord.Embed(color=TEAL, description=f"📥 {member.mention} joined ({member})")
            embed.add_field(name="Account created", value=discord.utils.format_dt(member.created_at, "R"))
            embed.set_footer(text=f"ID {member.id}")
            await self.send("member_log", embed=embed)

    async def on_member_remove(self, member):
        if member.guild.id != self.settings["guild_id"] or "logs" not in self.features:
            return
        roles = ", ".join(r.mention for r in member.roles if not r.is_default()) or "none"
        embed = discord.Embed(color=GREY, description=f"📤 {member.mention} left ({member})")
        embed.add_field(name="Roles", value=clip(roles, 1024))
        embed.set_footer(text=f"ID {member.id}")
        await self.send("member_log", embed=embed)

    async def on_member_update(self, before, after):
        if after.guild.id != self.settings["guild_id"] or "logs" not in self.features:
            return
        changes = []
        if before.nick != after.nick:
            changes.append(f"Nickname: `{before.nick or before.name}` → `{after.nick or after.name}`")
        added = [r.mention for r in after.roles if r not in before.roles]
        removed = [r.mention for r in before.roles if r not in after.roles]
        if added:
            changes.append("Roles added: " + ", ".join(added))
        if removed:
            changes.append("Roles removed: " + ", ".join(removed))
        if changes:
            await self.send("member_log", embed=discord.Embed(
                color=AMBER, description=f"✏️ {after.mention}\n" + "\n".join(changes)))

    def loggable(self, message):
        return (message.guild and message.guild.id == self.settings["guild_id"] and not message.author.bot
                and message.channel.id not in self.settings["channels"].values())

    async def on_message_delete(self, message):
        if "logs" not in self.features or not self.loggable(message):
            return
        embed = discord.Embed(color=RED, description=f"🗑️ Message by {message.author.mention} deleted in {message.channel.mention}")
        embed.add_field(name="Content", value=clip(message.content) or "*(no text)*", inline=False)
        if message.attachments:
            embed.add_field(name="Attachments", value=clip("\n".join(a.filename for a in message.attachments), 1024))
        embed.set_footer(text=f"Author ID {message.author.id}")
        await self.send("message_log", embed=embed)

    async def on_message_edit(self, before, after):
        if "logs" not in self.features or not self.loggable(after) or before.content == after.content:
            return
        embed = discord.Embed(color=AMBER, description=f"✏️ [Message]({after.jump_url}) by {after.author.mention} edited in {after.channel.mention}")
        embed.add_field(name="Before", value=clip(before.content) or "*(no text)*", inline=False)
        embed.add_field(name="After", value=clip(after.content) or "*(no text)*", inline=False)
        await self.send("message_log", embed=embed)

    async def on_audit_log_entry_create(self, entry):
        if "logs" not in self.features or entry.guild.id != self.settings["guild_id"]:
            return
        action = entry.action
        A = discord.AuditLogAction
        if action not in (A.kick, A.ban, A.unban, A.member_update):
            return
        moderator = f"<@{entry.user_id}>" if entry.user_id else "someone"
        target = audit_target(entry)
        reason = f"\nReason: {clip(entry.reason, 500)}" if entry.reason else ""
        if action == discord.AuditLogAction.kick:
            text, color = f"👢 {target} was kicked by {moderator}", AMBER
        elif action == discord.AuditLogAction.ban:
            text, color = f"🔨 {target} was banned by {moderator}", RED
        elif action == discord.AuditLogAction.unban:
            text, color = f"🕊️ {target} was unbanned by {moderator}", TEAL
        elif action == discord.AuditLogAction.member_update and hasattr(entry.after, "timed_out_until"):
            until = entry.after.timed_out_until
            if until:
                text, color = f"⏳ {target} was timed out until {discord.utils.format_dt(until)} by {moderator}", AMBER
            else:
                text, color = f"⌛ {target}'s timeout was removed by {moderator}", TEAL
        else:
            return
        await self.send("mod_log", embed=discord.Embed(color=color, description=text + reason))

    # --- tickets -----------------------------------------------------------------

    def load_tickets(self):
        try:
            data = json.loads(self.ticket_file.read_text())
            return {"next": int(data.get("next", 1)), "open": {int(k): v for k, v in data.get("open", {}).items()}}
        except (OSError, ValueError):
            return {"next": 1, "open": {}}

    def save_tickets(self):
        try:
            self.ticket_file.write_text(json.dumps({"next": self.tickets["next"],
                                                    "open": {str(k): v for k, v in self.tickets["open"].items()}}))
        except OSError as error:
            log(f"Saving tickets failed: {error}")

    def is_staff(self, member):
        if not isinstance(member, discord.Member):
            return False
        staff = set(self.settings["staff_roles"])
        return member.guild_permissions.administrator or any(role.id in staff for role in member.roles)

    async def ensure_ticket_panel(self):
        """Post the "Open a ticket" panel once; edit it on later starts."""
        channel = self.channel("ticket_panel")
        if not channel:
            return
        embed = discord.Embed(title="Support", color=TEAL, description=(
            "Need help with Babylon13, want to report a player or an exploit, or have a question for the staff?\n\n"
            "Press **Open a ticket** and describe your problem. You get a private channel that only you and the "
            "staff can see. When the ticket is closed, you receive a copy of the conversation by DM."))
        view = {"type": 1, "components": [{"type": 2, "style": 1, "label": "Open a ticket", "custom_id": TICKET_OPEN, "emoji": {"name": "🎫"}}]}
        try:
            async for message in channel.history(limit=20):
                if message.author.id == self.user.id:
                    await self.post_components(channel, embed, [view], message_id=message.id)
                    return
            await self.post_components(channel, embed, [view])
        except discord.HTTPException as error:
            log(f"Posting the ticket panel failed: {error}")

    async def post_components(self, channel, embed, rows, message_id=None):
        return await self.raw_message(channel.id, {"embeds": [embed.to_dict()], "components": rows}, message_id)

    async def raw_message(self, channel_id, payload, message_id=None):
        """Post (or edit) a message with raw component rows. discord.py's own http helpers take
        multipart parameters rather than keywords, so every raw message call goes through here."""
        if message_id is None:
            route = discord.http.Route("POST", "/channels/{channel_id}/messages", channel_id=channel_id)
        else:
            route = discord.http.Route("PATCH", "/channels/{channel_id}/messages/{message_id}",
                                       channel_id=channel_id, message_id=message_id)
        return await self.http.request(route, json=dict(payload, allowed_mentions={"parse": []}))

    # --- adminhelp relay -----------------------------------------------------------

    def ahelp_threadsafe(self, event):
        asyncio.run_coroutine_threadsafe(self.post_ahelp(event), self.loop_ref)

    def admins_online_threadsafe(self):
        return asyncio.run_coroutine_threadsafe(self.count_online_admins(), self.loop_ref).result(timeout=3)

    async def count_online_admins(self):
        """Members of the ahelp roles who are not offline; None without presence data."""
        guild = self.guild
        roles = set(self.settings.get("ahelp_roles") or [])
        if not guild or not roles or not self.intents.presences:
            return None
        return sum(1 for member in guild.members if not member.bot and member.status != discord.Status.offline
                   and any(role.id in roles for role in member.roles))

    async def post_ahelp(self, event):
        """One message with a thread per ticket; later events of that ticket go into the thread."""
        channel = self.channel("ahelp")
        if not channel:
            return
        embed, rows = ahelp_entry(event)
        payload = {"embeds": [embed.to_dict()], "components": rows}
        key = (event["run"], event["ticket"] if event["ticket"] is not None else event["ckey"])
        async with self.ahelp_locks.setdefault(key, asyncio.Lock()):
            try:
                thread_id = self.ahelp_threads.get(key)
                if not thread_id:
                    message = await self.raw_message(channel.id, payload)
                    route = discord.http.Route("POST", "/channels/{channel_id}/messages/{message_id}/threads",
                                               channel_id=channel.id, message_id=message["id"])
                    number = f"#{event['ticket']}" if event["ticket"] is not None else "PM"
                    thread = await self.http.request(route, json={"name": clip(f"Ahelp {number} {event['ckey']} - {event['world']}", 100),
                                                                  "auto_archive_duration": 1440})
                    thread_id = self.ahelp_threads[key] = int(thread["id"])
                else:
                    await self.raw_message(thread_id, payload)
                if event["ckey"]:
                    self.ahelp_player_threads[(event["run"], event["ckey"])] = thread_id
            except discord.HTTPException as error:
                log(f"Posting an adminhelp failed: {error}")

    async def ahelp_log(self, interaction, thread_id, description):
        """Records a staff action in the ticket's thread, wherever the button was clicked."""
        embed = discord.Embed(color=TEAL, description=description)
        try:
            if thread_id:
                await self.raw_message(thread_id, {"embeds": [embed.to_dict()]})
            elif interaction.channel:
                await interaction.channel.send(embed=embed, allowed_mentions=discord.AllowedMentions.none())
        except discord.HTTPException as error:
            log(f"Logging an adminhelp action failed: {error}")

    async def ahelp_button(self, interaction, custom_id):
        if not self.is_staff(interaction.user):
            await interaction.response.send_message("Only staff can answer adminhelps.", ephemeral=True)
            return
        if custom_id.startswith(AHELP_REPLY):
            run_id, _, player = custom_id[len(AHELP_REPLY):].partition(":")
            await interaction.response.send_modal(AhelpReplyModal(self, run_id, player))
            return
        run_id, _, ticket = custom_id[len(AHELP_CLOSE):].partition(":")
        await self.close_ahelp(interaction, run_id, ticket)

    async def ahelp_call(self, interaction, call, *args):
        """Runs a supervisor call for a button; tells the clicker what failed and returns False."""
        try:
            await asyncio.to_thread(call, *args)
            return True
        except ValueError as error:
            await interaction.followup.send(f"Not done: {error}", ephemeral=True)
        except OSError:
            await interaction.followup.send("Not done: the world did not answer.", ephemeral=True)
        return False

    async def send_ahelp_reply(self, interaction, run_id, player, text):
        await interaction.response.defer(ephemeral=True, thinking=True)
        sender = interaction.user.display_name
        if not await self.ahelp_call(interaction, self.supervisor.ahelp_reply, run_id, player, sender, text):
            return
        await interaction.followup.send("Delivered.", ephemeral=True)
        await self.ahelp_log(interaction, self.ahelp_player_threads.get((run_id, player)),
                             f"📨 **{md(sender)}** → **{md(player)}**: {clip(md(text), 3500)}")

    async def close_ahelp(self, interaction, run_id, ticket):
        await interaction.response.defer(ephemeral=True, thinking=True)
        if not ticket.isdigit():
            await interaction.followup.send("Not done: unknown ticket.", ephemeral=True)
            return
        sender = interaction.user.display_name
        if not await self.ahelp_call(interaction, self.supervisor.ahelp_close, run_id, int(ticket), sender):
            return
        await interaction.followup.send("Ticket closed.", ephemeral=True)
        thread_id = self.ahelp_threads.get((run_id, int(ticket)))
        await self.ahelp_log(interaction, thread_id, f"🔒 Ticket #{ticket} closed by **{md(sender)}**.")
        if thread_id:
            try:
                await self.http.request(discord.http.Route("PATCH", "/channels/{channel_id}", channel_id=thread_id),
                                        json={"archived": True})
            except discord.HTTPException as error:
                log(f"Archiving an adminhelp thread failed: {error}")

    def ticket_of(self, member_id):
        return next((cid for cid, t in self.tickets["open"].items() if t["owner"] == member_id), None)

    async def ticket_button(self, interaction, custom_id):
        if custom_id == TICKET_OPEN:
            existing = self.ticket_of(interaction.user.id)
            if existing and self.get_channel(existing):
                await interaction.response.send_message(f"You already have an open ticket: <#{existing}>", ephemeral=True)
                return
            await interaction.response.send_modal(TicketModal(self))
            return
        ticket = self.tickets["open"].get(interaction.channel_id)
        if not ticket:
            await interaction.response.send_message("This is not an open ticket.", ephemeral=True)
            return
        if interaction.user.id != ticket["owner"] and not self.is_staff(interaction.user):
            await interaction.response.send_message("Only the ticket's creator and the staff can do that.", ephemeral=True)
            return
        if custom_id == TICKET_ADD:
            await interaction.response.send_message("Who should be added to this ticket?",
                                                    view=AddMembersView(self, interaction.channel_id), ephemeral=True)
        else:
            await interaction.response.send_message("🔒 Closing the ticket and sending the transcript…")
            await self.close_ticket(interaction.channel, interaction.user)

    async def open_ticket(self, interaction, topic):
        guild = interaction.guild
        member = interaction.user
        category = guild.get_channel(self.settings["ticket_category"]) if guild else None
        if not category:
            await interaction.response.send_message("Tickets are not set up correctly. Please tell the staff.", ephemeral=True)
            log("The ticket category is missing")
            return
        await interaction.response.defer(ephemeral=True, thinking=True)
        async with self.ticket_lock:
            existing = self.ticket_of(member.id)
            if existing and self.get_channel(existing):
                await interaction.followup.send(f"You already have an open ticket: <#{existing}>", ephemeral=True)
                return
            number = self.tickets["next"]
            self.tickets["next"] += 1
            access = discord.PermissionOverwrite(view_channel=True, send_messages=True, read_message_history=True,
                                                 attach_files=True, embed_links=True)
            overwrites = {guild.default_role: discord.PermissionOverwrite(view_channel=False), member: access,
                          guild.me: discord.PermissionOverwrite(view_channel=True, send_messages=True,
                                                                manage_channels=True, manage_permissions=True)}
            for role_id in self.settings["staff_roles"]:
                role = guild.get_role(role_id)
                if role:
                    overwrites[role] = discord.PermissionOverwrite(view_channel=True, send_messages=True,
                                                                   read_message_history=True, attach_files=True,
                                                                   manage_messages=True)
            channel = await guild.create_text_channel(f"ticket-{number:04d}-{ticket_slug(member.name)}", category=category,
                                                      overwrites=overwrites, topic=clip(f"Ticket of {member}: {topic}", 1000),
                                                      reason=f"Ticket #{number} for {member}")
            self.tickets["open"][channel.id] = {"number": number, "owner": member.id, "owner_name": str(member),
                                                "opened": time.time(), "topic": topic}
            self.save_tickets()
        embed = discord.Embed(title=f"Ticket #{number:04d}", color=TEAL, description=clip(topic, 4000))
        embed.add_field(name="Opened by", value=member.mention)
        embed.set_footer(text="Add people with the button below. Closing the ticket sends a transcript to its creator.")
        rows = [{"type": 1, "components": [
            {"type": 2, "style": 2, "label": "Add someone", "custom_id": TICKET_ADD, "emoji": {"name": "➕"}},
            {"type": 2, "style": 4, "label": "Close ticket", "custom_id": TICKET_CLOSE, "emoji": {"name": "🔒"}}]}]
        await self.post_components(channel, embed, rows)
        staff = " ".join(f"<@&{r}>" for r in self.settings["staff_roles"])
        if staff:
            await channel.send(f"{member.mention} {staff}", allowed_mentions=discord.AllowedMentions(users=True, roles=True))
        await interaction.followup.send(f"Your ticket is open: {channel.mention}", ephemeral=True)
        await self.send("ticket_log", embed=discord.Embed(color=TEAL, description=f"🎫 Ticket #{number:04d} opened by {member.mention}: {channel.mention}"))

    async def add_to_ticket(self, interaction, channel_id, users):
        channel = self.get_channel(channel_id)
        if not channel or channel_id not in self.tickets["open"]:
            await interaction.response.send_message("This ticket is closed.", ephemeral=True)
            return
        added = []
        for user in users:
            member = channel.guild.get_member(user.id) if not isinstance(user, discord.Member) else user
            if not member or member.bot:
                continue
            await channel.set_permissions(member, view_channel=True, send_messages=True, read_message_history=True,
                                          attach_files=True, embed_links=True, reason=f"Added to the ticket by {interaction.user}")
            added.append(member.mention)
        await interaction.response.edit_message(content="Added: " + (", ".join(added) or "nobody"), view=None)
        if added:
            await channel.send(f"➕ {interaction.user.mention} added {', '.join(added)} to this ticket.",
                               allowed_mentions=discord.AllowedMentions(users=True))

    async def close_ticket(self, channel, closer):
        async with self.ticket_lock:
            ticket = self.tickets["open"].pop(channel.id, None)
            self.save_tickets()
        if not ticket:
            return
        messages = [message async for message in channel.history(limit=None, oldest_first=True)]
        text = transcript_text(ticket, messages) + f"\nClosed by {closer} ({closer.id}) at " \
            f"{time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}\n"
        filename = f"ticket-{ticket['number']:04d}.txt"
        owner = self.get_user(ticket["owner"]) or await self.fetch_user(ticket["owner"])
        delivered = "sent to the creator"
        try:
            await owner.send(f"Your Babylon13 ticket #{ticket['number']:04d} was closed. Here is a copy of the conversation.",
                             file=discord.File(io.BytesIO(text.encode()), filename=filename))
        except discord.HTTPException:
            delivered = "could not be sent to the creator (DMs closed)"
        log_channel = self.channel("ticket_log")
        if log_channel:
            embed = discord.Embed(color=GREY, description=(
                f"🔒 Ticket #{ticket['number']:04d} of <@{ticket['owner']}> closed by {closer.mention}. "
                f"{len(messages)} messages; transcript {delivered}."))
            await log_channel.send(embed=embed, file=discord.File(io.BytesIO(text.encode()), filename=filename))
        try:
            await channel.delete(reason=f"Ticket #{ticket['number']} closed by {closer}")
        except discord.HTTPException as error:
            log(f"Deleting ticket channel failed: {error}")

    # --- status and game log ---------------------------------------------------

    async def update_status(self, online=True):
        channel = self.channel("status")
        if not channel:
            return
        snapshot = await asyncio.to_thread(self.supervisor.status_snapshot) if online else None
        embed = status_embed(snapshot, self.settings, online)
        try:
            if not self.status_message:
                async for message in channel.history(limit=20):
                    if message.author.id == self.user.id:
                        self.status_message = message
                        break
            if self.status_message:
                await self.status_message.edit(content=None, embed=embed)
            else:
                self.status_message = await channel.send(embed=embed)
        except discord.NotFound:
            self.status_message = None
        except discord.HTTPException as error:
            log(f"Updating the status message failed: {error}")

    async def repeat(self, name, step, interval):
        """Run step every interval seconds until the bot closes. A failing run is logged and the
        loop continues; an uncaught error would otherwise end the task without a trace."""
        while not self.is_closed():
            try:
                await step()
            except asyncio.CancelledError:
                raise
            except Exception as error:
                log(f"The {name} loop failed: {error!r}")
            await asyncio.sleep(interval)

    async def status_loop(self):
        await self.repeat("status", self.update_status, 60)

    def capture_game_line(self, source, line):
        if source == "supervisor" and line.strip():
            self.game_lines.append(time.strftime("%H:%M:%S ") + line)

    async def flush_game_log(self):
        lines = []
        while self.game_lines:
            lines.append(self.game_lines.popleft())
        for block in chunk_lines(lines):
            await self.send("game_log", content=block)

    async def game_log_loop(self):
        await self.repeat("game log", self.flush_game_log, 5)


class AhelpReplyModal(discord.ui.Modal, title="Answer the adminhelp"):
    reply = discord.ui.TextInput(label="Your answer (sent as an admin PM)", style=discord.TextStyle.paragraph, max_length=1000)

    def __init__(self, bot, run_id, player):
        super().__init__()
        self.bot, self.run_id, self.player = bot, run_id, player

    async def on_submit(self, interaction: discord.Interaction):
        await self.bot.send_ahelp_reply(interaction, self.run_id, self.player, str(self.reply))


class TicketModal(discord.ui.Modal, title="Open a support ticket"):
    topic = discord.ui.TextInput(label="What do you need help with?", style=discord.TextStyle.paragraph,
                                 max_length=1000, placeholder="Describe the problem, your BYOND key and what you tried.")

    def __init__(self, bot):
        super().__init__()
        self.bot = bot

    async def on_submit(self, interaction: discord.Interaction):
        await self.bot.open_ticket(interaction, str(self.topic))


class AddMembersView(discord.ui.View):
    def __init__(self, bot, channel_id):
        super().__init__(timeout=180)
        self.bot = bot
        self.channel_id = channel_id

    @discord.ui.select(cls=discord.ui.UserSelect, placeholder="Pick the members to add", min_values=1, max_values=5)
    async def pick(self, interaction: discord.Interaction, select: discord.ui.UserSelect):
        await self.bot.add_to_ticket(interaction, self.channel_id, select.values)


class VoiceMemberView(discord.ui.View):
    def __init__(self, bot, channel_id, action):
        super().__init__(timeout=180)
        self.bot = bot
        self.channel_id = channel_id
        self.action = action
        if action == VOICE_TRANSFER:
            self.pick.max_values = 1

    @discord.ui.select(cls=discord.ui.UserSelect, placeholder="Pick members", min_values=1, max_values=10)
    async def pick(self, interaction: discord.Interaction, select: discord.ui.UserSelect):
        await self.bot.voice_members(interaction, self.channel_id, self.action, select.values)


class VoiceModal(discord.ui.Modal):
    def __init__(self, bot, channel, limit):
        super().__init__(title="Member limit" if limit else "Rename the room")
        self.bot = bot
        self.channel = channel
        self.limit = limit
        self.value = discord.ui.TextInput(label="Maximum members (1-99)" if limit else "New name",
                                          max_length=2 if limit else 90,
                                          default=str(channel.user_limit or len(channel.members) or 2) if limit else channel.name)
        self.add_item(self.value)

    async def on_submit(self, interaction: discord.Interaction):
        if self.limit:
            try:
                limit = int(str(self.value))
                assert 1 <= limit <= 99
            except (ValueError, AssertionError):
                await interaction.response.send_message("Enter a number from 1 to 99.", ephemeral=True)
                return
            await self.channel.edit(user_limit=limit, reason=f"Room limit set by {interaction.user}")
            await interaction.response.send_message(f"🔢 The room is now limited to {limit} members.")
        else:
            name = str(self.value).strip()[:90] or self.channel.name
            await self.channel.edit(name=name, reason=f"Room renamed by {interaction.user}")
            await interaction.response.send_message(f"✏️ The room is now called **{name}**.")


def ticket_slug(name):
    slug = re.sub(r"[^a-z0-9-]+", "-", name.lower()).strip("-")
    return slug[:20] or "member"


def transcript_text(ticket, messages):
    lines = [f"Babylon13 ticket #{ticket['number']:04d}",
             f"Opened by {ticket.get('owner_name')} ({ticket['owner']}) at "
             f"{time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime(ticket['opened']))}",
             f"Topic: {ticket.get('topic', '')}", ""]
    for message in messages:
        stamp = message.created_at.strftime("%Y-%m-%d %H:%M:%S UTC")
        lines.append(f"[{stamp}] {message.author} ({message.author.id}): {message.content}")
        for embed in message.embeds:
            lines.append(f"    [embed] {embed.title or ''} {embed.description or ''}".rstrip())
        for attachment in message.attachments:
            lines.append(f"    [attachment] {attachment.filename} {attachment.url}")
    return "\n".join(lines) + "\n"


class BotHandle:
    """Runs the bot on its own thread and event loop; restarts it after crashes."""

    def __init__(self, settings, supervisor):
        self.settings = settings
        self.supervisor = supervisor
        self.client = None
        self.stopping = False
        # Asked for when ahelps are relayed; dropped if the portal does not allow it.
        self.presences = "ahelp" in settings["features"]
        self.thread = threading.Thread(target=self.run, daemon=True, name="discord-bot")

    def start(self):
        self.thread.start()
        return self

    def run(self):
        delay = 10
        while not self.stopping:
            self.client = BabylonBot(self.settings, self.supervisor, presences=self.presences)

            async def main(client=self.client):
                async with client:  # Closes the HTTP session on every exit path.
                    await client.start(self.settings["token"])
            try:
                asyncio.run(main())
                if self.stopping:
                    return
            except discord.PrivilegedIntentsRequired:
                if self.presences:
                    log("Discord rejected the Presence Intent; running without the online-admin count. "
                        "Enable 'Presence Intent' for the bot in the developer portal to show it in game.")
                    self.presences = False
                    continue
                log("Discord rejected the privileged intents. Enable 'Server Members Intent' and "
                    "'Message Content Intent' for the bot in the developer portal; the bot stays off.")
                return
            except discord.LoginFailure:
                log("Discord rejected the bot token; the bot stays off.")
                return
            except Exception as error:
                log(f"The bot crashed: {error!r}; restarting in {delay}s")
            time.sleep(delay)
            delay = min(delay * 2, 300)

    def stop(self, timeout=10):
        self.stopping = True
        client = self.client
        loop = getattr(client, "loop_ref", None) if client else None
        if loop and loop.is_running():
            try:
                asyncio.run_coroutine_threadsafe(client.shutdown(), loop).result(timeout)
            except Exception as error:
                log(f"Stopping the bot: {error!r}")
