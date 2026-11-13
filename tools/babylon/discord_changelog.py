#!/usr/bin/env python3
"""Posts the changelog to a Discord webhook as embed cards.

    discord_changelog.py commit    every commit of a push, one line each
    discord_changelog.py release   the published release's description

Reads the GitHub event from GITHUB_EVENT_PATH and the webhook from DISCORD_WEBHOOK_URL
(without it nothing is posted). DISCORD_CHANGELOG_ROLE, a role ID, is mentioned above the
first card. Nothing is dropped: text longer than one card continues on further cards.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

# Discord allows 4096 characters per embed description and 6000 per message; one card per
# message with some margin stays below both.
DESCRIPTION_LIMIT = 4000
TITLE_LIMIT = 256
SUBJECT_LIMIT = 200
COMMIT_COLOR = 0x5865F2
RELEASE_COLOR = 0x57F287
PRERELEASE_COLOR = 0xFEE75C


def escape(text):
    """Keeps commit subjects and names from turning into Discord markdown."""
    for character in "\\*_~`|>[]":
        text = text.replace(character, "\\" + character)
    return text


def shorten(text, limit):
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def chunk_lines(lines, limit=DESCRIPTION_LIMIT):
    """Groups whole lines into blocks of at most `limit` characters; overlong lines are split."""
    chunks = []
    current = ""
    for line in lines:
        while len(line) > limit:
            if current:
                chunks.append(current)
                current = ""
            chunks.append(line[:limit])
            line = line[limit:]
        candidate = f"{current}\n{line}" if current else line
        if len(candidate) > limit:
            chunks.append(current)
            current = line
        else:
            current = candidate
    if current:
        chunks.append(current)
    return chunks


def numbered(title, index, total):
    suffix = f" ({index}/{total})" if total > 1 else ""
    return shorten(title, TITLE_LIMIT - len(suffix)) + suffix


def repository_author(event):
    repository = event["repository"]
    author = {"name": repository["full_name"], "url": repository["html_url"]}
    avatar = (repository.get("owner") or {}).get("avatar_url")
    if avatar:
        author["icon_url"] = avatar
    return author


def commit_embeds(event):
    """One line per commit of the push, oldest first; all of them, spread over cards."""
    if event.get("deleted"):
        return []
    commits = event.get("commits") or []
    lines = []
    for commit in commits:
        subject = (commit.get("message") or "").strip().splitlines()
        subject = escape(shorten(subject[0].strip() if subject else "(no message)", SUBJECT_LIMIT))
        author = (commit.get("author") or {}).get("name") or "unknown"
        lines.append(f"[`{commit['id'][:7]}`]({commit['url']}) {subject} — *{escape(author)}*")
    if not lines:
        return []
    branch = event["ref"].removeprefix("refs/heads/")
    count = len(lines)
    title = f"{count} new commit{'s' if count != 1 else ''} on {branch}"
    chunks = chunk_lines(lines)
    pusher = (event.get("pusher") or {}).get("name")
    timestamp = (event.get("head_commit") or {}).get("timestamp")
    embeds = []
    for index, description in enumerate(chunks, 1):
        embed = {
            "title": numbered(title, index, len(chunks)),
            "url": event.get("compare") or event["repository"]["html_url"],
            "description": description,
            "color": COMMIT_COLOR,
            "author": repository_author(event),
        }
        if pusher:
            embed["footer"] = {"text": f"Pushed by {pusher}"}
        if timestamp:
            embed["timestamp"] = timestamp
        embeds.append(embed)
    return embeds


def release_embeds(event):
    """The release's description, as written on GitHub (Discord renders its markdown)."""
    release = event["release"]
    if release.get("draft"):
        return []
    name = (release.get("name") or "").strip() or release["tag_name"]
    title = f"{'Pre-release' if release.get('prerelease') else 'Release'} {name}"
    body = (release.get("body") or "").strip().replace("\r\n", "\n") or "No release notes."
    chunks = chunk_lines(body.split("\n"))
    embeds = []
    for index, description in enumerate(chunks, 1):
        embed = {
            "title": numbered(title, index, len(chunks)),
            "url": release["html_url"],
            "description": description,
            "color": PRERELEASE_COLOR if release.get("prerelease") else RELEASE_COLOR,
            "author": repository_author(event),
            "footer": {"text": release["tag_name"]},
        }
        if release.get("published_at"):
            embed["timestamp"] = release["published_at"]
        embeds.append(embed)
    return embeds


def messages(embeds, role=None):
    """One card per message; only the first mentions the role."""
    result = []
    for index, embed in enumerate(embeds):
        message = {"embeds": [embed], "allowed_mentions": {"parse": []}}
        if role and index == 0:
            message["content"] = f"<@&{role}>"
            message["allowed_mentions"] = {"parse": [], "roles": [role]}
        result.append(message)
    return result


def post(webhook, message, user_agent):
    data = json.dumps(message).encode()
    for _ in range(5):
        request = urllib.request.Request(
            webhook + ("&" if "?" in webhook else "?") + "wait=true",
            data=data,
            headers={"Content-Type": "application/json", "User-Agent": user_agent},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=30):
                return
        except urllib.error.HTTPError as error:
            if error.code != 429:
                detail = error.read().decode(errors="replace")
                raise SystemExit(f"Discord rejected the message ({error.code}): {detail}") from None
            retry = json.loads(error.read() or b"{}").get("retry_after", 2)
            time.sleep(float(retry) + 0.5)
    raise SystemExit("Discord kept rate limiting the webhook.")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode not in ("commit", "release"):
        raise SystemExit("usage: discord_changelog.py commit|release")
    webhook = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    if not webhook:
        print("::warning::DISCORD_CHANGELOG_WEBHOOK secret not set; nothing posted.")
        return
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as file:
        event = json.load(file)
    embeds = commit_embeds(event) if mode == "commit" else release_embeds(event)
    role = os.environ.get("DISCORD_CHANGELOG_ROLE", "").strip() or None
    if role and not role.isdigit():
        raise SystemExit("DISCORD_CHANGELOG_ROLE must be a role ID.")
    user_agent = f"DiscordBot ({event['repository']['html_url']}, 1.0)"
    for index, message in enumerate(messages(embeds, role)):
        if index:
            time.sleep(1)  # Webhooks allow about five messages per two seconds.
        post(webhook, message, user_agent)
    print(f"Posted {len(embeds)} card(s) to Discord.")


if __name__ == "__main__":
    main()
