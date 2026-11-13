"""Babylon supervisor: Python 3.11+, standard library only.

The HTTP API is for trusted BYOND servers, not browsers or player-supplied ckeys.
Run: python services/supervisor/supervisor.py --config <private-config.json>
"""
import argparse
import hashlib
import hmac
import html
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import sqlite3
import subprocess
import threading
import time
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

from protocol import topic
from checkpoints import Checkpoints, CheckpointError
from map_overlay import prepare_fresh_map
from world_storage import delete_world_data
from logstream import Follower, log, world_source


class Denied(ValueError):
    pass


# Link codes avoid look-alike characters (0/O, 1/I) because players type them.
LINK_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
LINK_CODE_SECONDS = 600


def plain_text(value):
    """Game chat text as plain text: tags removed and entities decoded (ahelp relays)."""
    return html.unescape(re.sub(r"<[^>]*>", "", value)).strip()


def clean_text(value, multiline=False):
    """Player-written text (world names, descriptions): no control or bidirectional-override
    characters, which could spoof how a name looks. HTML/Markdown is escaped where it is shown."""
    if multiline:
        value = re.sub(r"\r\n?", "\n", value)
    kept = []
    for char in value:
        if char == "\n" and multiline:
            kept.append(char)
        elif char in "\t\n\r":
            kept.append(" ")
        elif unicodedata.category(char) not in ("Cc", "Cf", "Cs", "Co", "Cn"):
            kept.append(char)
    return "".join(kept).strip()


def link_code_hash(code):
    return hashlib.sha256(re.sub(r"[^A-Z0-9]", "", str(code).upper()).encode()).hexdigest()


def ckey(value):
    return re.sub(r"[^a-z0-9]", "", str(value).lower())


def password_hash(password):
    if not password:
        return None
    salt = secrets.token_hex(16)
    digest = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1)
    return salt + ":" + digest.hex()


def password_matches(password, stored):
    if not stored:
        return False
    salt, digest = stored.split(":")
    actual = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1)
    return hmac.compare_digest(actual.hex(), digest)


