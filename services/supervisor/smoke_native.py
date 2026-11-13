"""Explicit integration test with real DreamDaemon children; no player world is touched."""
import argparse
import json
from pathlib import Path
import secrets
import shutil
import socket
import threading
import time
import urllib.request

from protocol import topic
from supervisor import Driver, Supervisor, serve


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dreamdaemon", required=True)
    parser.add_argument("--config-directory", required=True)
    parser.add_argument("--data-directory", required=True)
    parser.add_argument("--api-port", type=int, default=1368)
    parser.add_argument("--child-port", type=int, default=1458)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    # Closet/crate contents are generated on first opening; count the papers
    # available immediately after initialization, including satchel contents.
    lore = json.loads((root / "_maps/babylon/lore.json").read_text())
    expected_lore = sum(not item["paper"].startswith("/obj/structure/closet/") for item in lore)
    data = Path(args.data_directory).resolve()
    if data.exists():
        raise RuntimeError("Use a new empty test data directory")
    for port in (args.api_port, args.child_port):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", port))
    config = dict(data_directory=str(data), template_directory=str(root),
                  config_directory=str(Path(args.config_directory).resolve()),
                  dreamdaemon=str(Path(args.dreamdaemon).resolve()),
                  max_worlds_per_player=3, max_running_worlds_per_player=1,
                  max_running_worlds=1, max_players_per_world=2,
                  port_first=args.child_port, port_last=args.child_port,
                  ticket_lifetime_seconds=60, empty_grace_seconds=600,
                  startup_timeout_seconds=300, public_host="127.0.0.1", admins=["testadmin"],
                  listen_host="127.0.0.1", listen_port=args.api_port,
                  lobby_secret=secrets.token_urlsafe(32), lobby_address="byond://127.0.0.1:1369")

    class TestDriver(Driver):
        def prepare(self, world, run):
            prepared = super().prepare(world, run)
            for ext in ("dmb", "rsc"):
                shutil.copy2(root / f"babylon-test.{ext}", prepared / f"babylon.{ext}")
            return prepared

    driver = TestDriver(config)
    service = Supervisor(config, driver)
    threading.Thread(target=serve, args=(config, service), daemon=True).start()

    def api(action, payload=None, actor="smokeowner"):
        body = json.dumps(dict(secret=config["lobby_secret"], actor=actor, action=action, payload=payload or {})).encode()
        request = urllib.request.Request(f"http://127.0.0.1:{args.api_port}/api", data=body,
                                         headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=180) as response:
            result = json.load(response)
        assert result.get("ok"), result
        return result

    def current():
        with service.lock:
            return service.row("SELECT * FROM runs")

    def wait_ready(world):
        api("join", {"world": world})
        deadline = time.time() + 300
        while time.time() < deadline:
            run = current()
            if run and run["state"] == "running":
                return run
            if run and run["state"] == "error":
                raise RuntimeError(run["error"])
            time.sleep(2)
        raise TimeoutError("Child did not become ready")

    def debug(run, action, payload):
        result = topic(run["port"], run["secret"], action, payload, timeout=180)
        assert not result.get("error"), result
        return result

    def call(run, target, proc, values=None):
        return debug(run, "call", dict(target=target, proc=proc, args=values or []))["result"]

    def stop(world):
        api("stop", {"world": world})
        deadline = time.time() + 60
        while time.time() < deadline and current():
            time.sleep(1)
        assert not current(), "Child did not exit after checkpoint"

    try:
        time.sleep(.5)
        world = api("create", dict(name="Native smoke", visibility="private"))["id"]
        run = wait_ready(world)
        assert topic(run["port"], run["secret"], "status")["players"] == []
        assert topic(run["port"], run["secret"], "announce", {"message": "Smoke restart notice"}).get("ok"), "announce failed"
        afk = call(run, "session", "test_afk_policy")
        afk = {entry["entry"]: entry["value"] for entry in afk["entries"]}
        assert afk and all(afk.values()), afk
        showcase = call(run, "session", "test_showcase_visitor")
        showcase = {entry["entry"]: entry["value"] for entry in showcase["entries"]}
        assert showcase and all(showcase.values()), showcase
        experience = call(run, "session", "test_builder_experience")
        experience = {entry["entry"]: entry["value"] for entry in experience["entries"]}
        for key in ("replacement_items", "replacement_storage", "replacement_head", "station_confinement", "physical_cafe_turfs"):
            assert experience[key] == 0, experience
        for key in ("spawners_hidden", "minigames_hidden", "dnr_present", "reenter_present", "return_before_destruct"):
            assert experience[key], experience
        assert experience["lore_papers"] == expected_lore, experience
        sfw = call(run, "session", "test_sfw_content")
        sfw = {entry["entry"]: entry["value"] for entry in sfw["entries"]}
        assert sfw and all(sfw.values()), sfw
        moderation = call(run, "session", "test_moderation")
        moderation = {entry["entry"]: entry["value"] for entry in moderation["entries"]}
        assert moderation and all(moderation.values()), moderation
        research = call(run, "session", "test_research")
        research = {entry["entry"]: entry["value"] for entry in research["entries"]}
        assert research and all(research.values()), research
        closets = call(run, "session", "test_closet_contents")
        closets = {entry["entry"]: entry["value"] for entry in closets["entries"]}
        assert closets and all(closets.values()), closets
        music = call(run, "session", "test_music_folders")
        music = {entry["entry"]: entry["value"] for entry in music["entries"]}
        assert music and all(music.values()), music
        loops = call(run, "session", "test_music_loops")
        loops = {entry["entry"]: entry["value"] for entry in loops["entries"]}
        assert loops and all(loops.values()), loops
        joining = call(run, "session", "test_join_loading")
        joining = {entry["entry"]: entry["value"] for entry in joining["entries"]}
        assert joining and all(joining.values()), joining
        silicons = call(run, "session", "test_no_unplayable_silicons")
        silicons = {entry["entry"]: entry["value"] for entry in silicons["entries"]}
        assert silicons and all(silicons.values()), silicons
        played = call(run, "session", "test_play_time")
        played = {entry["entry"]: entry["value"] for entry in played["entries"]}
        assert played and all(played.values()), played
        wrap = call(run, "session", "test_space_wrap")
        wrap = {entry["entry"]: entry["value"] for entry in wrap["entries"]}
        assert wrap and all(wrap.values()), wrap
        storyteller = call(run, "session", "test_no_storyteller")
        storyteller = {entry["entry"]: entry["value"] for entry in storyteller["entries"]}
        assert storyteller and all(storyteller.values()), storyteller
        player = call(run, "session", "ensure_player", ["smokefriend"])
        friend_ref = player["ref"]
        fields = debug(run, "inspect", dict(target=friend_ref, vars=["builder"]))["vars"]
        friend_drone = fields["builder"]["ref"]
        debug(run, "set_var", dict(target=friend_drone, var="name", value="Second persistent drone"))
        debug(run, "set_var", dict(target=friend_drone, var="picked", value=1))
        bag = debug(run, "spawn", dict(type="/obj/item/storage/backpack", target=friend_drone))["object"]["ref"]
        call(run, friend_drone, "put_in_hand", [{"ref": bag}, 2, 1])
        closet = debug(run, "spawn", dict(type="/obj/structure/closet", target=friend_drone))["object"]["ref"]
        call(run, friend_drone, "forceMove", [{"ref": closet}])
        call(run, friend_drone, "death")
        # Exercise real DM world.Export -> HTTP redemption, with an admin bypass.
        address = api("join", {"world": world}, actor="testadmin")["address"]
        ticket = address.split("babylon_ticket=")[1]
        query = dict(action="redeem", actor="testadmin", ticket=ticket)
        # Test-only helper runs the same HTTP request procedure as client.New.
        exported = call(run, "session", "test_supervisor_export", [json.dumps(query)])
        assert any(e["entry"] == "ok" and e["value"] for e in exported["entries"]), exported
        exported = call(run, "session", "test_supervisor_export", [json.dumps(query)])
        assert not any(e["entry"] == "ok" and e["value"] for e in exported["entries"]), "Ticket replay accepted"
        stop(world)
        saved = data / "worlds" / world / "data/babylon/saves"
        generation = json.loads((saved / "latest.json").read_text())["generation"]
        before = json.loads((saved / generation / "state.json").read_text())
        assert set(before["players"]) == {"smokeowner", "smokefriend"}
        friend_id = before["players"]["smokefriend"]["builder"]
        assert before["players"]["smokefriend"]["respawn_pending"]
        run = wait_ready(world)
        roster = debug(run, "inspect", dict(target="session", vars=["player_sessions"]))["vars"]["player_sessions"]
        assert roster["length"] == 2, roster
        restored_friend = next(e["value"]["ref"] for e in roster["entries"] if e["entry"] == "smokefriend")
        fields = debug(run, "inspect", dict(target=restored_friend, vars=["builder", "respawn_pending", "respawn_ready_at"]))["vars"]
        assert fields["builder"]["name"] == "Second persistent drone", fields
        assert fields["respawn_pending"], fields
        # Restoring refreshes every object's appearance; holobarriers must keep their overlay.
        barriers = debug(run, "find", dict(type="/obj/structure/holosign/barrier", limit=5))["matches"]
        assert barriers, "the map's holobarriers were not restored"
        for barrier in barriers:
            shown = debug(run, "inspect", dict(target=barrier["ref"], vars=["vis_contents"]))["vars"]["vis_contents"]
            assert shown["length"] >= 1, "restored holobarrier lost its overlay (invisible)"
        papers = debug(run, "find", dict(type="/obj/item/paper/babylon", limit=100))["matches"]
        assert len(papers) == expected_lore, papers
        # Exercise the actual respawn path, not only the replacement initializer.
        debug(run, "set_var", dict(target=restored_friend, var="respawn_ready_at", value=0))
        assert call(run, restored_friend, "respawn_builder"), "Respawn failed"
        replacement = debug(run, "inspect", dict(target=restored_friend, vars=["builder"]))["vars"]["builder"]["ref"]
        equipment = debug(run, "inspect", dict(target=replacement, vars=["internal_storage", "head", "contents"]))["vars"]
        assert not equipment["internal_storage"] and not equipment["head"], equipment
        assert not any(isinstance(e["entry"], dict) and e["entry"].get("type", "").startswith("/obj/item") for e in equipment["contents"]["entries"]), equipment
        stop(world)
        generation2 = json.loads((saved / "latest.json").read_text())["generation"]
        after = json.loads((saved / generation2 / "state.json").read_text())
        assert after["players"]["smokefriend"]["builder"] != friend_id
        objects = {r["id"]: r for r in after["records"]}
        inventory = [r for r in before["records"] if r.get("parent") == friend_id]
        for item in inventory:
            assert objects[item["id"]].get("parent") == friend_id
        # A real showcase child must classify admission through native HTTP,
        # including attempts to request player access from an untrusted guest.
        showcase_world = api("create", dict(name="Native showcase", visibility="showcase"))["id"]
        showcase_run = wait_ready(showcase_world)
        for actor, mode in (("smokevisitor", "showcase"), ("smokeowner", "player"), ("testadmin", "player")):
            address = api("join", dict(world=showcase_world, mode="player"), actor=actor)["address"]
            query = dict(action="redeem", actor=actor, ticket=address.split("babylon_ticket=")[1], mode="player")
            exported = call(showcase_run, "session", "test_supervisor_export", [json.dumps(query)])
            fields = {entry["entry"]: entry["value"] for entry in exported["entries"]}
            assert fields.get("ok") and fields.get("mode") == mode, fields
        stop(showcase_world)
        report = dict(passed=True, real_child_start_stop=True, http_ticket_redemption=True,
                      afk_policy=True, showcase_read_only_visitor=True,
                      showcase_ticket_redemption=True,
                      replay_rejected=True, admin_private_bypass=True, multiplayer_roster=True,
                      second_inventory=True, second_respawn=True, enclosed_drone=True,
                      empty_respawn=True, ghost_hud_trimmed=True, physical_cafe_turfs=0,
                      lore_papers=expected_lore, return_button_order=True,
                      generations=[generation, generation2])
        (data / "result.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
    finally:
        run = current()
        if run:
            try:
                api("stop", {"world": run["world"]})
                deadline = time.time() + 30
                while time.time() < deadline and current():
                    time.sleep(1)
            except Exception:
                pass
            if current():
                print("Test child retained for diagnosis; see test data directory.")


if __name__ == "__main__":
    main()