class Driver:
    def __init__(self, config):
        self.config = config
        self.processes = {}

    def music_param(self):
        """The server's music folder for the worlds, only if it exists (it is optional)."""
        music = self.config.get("music_directory")
        if music and Path(music).is_dir():
            return {"babylon-music": str(Path(music).resolve())}
        return {}

    def prepare(self, world, run):
        template = Path(self.config["template_directory"]).resolve()
        root = Path(self.config["data_directory"]).resolve() / "worlds" / world["id"]
        root.mkdir(parents=True, exist_ok=True)
        # Separate mutable assets/config per world. Do not copy source saves, logs or credentials.
        for name in ("_maps", "strings", "icons", "sound", "html", "tgui/public", "build/behavior_trees",
                     "code", "modular_skyrat", "modular_zubbers", "modular_zzplurt"):
            source = template / name
            if source.exists():
                shutil.copytree(source, root / name, dirs_exist_ok=True,
                                ignore=shutil.ignore_patterns("active.dmm", "*.lk", "*.dm", "node_modules"))
        for name in ("babylon.dmb", "babylon.rsc", "rust_g.dll", "auxlua.dll", "dreamluau.dll",
                     "librust_g.so", "libauxlua.so", "libdreamluau.so"):
            if (template / name).exists():
                shutil.copy2(template / name, root / name)
        if not (root / "babylon.dmb").is_file():
            raise Denied("Compile babylon.dme before starting worlds")
        config_dir = root / "babylon-config"
        shutil.copytree(self.config["config_directory"], config_dir, dirs_exist_ok=True)
        # Each child has its own native control key; never use the lobby credential.
        (config_dir / "comms.txt").write_text("COMMS_KEY " + run["secret"] + "\n")
        saves = root / "data/babylon"
        saves.mkdir(parents=True, exist_ok=True)
        active = root / "_maps/babylon/active.dmm"
        active.parent.mkdir(parents=True, exist_ok=True)
        latest = saves / "saves/latest.json"
        resume = saves / "resume-state.json"
        if latest.exists():
            generation = json.loads(latest.read_text())["generation"]
            if not re.fullmatch(r"save-\d{8}-\d{6}-\d+", generation):
                raise Denied("Invalid checkpoint generation")
            checkpoint = latest.parent / generation
            json.loads((checkpoint / "state.json").read_text())
            shutil.copy2(checkpoint / "map.dmm", active)
            shutil.copy2(checkpoint / "state.json", resume)
        else:
            prepare_fresh_map(template, active)
            resume.unlink(missing_ok=True)
        return root

    def start(self, world, run):
        root = self.prepare(world, run)
        from urllib.parse import urlencode
        params = urlencode({"config-directory": str(root / "babylon-config"),
                            "babylon-owner": world["owner"], "babylon-world": world["id"], "babylon-name": world["name"],
                            "babylon-run": run["id"], "babylon-secret": run["secret"],
                            "babylon-api": f"http://127.0.0.1:{self.config['listen_port']}",
                            "babylon-lobby": self.config["lobby_address"],
                            "babylon-afk-timeout": self.config.get("afk_timeout_seconds", 900),
                            **self.music_param()})
        log = open(root / "daemon.log", "ab", buffering=0)
        try:
            process = subprocess.Popen([self.config["dreamdaemon"], "babylon.dmb", str(run["port"]),
                                        "-ip", self.config.get("bind_address", "127.0.0.1"),
                                        # Worlds only admit lobby tickets: never list them on the BYOND hub.
                                        "-trusted", "-close", "-invisible", "-params", params], cwd=root,
                                       stdout=log, stderr=log,
                                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        finally:
            log.close()
        self.processes[run["id"]] = process
        # Mirror the child's own log files into the container log, prefixed.
        Follower(world_source(world), root, lambda: process.poll() is None).start()
        return process.pid

    def alive(self, run):
        process = self.processes.get(run["id"])
        if process:
            return process.poll() is None
        pid = run["pid"]
        if not pid:
            return False
        if os.name == "nt":
            import ctypes
            from ctypes import wintypes
            kernel = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel.OpenProcess.restype = wintypes.HANDLE
            kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
            kernel.CloseHandle.argtypes = [wintypes.HANDLE]
            handle = kernel.OpenProcess(0x1000, False, pid)
            if not handle:
                return False
            try:
                code = wintypes.DWORD()
                return bool(kernel.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259
            finally:
                kernel.CloseHandle(handle)
        try:
            os.kill(pid, 0)
            # PIDs can be reused after a container restart. A live unrelated
            # process must not keep an old world stuck in the running table.
            command = Path(f"/proc/{pid}/cmdline").read_bytes().decode(errors="replace")
            return "babylon.dmb" in command and run["id"] in command and run["world"] in command
        except (ProcessLookupError, FileNotFoundError):
            return False

    def status(self, run):
        return topic(run["port"], run["secret"], "status")

    def stop(self, run):
        return topic(run["port"], run["secret"], "managed_stop", timeout=180)

    def ahelp_reply(self, run, payload):
        return topic(run["port"], run["secret"], "ahelp_reply", payload)

    def ahelp_close(self, run, payload):
        return topic(run["port"], run["secret"], "ahelp_close", payload)

    def announce(self, run, message):
        return topic(run["port"], run["secret"], "announce", {"message": message})


class Supervisor:
    def __init__(self, config, driver=None, clock=time.time):
        self.config = config
        self.clock = clock
        self.lock = threading.RLock()
        self.deletion_lock = threading.Lock()
        self.driver = driver or Driver(config)
        self.admins = {ckey(k) for k in config.get("admins", [])}
        Path(config["data_directory"]).mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(Path(config["data_directory"]) / "supervisor.sqlite3", check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS worlds (
              id TEXT PRIMARY KEY, owner TEXT NOT NULL, name TEXT NOT NULL,
              description TEXT NOT NULL, visibility TEXT NOT NULL, password TEXT,
              max_players INTEGER NOT NULL, created REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS members (world TEXT, ckey TEXT, role TEXT,
              PRIMARY KEY(world,ckey));
            CREATE TABLE IF NOT EXISTS runs (
              id TEXT PRIMARY KEY, world TEXT UNIQUE, port INTEGER UNIQUE, secret TEXT,
              pid INTEGER, state TEXT, started REAL, empty_since REAL, error TEXT,
              players TEXT DEFAULT '[]', last_save TEXT);
            CREATE TABLE IF NOT EXISTS tickets (
              hash TEXT PRIMARY KEY, ckey TEXT, world TEXT, run TEXT, expires REAL,
              password_hash TEXT, admin INTEGER);
            CREATE TABLE IF NOT EXISTS sessions (ckey TEXT PRIMARY KEY, world TEXT, run TEXT);
            CREATE TABLE IF NOT EXISTS audit (at REAL, actor TEXT, action TEXT, world TEXT);
            CREATE TABLE IF NOT EXISTS world_deletions (world TEXT PRIMARY KEY);
            CREATE TABLE IF NOT EXISTS discord_links (ckey TEXT PRIMARY KEY, discord_id TEXT UNIQUE NOT NULL,
              discord_name TEXT, linked REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS discord_codes (hash TEXT PRIMARY KEY, ckey TEXT NOT NULL, expires REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS world_bans (world TEXT NOT NULL, ckey TEXT NOT NULL, by TEXT NOT NULL,
              reason TEXT NOT NULL, at REAL NOT NULL, PRIMARY KEY(world, ckey));
        """)
        columns = {row[1] for row in self.db.execute("PRAGMA table_info(worlds)")}
        if "last_used" not in columns:
            self.db.execute("ALTER TABLE worlds ADD COLUMN last_used REAL")
        self.db.execute("UPDATE worlds SET last_used=max(created,coalesce((SELECT max(at) FROM audit WHERE world=worlds.id),created)) WHERE last_used IS NULL")
        self.db.commit()
        self.stop_workers = set()
        self.next_cleanup = 0
        # Set by the Discord bot: membership(discord_id) -> True/False/None (unknown),
        # from its member cache only, because it is called while holding the lock.
        self.discord_membership = None
        # Set by the Discord bot: called with (ckey, discord_id, linked) after a change.
        self.discord_link_changed = None
        # Called with each adminhelp event from a child world (the Discord bot relays them).
        self.ahelp_relay = None
        # Set while the container shuts down: no new worlds or joins, and a notice for the lobby.
        self.shutting_down = False
        self.server_notice = None
        # Returns how many admins are online on Discord (or None), for the player's ahelp notice.
        self.ahelp_admins_online = None
        self.checkpoints = Checkpoints(config["data_directory"], config.get("kept_save_points_per_world", 4))
        # Running children are reconciled by tick; stopped worlds have no writers.
        for row in self.db.execute("SELECT id FROM worlds WHERE id NOT IN (SELECT world FROM runs)"):
            self.maintain_checkpoints(row[0])

    def cleanup_unused_worlds(self):
        with self.lock, self.db:
            if self.clock() < self.next_cleanup:
                return
            self.next_cleanup = self.clock() + 3600
            days = self.config.get("delete_unused_worlds_after_days", 60)
            if days:
                expired = self.db.execute("SELECT id FROM worlds WHERE last_used<=? AND id NOT IN (SELECT world FROM runs)",
                                          (self.clock() - days * 86400,)).fetchall()
                for row in expired:
                    world = row[0]
                    self.queue_world_deletion(world, "supervisor", "expire_unused_world")
            pending = [row[0] for row in self.db.execute("SELECT world FROM world_deletions")]
        # Deleting runtime assets can take time. Do not hold the admission/database lock.
        for world in pending:
            self.finish_world_deletion(world)

    def queue_world_deletion(self, world, actor, action):
        # Called inside the admission lock/transaction: revoke access and commit
        # the retry journal before any filesystem operation can begin.
        self.db.execute("INSERT OR IGNORE INTO world_deletions VALUES(?)", (world,))
        for table in ("members", "tickets", "sessions", "world_bans"):
            self.db.execute(f"DELETE FROM {table} WHERE world=?", (world,))
        self.db.execute("DELETE FROM worlds WHERE id=?", (world,))
        self.audit(actor, action, world)
        self.checkpoints.maintained.pop(world, None)

    def finish_world_deletion(self, world):
        # Expiry and manual deletion may run concurrently. Serialize file
        # cleanup without holding the database/admission lock.
        with self.deletion_lock:
            try:
                delete_world_data(self.config["data_directory"], world)
            except (OSError, ValueError):
                log(f"World cleanup pending for {world}; will retry")
                return False
            with self.lock, self.db:
                self.db.execute("DELETE FROM world_deletions WHERE world=?", (world,))
        return True

    def delete_world(self, actor, data):
        with self.lock, self.db:
            world = self.world(data.get("world"))
            if self.role(actor, world) not in ("owner", "admin"):
                raise Denied("Only the owner or a server administrator can delete a world")
            if data.get("confirm_delete") not in (True, 1):
                raise Denied("Confirm permanent deletion of this world and all its checkpoints")
            if self.row("SELECT * FROM runs WHERE world=?", (world["id"],)):
                raise Denied("Stop the world before deleting it")
            self.queue_world_deletion(world["id"], actor, "delete_world")
        return {"ok": True, "cleanup_pending": not self.finish_world_deletion(world["id"])}

    def maintain_checkpoints(self, world, expected=None):
        try:
            self.checkpoints.retain(world, expected)
        except (CheckpointError, OSError, ValueError, KeyError):
            # A damaged history must not prevent unrelated worlds from running.
            log(f"Checkpoint maintenance failed for world {world}; history retained for inspection")

    def row(self, sql, args=()):
        result = self.db.execute(sql, args).fetchone()
        return dict(result) if result else None

    def world(self, world_id):
        world = self.row("SELECT * FROM worlds WHERE id=?", (world_id,))
        if not world:
            raise Denied("World does not exist or is unavailable")
        return world

    def role(self, actor, world):
        if actor in self.admins:
            return "admin"
        if actor == world["owner"]:
            return "owner"
        member = self.row("SELECT role FROM members WHERE world=? AND ckey=?", (world["id"], actor))
        return member["role"] if member else "guest"

    def banned(self, world_id, actor):
        """World bans are set by the world's owner and apply to that world only; admins are exempt."""
        return actor not in self.admins and bool(self.row("SELECT 1 FROM world_bans WHERE world=? AND ckey=?", (world_id, actor)))

    WORLD_OPS = ("list", "member_add", "member_remove", "ban", "unban")

    def manage_world(self, run_id, secret, data):
        """An owner (or admin) managing members and bans from inside their running world."""
        with self.lock, self.db:
            run = self.child(run_id, secret)
            world = self.world(run["world"])
            actor = ckey(str(data.get("actor", "")))
            if self.role(actor, world) not in ("owner", "admin"):
                raise Denied("Only the world's owner or a server administrator can manage its players")
            op = data.get("op")
            if op not in self.WORLD_OPS:
                raise Denied("Unknown world action")
            if op == "list":
                members = [r["ckey"] for r in self.db.execute("SELECT ckey FROM members WHERE world=? ORDER BY ckey", (world["id"],))]
                bans = [dict(r) for r in self.db.execute("SELECT ckey, by, reason FROM world_bans WHERE world=? ORDER BY at", (world["id"],))]
                return {"ok": True, "owner": world["owner"], "members": members, "bans": bans}
            target = ckey(str(data.get("target", "")))
            if not target:
                raise Denied("Name a BYOND account")
            if op in ("member_remove", "ban") and (target == world["owner"] or target in self.admins):
                raise Denied("The world's owner and server administrators can't be removed or banned")
            if op == "member_add":
                if target == world["owner"]:
                    raise Denied("The owner is already part of this world")
                if self.banned(world["id"], target):
                    raise Denied("Unban that player first")
                self.db.execute("INSERT OR REPLACE INTO members VALUES(?,?,?)", (world["id"], target, "member"))
            elif op == "member_remove":
                self.db.execute("DELETE FROM members WHERE world=? AND ckey=?", (world["id"], target))
            elif op == "ban":
                reason = clean_text(str(data.get("reason", "")))[:200] or "No reason given"
                self.db.execute("DELETE FROM members WHERE world=? AND ckey=?", (world["id"], target))
                self.db.execute("INSERT OR REPLACE INTO world_bans VALUES(?,?,?,?,?)", (world["id"], target, actor, reason, self.clock()))
            else:
                self.db.execute("DELETE FROM world_bans WHERE world=? AND ckey=?", (world["id"], target))
            if op in ("member_remove", "ban"):
                self.db.execute("DELETE FROM tickets WHERE world=? AND ckey=?", (world["id"], target))
            self.audit(actor, f"{op}:{target}", world["id"])
            return {"ok": True}

    def audit(self, actor, action, world_id):
        self.db.execute("INSERT INTO audit VALUES(?,?,?,?)", (self.clock(), actor, action, world_id))
        log("%s: %s %s" % (actor, action, self.describe(world_id)))

    def describe(self, world_id):
        world = self.row("SELECT id, name FROM worlds WHERE id=?", (world_id,)) if world_id else None
        return world_source(dict(world)).split(" ", 1)[1] if world else (world_id or "")

    def settings(self, data, current=None):
        current = current or {}
        name = clean_text(str(data.get("name", current.get("name", "Babylon"))))
        description = clean_text(str(data.get("description", current.get("description", ""))), multiline=True)
        visibility = data.get("visibility", current.get("visibility", "private"))
        if not 1 <= len(name) <= 60 or len(description) > 500:
            raise Denied("Use a name of 1–60 characters and a description up to 500 characters")
        if visibility not in ("public", "private", "showcase", "password"):
            raise Denied("Invalid visibility")
        maximum = int(data.get("max_players", current.get("max_players", self.config["max_players_per_world"])))
        if not 1 <= maximum <= self.config["max_players_per_world"]:
            raise Denied("Player limit exceeds the server limit")
        password = current.get("password")
        if "password" in data:
            if len(str(data["password"])) > 128:
                raise Denied("Password too long")
            password = password_hash(str(data["password"]))
        if visibility == "password" and not password:
            raise Denied("A password is required")
        return name, description, visibility, password, maximum

    # --- Discord account links -------------------------------------------------

    def discord_settings(self):
        return self.config.get("discord") or {}

    def discord_link(self, account):
        row = self.row("SELECT * FROM discord_links WHERE ckey=?", (ckey(account),))
        return dict(row) if row else None

    def discord_state(self, actor):
        settings = self.discord_settings()
        link = self.discord_link(actor) if settings.get("link") else None
        return {"link": bool(settings.get("link")), "linked": bool(link),
                "name": link["discord_name"] if link else None,
                "require_create": bool(settings.get("require_create")),
                "require_join": bool(settings.get("require_join")),
                "invite": settings.get("invite") or None}

    def require_discord(self, actor, purpose):
        """Raise Denied if the server requires a linked Discord account for purpose."""
        settings = self.discord_settings()
        if not settings.get("require_" + purpose) or actor in self.admins:
            return
        verb = "create" if purpose == "create" else "join"
        link = self.discord_link(actor)
        if not link:
            raise Denied(f"Link your Discord account to {verb} worlds: use Link Discord at the top of the lobby.")
        membership = self.discord_membership
        if membership and membership(link["discord_id"]) is False:
            raise Denied(f"Your linked Discord account is not on our Discord server. Rejoin it to {verb} worlds.")

    def discord_code(self, actor):
        if not self.discord_settings().get("link"):
            raise Denied("Discord linking is not enabled on this server")
        code = "".join(secrets.choice(LINK_ALPHABET) for _ in range(8))
        with self.lock, self.db:
            self.db.execute("DELETE FROM discord_codes WHERE ckey=? OR expires<=?", (actor, self.clock()))
            self.db.execute("INSERT INTO discord_codes VALUES(?,?,?)",
                            (link_code_hash(code), actor, self.clock() + LINK_CODE_SECONDS))
        log(f"{actor}: requested a Discord link code")
        return {"ok": True, "code": code[:4] + "-" + code[4:], "expires_in": LINK_CODE_SECONDS,
                "invite": self.discord_settings().get("invite") or None}

    def redeem_discord_code(self, code, discord_id, discord_name):
        """Called by the bot for /link. Returns the linked ckey."""
        discord_id = str(discord_id)
        if not re.fullmatch(r"\d{5,25}", discord_id):
            raise Denied("Invalid Discord account")
        with self.lock, self.db:
            row = self.row("SELECT * FROM discord_codes WHERE hash=? AND expires>?", (link_code_hash(code), self.clock()))
            if not row:
                raise Denied("This code is invalid or has expired. Get a new one with Link Discord in the lobby.")
            account = row["ckey"]
            previous = self.row("SELECT ckey FROM discord_links WHERE discord_id=? AND ckey<>?", (discord_id, account))
            self.db.execute("DELETE FROM discord_codes WHERE ckey=?", (account,))
            # One Discord account per BYOND account and the other way round.
            self.db.execute("DELETE FROM discord_links WHERE ckey=? OR discord_id=?", (account, discord_id))
            self.db.execute("INSERT INTO discord_links VALUES(?,?,?,?)",
                            (account, discord_id, str(discord_name)[:100], self.clock()))
            self.audit(account, "discord_link", None)
        if previous:
            log(f"{previous['ckey']}: Discord link replaced by {account}")
        self.notify_discord_link(account, discord_id, True)
        return account

    def unlink_discord(self, account=None, discord_id=None):
        """Remove a link by ckey or Discord id. Returns the removed link or None."""
        with self.lock, self.db:
            if account is not None:
                row = self.row("SELECT * FROM discord_links WHERE ckey=?", (ckey(account),))
            else:
                row = self.row("SELECT * FROM discord_links WHERE discord_id=?", (str(discord_id),))
            if not row:
                return None
            row = dict(row)
            self.db.execute("DELETE FROM discord_links WHERE ckey=?", (row["ckey"],))
            self.audit(row["ckey"], "discord_unlink", None)
        self.notify_discord_link(row["ckey"], row["discord_id"], False)
        return row

    def discord_link_by_id(self, discord_id):
        with self.lock:
            row = self.row("SELECT * FROM discord_links WHERE discord_id=?", (str(discord_id),))
        return dict(row) if row else None

    def notify_discord_link(self, account, discord_id, linked):
        callback = self.discord_link_changed
        if callback:
            try:
                callback(account, discord_id, linked)
            except Exception as error:
                log(f"Discord link notification failed: {error}")

    AHELP_KINDS = ("new", "message", "reply", "admin")

    def relay_ahelp(self, run_id, secret, data):
        """An adminhelp event from a child world, authenticated with that run's credentials."""
        with self.lock:
            run = self.child(run_id, secret)
            world = self.world(run["world"])
        kind = data.get("kind")
        if kind not in self.AHELP_KINDS:
            raise Denied("Unknown adminhelp event")
        ticket = str(data.get("ticket") or "")
        event = dict(run=run["id"], world=world["name"] if world else "Unknown world", kind=kind,
                     ticket=int(ticket) if ticket.isdigit() else None, ckey=ckey(str(data.get("ckey", ""))),
                     key=str(data.get("key") or data.get("ckey") or "")[:64],
                     sender=str(data.get("sender") or "")[:64], message=plain_text(str(data.get("message", "")))[:4000])
        log("Adminhelp %s #%s from %s in %s" % (kind, event["ticket"], event["ckey"], event["world"]))
        result = {"ok": True, "relayed": False}
        callback = self.ahelp_relay
        if callback:
            try:
                callback(event)
                result["relayed"] = True
            except Exception as error:
                log(f"Relaying an adminhelp failed: {error}")
        if kind == "new" and self.ahelp_admins_online:
            try:
                online = self.ahelp_admins_online()
                if isinstance(online, int) and online > 0:
                    result["admins_online"] = online
            except Exception as error:
                log(f"Counting online admins failed: {error}")
        return result

    def ahelp_close(self, run_id, ticket, sender):
        """Closes a world's adminhelp ticket from outside the game."""
        with self.lock:
            run = self.row("SELECT * FROM runs WHERE id=?", (run_id,))
        if not run or run["state"] != "running":
            raise Denied("That world is no longer running")
        result = self.driver.ahelp_close(dict(run), {"ticket": int(ticket), "sender": str(sender)[:64]})
        if not result.get("ok"):
            raise Denied(str(result.get("result") or result.get("error") or "The ticket could not be closed"))
        return result

    def ahelp_reply(self, run_id, target, sender, message):
        """A staff reply from outside the game, delivered as an admin PM in that world."""
        message = str(message).strip()
        if not message:
            raise Denied("The reply is empty")
        if message.lower().startswith("ticket "):
            raise Denied("Replies starting with 'ticket ' are read as ticket commands by the game")
        with self.lock:
            run = self.row("SELECT * FROM runs WHERE id=?", (run_id,))
        if not run or run["state"] != "running":
            raise Denied("That world is no longer running")
        result = self.driver.ahelp_reply(dict(run), {"ckey": ckey(target), "sender": str(sender)[:64], "message": message[:1024]})
        if not result.get("ok"):
            raise Denied(str(result.get("result") or result.get("error") or "The reply could not be delivered"))
        return result

    def announce(self, message):
        """A notice in the chat of every running world (shutdown countdown)."""
        with self.lock:
            runs = [dict(r) for r in self.db.execute("SELECT * FROM runs WHERE state='running'")]
        for run in runs:
            try:
                self.driver.announce(run, message)
            except Exception as error:
                log(f"Announcing to {self.describe(run['world'])} failed: {error}")

    def players_in_worlds(self):
        with self.lock:
            return sum(len(json.loads(r["players"] or "[]")) for r in self.db.execute("SELECT players FROM runs"))

    def status_snapshot(self):
        """Server-wide state for the Discord status message. Private worlds stay anonymous."""
        with self.lock:
            rows = self.db.execute("SELECT w.name, w.visibility, w.max_players, w.owner, r.state, r.players FROM runs r "
                                   "JOIN worlds w ON w.id=r.world ORDER BY r.started").fetchall()
            total = self.row("SELECT count(*) n FROM worlds")["n"]
        worlds = [{"name": row["name"] if row["visibility"] != "private" else None,
                   "visibility": row["visibility"], "state": row["state"], "max_players": row["max_players"],
                   "players": len(json.loads(row["players"] or "[]")), "admin": row["owner"] in self.admins}
                  for row in rows]
        active = [w for w in worlds if w["state"] in ("starting", "running")]
        return {"worlds": worlds, "total_worlds": total, "max_running_worlds": self.config["max_running_worlds"],
                "running_worlds": sum(not w["admin"] for w in active), "admin_worlds": sum(w["admin"] for w in active),
                "players": sum(w["players"] for w in active)}

    def summary(self):
        """Cluster-wide counts for the lobby's hub status; no per-world details."""
        with self.lock:
            runs = self.db.execute("SELECT r.state, r.players, w.owner FROM runs r LEFT JOIN worlds w ON w.id=r.world").fetchall()
        active = [run for run in runs if run["state"] in ("starting", "running")]
        # Admin worlds run outside the limit and are reported separately ("2 running worlds (+1)").
        return {"ok": True, "running_worlds": sum(run["owner"] not in self.admins for run in active),
                "admin_worlds": sum(run["owner"] in self.admins for run in active),
                "players": sum(len(json.loads(run["players"] or "[]")) for run in active)}

    def dispatch(self, actor, action, data):
        if action == "summary":
            return self.summary()
        actor = ckey(actor)
        if not actor or actor.startswith("guest"):
            raise Denied("Sign in with a BYOND account")
        if action == "delete":
            return self.delete_world(actor, data)
        if action == "discord_code":
            return self.discord_code(actor)
        if action == "discord_unlink":
            return {"ok": True, "unlinked": bool(self.unlink_discord(actor))}
        with self.lock, self.db:
            if action == "list":
                worlds = []
                for item in self.db.execute("SELECT * FROM worlds ORDER BY created DESC").fetchall():
                    world = dict(item)
                    role = self.role(actor, world)
                    if world["visibility"] == "private" and role == "guest":
                        continue
                    run = self.row("SELECT * FROM runs WHERE world=?", (world["id"],))
                    worlds.append({k: world[k] for k in ("id", "owner", "name", "description", "visibility", "max_players")})
                    worlds[-1].update(role=role, state=run["state"] if run else "stopped",
                                      players=len(json.loads(run["players"])) if run else 0,
                                      last_save=run["last_save"] if run else self.last_save(world["id"]),
                                      error=run["error"] if run else None,
                                      last_active=time.strftime("%Y-%m-%d %H:%M", time.localtime(world["last_used"])))
                return {"ok": True, "worlds": worlds, "admin": actor in self.admins, "server_notice": self.server_notice,
                        "discord": self.discord_state(actor),
                        "delete_unused_worlds_after_days": self.config.get("delete_unused_worlds_after_days", 60),
                        "limits": {k: v for k, v in self.config.items() if k.startswith("max_")}}
            if action in ("create", "join") and self.shutting_down:
                raise Denied("The server is restarting. Try again in a minute.")
            if action == "create":
                self.require_discord(actor, "create")
                count = self.row("SELECT count(*) n FROM worlds WHERE owner=?", (actor,))["n"]
                if count >= self.config["max_worlds_per_player"]:
                    raise Denied("Your world limit has been reached")
                fields = self.settings(data)
                world_id = secrets.token_hex(16)
                self.db.execute("INSERT INTO worlds(id,owner,name,description,visibility,password,max_players,created,last_used) VALUES(?,?,?,?,?,?,?,?,?)",
                                (world_id, actor, *fields, self.clock(), self.clock()))
                self.audit(actor, action, world_id)
                return {"ok": True, "id": world_id}
            world = self.world(data.get("world"))
            role = self.role(actor, world)
            if action in ("edit", "stop", "member", "checkpoints", "rollback"):
                if role not in ("owner", "admin"):
                    raise Denied("Only the owner or a server administrator can do that")
                run = self.row("SELECT * FROM runs WHERE world=?", (world["id"],))
                if action in ("checkpoints", "rollback"):
                    if run:
                        raise Denied("Stop the world before browsing or restoring checkpoints")
                    try:
                        self.checkpoints.retain(world["id"])
                        if action == "checkpoints":
                            return {"ok": True, **self.checkpoints.list(world["id"])}
                        if data.get("confirm_delete_newer") not in (True, 1):
                            raise Denied("Confirm that all newer checkpoints will be permanently deleted")
                        result = self.checkpoints.rollback(world["id"], data.get("generation"), data.get("expected_latest"))
                    except CheckpointError as error:
                        raise Denied(str(error)) from None
                    self.db.execute("DELETE FROM tickets WHERE world=?", (world["id"],))
                    self.db.execute("UPDATE worlds SET last_used=? WHERE id=?", (self.clock(), world["id"]))
                    self.audit(actor, "rollback:" + result["generation"], world["id"])
                    return result
                elif action == "edit":
                    if run:
                        raise Denied("Stop the world before editing its settings")
                    fields = self.settings(data, world)
                    self.db.execute("UPDATE worlds SET name=?,description=?,visibility=?,password=?,max_players=? WHERE id=?",
                                    (*fields, world["id"]))
                    self.db.execute("DELETE FROM tickets WHERE world=?", (world["id"],))
                elif action == "member":
                    who = ckey(data.get("member", ""))
                    member_role = data.get("role", "member")
                    if not who or who == world["owner"] or member_role not in ("member", "remove"):
                        raise Denied("Invalid membership change")
                    self.db.execute("DELETE FROM members WHERE world=? AND ckey=?", (world["id"], who))
                    if member_role == "member":
                        self.db.execute("INSERT INTO members VALUES(?,?,?)", (world["id"], who, "member"))
                    self.db.execute("DELETE FROM tickets WHERE world=? AND ckey=?", (world["id"], who))
                else:
                    if run:
                        self.begin_stop(run)
                self.audit(actor, action, world["id"])
                self.db.execute("UPDATE worlds SET last_used=? WHERE id=?", (self.clock(), world["id"]))
                return {"ok": True}
            if action != "join":
                raise Denied("Unknown action")
            self.require_discord(actor, "join")
            if self.banned(world["id"], actor):
                raise Denied("You are banned from this world")
            authorized = role != "guest" or world["visibility"] in ("public", "showcase")
            if not authorized and world["visibility"] == "password":
                authorized = password_matches(str(data.get("password", "")), world["password"])
            if not authorized:
                raise Denied("This world is private or the password is incorrect")
            run = self.row("SELECT * FROM runs WHERE world=?", (world["id"],))
            if not run:
                if role == "guest":
                    raise Denied("This world is offline. Only its owner, members or a server administrator can start it")
                self.start(world)
                return {"ok": True, "pending": True}
            if run["state"] == "starting":
                return {"ok": True, "pending": True}
            if run["state"] != "running":
                raise Denied(run["error"] or "World is stopping; try again shortly")
            players = set(json.loads(run["players"]))
            players.update(r[0] for r in self.db.execute("SELECT ckey FROM sessions WHERE run=?", (run["id"],)))
            # A player's current ticket can be replaced without reserving another slot.
            self.db.execute("DELETE FROM tickets WHERE ckey=? OR expires<=?", (actor, self.clock()))
            reserved = self.row("SELECT count(*) n FROM tickets WHERE run=? AND ckey NOT IN (SELECT ckey FROM sessions WHERE run=?)",
                                (run["id"], run["id"]))["n"]
            if actor not in players and len(players) + reserved >= world["max_players"] and role != "admin":
                raise Denied("World is full")
            token = secrets.token_urlsafe(32)
            self.db.execute("INSERT INTO tickets VALUES(?,?,?,?,?,?,?)",
                            (hashlib.sha256(token.encode()).hexdigest(), actor, world["id"], run["id"],
                             self.clock() + self.config["ticket_lifetime_seconds"], world["password"], role == "admin"))
            self.db.execute("UPDATE runs SET empty_since=NULL WHERE id=?", (run["id"],))
            self.audit(actor, "ticket", world["id"])
            return {"ok": True, "address": f"byond://{self.config['public_host']}:{run['port']}?babylon_ticket={token}"}

    def last_save(self, world_id):
        path = Path(self.config["data_directory"]) / "worlds" / world_id / "data/babylon/saves/latest.json"
        try:
            return json.loads(path.read_text())["generation"]
        except (FileNotFoundError, ValueError, KeyError):
            return None

    def start(self, world):
        # Finish any interrupted rollback before a child can read its startup files.
        try:
            self.checkpoints.retain(world["id"])
        except CheckpointError as error:
            raise Denied(str(error)) from None
        runs = [dict(r) for r in self.db.execute("SELECT r.*, w.owner FROM runs r LEFT JOIN worlds w ON w.id=r.world")]
        # Admin worlds run outside the limit; they only need a free port.
        if world["owner"] not in self.admins and sum(r["owner"] not in self.admins for r in runs) >= self.config["max_running_worlds"]:
            raise Denied("The server's running-world limit has been reached")
        owned = self.row("SELECT count(*) n FROM runs r JOIN worlds w ON w.id=r.world WHERE w.owner=?", (world["owner"],))["n"]
        if owned >= self.config["max_running_worlds_per_player"]:
            raise Denied("This owner's running-world limit has been reached")
        ports = {r["port"] for r in runs}
        port = next((p for p in range(self.config["port_first"], self.config["port_last"] + 1) if p not in ports), None)
        if port is None:
            raise Denied("No child port is available")
        run = dict(id=secrets.token_hex(16), world=world["id"], port=port,
                   secret=secrets.token_urlsafe(32), state="starting", started=self.clock(), pid=None)
        self.db.execute("INSERT INTO runs(id,world,port,secret,state,started) VALUES(:id,:world,:port,:secret,:state,:started)", run)
        self.db.execute("UPDATE worlds SET last_used=? WHERE id=?", (self.clock(), world["id"]))
        # Commit the launch intent before starting a child so supervisor restarts can reconcile it.
        self.db.commit()
        try:
            pid = self.driver.start(world, run)
            self.db.execute("UPDATE runs SET pid=? WHERE id=?", (pid, run["id"]))
            log("Starting %s on port %s (pid %s)" % (self.describe(world["id"]), port, pid))
        except Exception as error:
            log("Starting %s failed: %s" % (self.describe(world["id"]), error))
            self.db.execute("DELETE FROM runs WHERE id=?", (run["id"],))
            self.db.commit()
            raise Denied("Child startup failed; check the supervisor and daemon logs")

    def child(self, run_id, secret):
        run = self.row("SELECT * FROM runs WHERE id=?", (run_id,))
        if not run or not hmac.compare_digest(str(secret), run["secret"]):
            raise Denied("Invalid child credentials")
        return run

    def redeem(self, run_id, secret, token, actor):
        with self.lock, self.db:
            run = self.child(run_id, secret)
            ticket = self.row("SELECT * FROM tickets WHERE hash=?", (hashlib.sha256(token.encode()).hexdigest(),))
            if not ticket or ticket["run"] != run_id or ticket["world"] != run["world"] or ticket["ckey"] != ckey(actor) or ticket["expires"] <= self.clock() or run["state"] != "running":
                raise Denied("Admission expired or invalid; reconnect through the lobby")
            world = self.world(run["world"])
            role = self.role(ckey(actor), world)
            if self.banned(world["id"], ckey(actor)):
                raise Denied("You are banned from this world")
            if role == "guest" and world["visibility"] not in ("public", "showcase") and not (world["visibility"] == "password" and ticket["password_hash"] == world["password"]):
                raise Denied("Access has changed")
            players = set(json.loads(run["players"]))
            sessions = {r[0] for r in self.db.execute("SELECT ckey FROM sessions WHERE run=?", (run_id,))}
            if ckey(actor) not in players | sessions and len(players | sessions) >= world["max_players"] and role != "admin":
                raise Denied("World is full")
            self.db.execute("DELETE FROM tickets WHERE hash=?", (ticket["hash"],))
            self.db.execute("INSERT OR REPLACE INTO sessions VALUES(?,?,?)", (ckey(actor), world["id"], run_id))
            self.db.execute("UPDATE worlds SET last_used=? WHERE id=?", (self.clock(), world["id"]))
            self.db.execute("UPDATE runs SET empty_since=NULL WHERE id=?", (run_id,))
            self.audit(ckey(actor), "admit", world["id"])
            return {"ok": True, "world": world["id"], "run": run_id, "role": role,
                    "mode": "showcase" if role == "guest" and world["visibility"] == "showcase" else "player"}

    def begin_stop(self, run):
        if run["id"] in self.stop_workers:
            return
        self.stop_workers.add(run["id"])
        log("Stopping %s (port %s): saving" % (self.describe(run["world"]), run["port"]))
        self.db.execute("UPDATE runs SET state='stopping',error=NULL WHERE id=?", (run["id"],))
        self.db.execute("DELETE FROM tickets WHERE run=?", (run["id"],))
        self.db.commit()

        def stop():
            try:
                response = self.driver.stop(run)
                if not response.get("ok"):
                    raise Denied("Final save failed; child has been kept alive")
            except Exception as error:
                log("Stopping %s failed, process retained: %s" % (self.describe(run["world"]), error))
                with self.lock, self.db:
                    self.db.execute("UPDATE runs SET state='error',error=? WHERE id=?",
                                    ("Stop/save failed; process retained. Inspect logs and retry Stop.", run["id"]))
            finally:
                with self.lock:
                    self.stop_workers.discard(run["id"])
        threading.Thread(target=stop, daemon=True).start()

    def tick(self):
        self.cleanup_unused_worlds()
        # Never hold the DB lock during network requests: a child may be redeeming a ticket.
        with self.lock:
            runs = [dict(r) for r in self.db.execute("SELECT * FROM runs")]
        for run in runs:
            try:
                status = self.driver.status(run)
                if status.get("run") != run["id"] or status.get("world") != run["world"]:
                    raise Denied("Child identity mismatch")
            except Exception:
                if self.driver.alive(run) or not run["pid"]:
                    if self.clock() - run["started"] > self.config["startup_timeout_seconds"] and run["state"] == "starting":
                        with self.lock, self.db:
                            self.db.execute("UPDATE runs SET state='error',error='Startup timed out; process retained' WHERE id=?", (run["id"],))
                        log("%s did not start within %ss; process retained" % (self.describe(run["world"]), self.config["startup_timeout_seconds"]))
                    continue
                log("%s exited (port %s)" % (self.describe(run["world"]), run["port"]))
                with self.lock, self.db:
                    self.db.execute("DELETE FROM runs WHERE id=?", (run["id"],))
                    self.db.execute("DELETE FROM tickets WHERE run=?", (run["id"],))
                    self.db.execute("DELETE FROM sessions WHERE run=?", (run["id"],))
                    self.maintain_checkpoints(run["world"])
                continue
            with self.lock, self.db:
                current = self.row("SELECT * FROM runs WHERE id=?", (run["id"],))
                if not current:
                    continue
                players = [ckey(p) for p in status.get("players", [])]
                if players:
                    self.db.execute("UPDATE worlds SET last_used=? WHERE id=?", (self.clock(), run["world"]))
                state = current["state"]
                if state == "starting" and status.get("ready"):
                    state = "running"
                if status.get("error"):
                    state = "error"
                if state != current["state"]:
                    log("%s is %s%s" % (self.describe(run["world"]), state,
                                        ": " + str(status["error"]) if status.get("error") else ""))
                self.db.execute("DELETE FROM tickets WHERE expires<=?", (self.clock(),))
                # Admissions get a short interval to complete client.New after redemption.
                active = {r[0] for r in self.db.execute("SELECT actor FROM audit WHERE action='admit' AND world=? AND at>?", (run["world"], self.clock() - 30))}
                for session in self.db.execute("SELECT ckey FROM sessions WHERE run=?", (run["id"],)).fetchall():
                    if session[0] not in players and session[0] not in active:
                        self.db.execute("DELETE FROM sessions WHERE ckey=? AND run=?", (session[0], run["id"]))
                pending = self.row("SELECT count(*) n FROM tickets WHERE run=?", (run["id"],))["n"]
                empty = None if players or pending or active else (current["empty_since"] or self.clock())
                self.db.execute("UPDATE runs SET state=?,players=?,empty_since=?,last_save=?,error=? WHERE id=?",
                                (state, json.dumps(players), empty, status.get("last_save"), status.get("error") or current["error"], run["id"]))
                if status.get("last_save") and not status.get("busy"):
                    self.maintain_checkpoints(run["world"], expected=status["last_save"])
                if state == "running" and empty and self.clock() - empty >= self.config["empty_grace_seconds"]:
                    self.begin_stop(current)


def load_config(path):
    config = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    config.setdefault("kept_save_points_per_world", 4)
    config.setdefault("delete_unused_worlds_after_days", 60)
    config.setdefault("afk_timeout_seconds", 900)
    if type(config["afk_timeout_seconds"]) is not int or config["afk_timeout_seconds"] < 0:
        raise ValueError("afk_timeout_seconds must be a nonnegative integer (0 disables AFK kicks)")
    if type(config["delete_unused_worlds_after_days"]) is not int or config["delete_unused_worlds_after_days"] < 0:
        raise ValueError("delete_unused_worlds_after_days must be a nonnegative integer (0 disables expiry)")
    if config.get("listen_host") != "127.0.0.1":
        raise ValueError("The trusted API must bind to 127.0.0.1")
    if len(config.get("lobby_secret", "")) < 32 or config["lobby_secret"].startswith("REPLACE"):
        raise ValueError("Set a random lobby_secret of at least 32 characters")
    for key in ("listen_port", "port_first", "port_last", "max_running_worlds", "max_players_per_world",
                "max_worlds_per_player", "max_running_worlds_per_player", "empty_grace_seconds",
                "startup_timeout_seconds", "ticket_lifetime_seconds", "kept_save_points_per_world"):
        if type(config.get(key)) is not int or config[key] < 1:
            raise ValueError(f"{key} must be a positive integer")
    if config["port_last"] < config["port_first"] or config["port_last"] > 65535:
        raise ValueError("Invalid child port range")
    if not re.fullmatch(r"[A-Za-z0-9.-]+", config["public_host"]):
        raise ValueError("public_host must be a hostname or IPv4 address")
    for key in ("data_directory", "template_directory", "config_directory", "dreamdaemon"):
        config[key] = str(Path(config[key]).resolve())
    return config


def serve(config, service=None):
    service = service or Supervisor(config)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # URL/body contain secrets. Audit actions, never raw requests.

        def do_POST(self):
            self.handle_api()

        def do_GET(self):
            # BYOND world.Export uses URL-encoded GET; loopback-only, never log query strings.
            self.handle_api()

        def handle_api(self):
            try:
                if self.command == "POST":
                    size = int(self.headers.get("Content-Length", "0"))
                    if not 0 < size <= 16384:
                        raise Denied("Invalid request size")
                    data = json.loads(self.rfile.read(size))
                else:
                    if len(self.path) > 16384:
                        raise Denied("Request too large")
                    data = {k: v[-1] for k, v in parse_qs(urlsplit(self.path).query, keep_blank_values=True).items()}
                if data.get("action") == "redeem":
                    result = service.redeem(data.get("run"), data.get("secret", ""), data.get("ticket", ""), data.get("actor", ""))
                elif data.get("action") == "ahelp":
                    result = service.relay_ahelp(data.get("run"), data.get("secret", ""), data)
                elif data.get("action") == "world_manage":
                    result = service.manage_world(data.get("run"), data.get("secret", ""), data)
                else:
                    if not hmac.compare_digest(str(data.get("secret", "")), config["lobby_secret"]):
                        raise Denied("Invalid lobby credentials")
                    payload = data.get("payload", {})
                    if isinstance(payload, str):
                        payload = json.loads(payload)
                    result = service.dispatch(data.get("actor", ""), data.get("action"), payload)
                code = 200
            except (Denied, ValueError, TypeError, KeyError):
                # Return useful expected errors, but never tracebacks/secrets to the client.
                import sys
                error = sys.exc_info()[1]
                result = {"ok": False, "error": str(error) if isinstance(error, Denied) else "Invalid request"}
                code = 403
            except Exception:
                result, code = {"ok": False, "error": "Supervisor error; consult server logs"}, 500
                import traceback
                log(traceback.format_exc())
            encoded = json.dumps(result).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    server = ThreadingHTTPServer((config["listen_host"], config["listen_port"]), Handler)
    server.daemon_threads = True

    def monitor():
        while True:
            try:
                service.tick()
            except Exception:
                import traceback
                log(traceback.format_exc())
            time.sleep(2)

    threading.Thread(target=monitor, daemon=True).start()
    log(f"Listening on 127.0.0.1:{config['listen_port']}")
    server.serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    serve(load_config(parser.parse_args().config))
